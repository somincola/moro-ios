import Darwin
import Foundation
import UniformTypeIdentifiers

enum MoroShareExtensionSharedContainer {
    static let appGroupIdentifier = "group.com.somincola.moro.app"
    static func sharedUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
    static func stagingDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("ComposeDraftStaging", isDirectory: true)
    }

    /// Must match `SharedComposeDraftStagingStore.cancelledMarkerPrefix` in the app.
    static let cancelledMarkerPrefix = ".cancelled-"

    /// The critical section is a few milliseconds, so ordinary contention between the app
    /// and the extension is retried briefly instead of surfacing as a failure. The wait is
    /// bounded and never blocks indefinitely while the process could be suspended.
    static func acquireIndexLock(_ descriptor: Int32, attempts: Int = 20, interval: useconds_t = 10_000) -> Bool {
        for attempt in 0..<attempts {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else { return false }
            if attempt + 1 < attempts { usleep(interval) }
        }
        return false
    }
}

struct MoroShareExtensionBootstrapSnapshot: Decodable {
    struct SnapshotAccount: Decodable { let id: String }
    let account: SnapshotAccount
}

final class MoroShareExtensionSessionBootstrapReader {
    private let userDefaults: UserDefaults
    init(userDefaults: UserDefaults = MoroShareExtensionSharedContainer.sharedUserDefaults()) {
        self.userDefaults = userDefaults
    }
    func loadActiveAccountID() -> String? {
        guard let data = userDefaults.data(forKey: "shared_active_account_session_snapshot_v1") else { return nil }
        return (try? JSONDecoder().decode(MoroShareExtensionBootstrapSnapshot.self, from: data))?.account.id
    }
}

enum MoroShareExtensionInputError: Error {
    case noContent, tooManyImages, unreadableImage, unreadableVideo, videoMustBeAlone, sharedContainerUnavailable
    var message: String {
        switch self {
        case .noContent: return L("share.error.noContent")
        case .tooManyImages: return L("share.error.tooManyImages")
        case .unreadableImage: return L("share.error.unreadableImage")
        case .unreadableVideo: return L("share.error.unreadableVideo")
        case .videoMustBeAlone: return L("share.error.videoMustBeAlone")
        case .sharedContainerUnavailable: return L("share.error.importFailed")
        }
    }
}

struct MoroShareExtensionPreparedAttachment {
    let sourceURL: URL
    let fileName: String
    let mimeType: String
    let id: String
}

struct MoroShareExtensionLoadedContent {
    let text: String
    let attachments: [MoroShareExtensionPreparedAttachment]
    let temporaryDirectoryURL: URL

    var hasSubstantivePayload: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    func removeTemporaryFiles() { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
}

enum MoroShareExtensionInputLoader {
    static func load(from inputItems: [Any]) async throws -> MoroShareExtensionLoadedContent {
        let items = inputItems.compactMap { $0 as? NSExtensionItem }
        let providers = items.flatMap { $0.attachments ?? [] }
        let media = providers.filter { isMedia($0) }
        let videos = media.filter { isVideo($0) }
        guard videos.isEmpty || media.count == 1 else { throw MoroShareExtensionInputError.videoMustBeAlone }
        guard media.count <= 4 else { throw MoroShareExtensionInputError.tooManyImages }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moro-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var textParts = items.compactMap { $0.attributedContentText?.string }
            // A Photos file URL is transport metadata, never a post's body.
            if let provider = providers.first(where: {
                !isMedia($0)
                    && $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            }), let text = await loadString(provider, type: UTType.plainText.identifier) {
                textParts.append(text)
            }
            if let provider = providers.first(where: {
                !isMedia($0)
                    && !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    && $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            }), let text = await loadString(provider, type: UTType.url.identifier) {
                textParts.append(text)
            }
            var attachments: [MoroShareExtensionPreparedAttachment] = []
            // Keep originals on disk. Video data must never be loaded into the extension's
            // small memory budget; the app prepares it after the handoff.
            for (index, provider) in media.enumerated() {
                try Task.checkCancellation()
                let isVideo = Self.isVideo(provider)
                let contentType: UTType = isVideo ? .movie : .image
                let identifier =
                    provider.registeredTypeIdentifiers.first {
                        guard let type = UTType($0) else { return false }
                        return type.conforms(to: contentType) && type.preferredMIMEType != nil
                    } ?? contentType.identifier
                let type = UTType(identifier)
                let id = UUID().uuidString
                let ext = type?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")
                let fallbackName = "\(isVideo ? "video" : "image")-\(index + 1)"
                let suggested = (provider.suggestedName ?? fallbackName) as NSString
                let name = suggested.deletingPathExtension
                    .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
                let fileName = "\(name.isEmpty ? fallbackName : name).\(ext)"
                let destination = directory.appendingPathComponent("\(id).\(ext)")
                do {
                    try await provider.moro_copyFileRepresentation(type: identifier, to: destination)
                } catch {
                    try Task.checkCancellation()
                    guard !isVideo else { throw MoroShareExtensionInputError.unreadableVideo }
                    let data: Data
                    do { data = try await provider.moro_loadDataRepresentation(type: identifier) } catch {
                        throw MoroShareExtensionInputError.unreadableImage
                    }
                    try data.write(to: destination, options: .atomic)
                }
                try Task.checkCancellation()
                let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 else {
                    throw isVideo ? MoroShareExtensionInputError.unreadableVideo : MoroShareExtensionInputError.unreadableImage
                }
                attachments.append(
                    .init(
                        sourceURL: destination, fileName: fileName,
                        mimeType: type?.preferredMIMEType ?? (isVideo ? "video/quicktime" : "image/jpeg"), id: id))
            }
            var distinctText: [String] = []
            for text in textParts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !text.isEmpty && !distinctText.contains(text) { distinctText.append(text) }
            let content = MoroShareExtensionLoadedContent(
                text: distinctText.joined(separator: "\n"),
                attachments: attachments, temporaryDirectoryURL: directory)
            guard content.hasSubstantivePayload else { throw MoroShareExtensionInputError.noContent }
            return content
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func isMedia(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
    }

    private static func isVideo(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            && !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    }

    private static func loadString(_ provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                let value = (item as? String) ?? (item as? NSAttributedString)?.string ?? (item as? URL)?.absoluteString
                continuation.resume(returning: value)
            }
        }
    }
}

/// Mirrors the app's additive Codable staging schema. No credentials cross this boundary.
private struct MoroShareExtensionDraftMediaAttachment: Encodable {}
private struct MoroShareExtensionDraftTarget: Encodable { let kind: String }
private struct MoroShareExtensionDraftPayload: Encodable {
    let content: String
    let contentWarning = ""
    let isContentWarningActive = false
    let visibility = "public"
    let mediaAttachments: [MoroShareExtensionDraftMediaAttachment] = []
    let isPollActive = false
    let pollOptions: [String] = []
    let pollMultiple = false
    let pollExpiresIn = 86400
    let isSchedulingEnabled = false
    let selectedLanguageCode = ""
    let quotePolicyRawValue = "public"
}
private struct MoroShareExtensionAttachmentReference: Encodable {
    let id: String
    let fileName: String
    let mimeType: String
    let relativePath: String
}
private struct MoroShareExtensionStagingItem: Encodable {
    let id: String
    let accountID: String?
    let sourceApplication: String?
    let target: MoroShareExtensionDraftTarget
    let payload: MoroShareExtensionDraftPayload
    let attachments: [MoroShareExtensionAttachmentReference]
    let createdAt: Date
}

final class MoroShareExtensionDraftStagingStore {
    private let userDefaults: UserDefaults
    private let baseDirectoryURL: URL?
    private let fileManager: FileManager
    private let transferFile: (URL, URL) throws -> Void
    private let key = "shared_compose_draft_staging_items_v1"
    private let corruptBackupKey = "shared_compose_draft_staging_items_v1_corrupt_backup"

    init(
        userDefaults: UserDefaults = MoroShareExtensionSharedContainer.sharedUserDefaults(),
        baseDirectoryURL: URL? = MoroShareExtensionSharedContainer.stagingDirectory(),
        fileManager: FileManager = .default, transferFile: ((URL, URL) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
        self.transferFile = transferFile ?? { try fileManager.moveItem(at: $0, to: $1) }
    }

    func stage(accountID: String?, content: MoroShareExtensionLoadedContent) throws -> String {
        guard let baseDirectoryURL else { throw MoroShareExtensionInputError.sharedContainerUnavailable }
        try Task.checkCancellation()
        let id = UUID().uuidString
        let directory = baseDirectoryURL.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var references: [MoroShareExtensionAttachmentReference] = []
            for attachment in content.attachments {
                try Task.checkCancellation()
                // IDs make duplicate filenames and cross-directory paths impossible.
                let ext = attachment.sourceURL.pathExtension
                let name = attachment.id + (ext.isEmpty ? "" : "." + ext)
                // These are owned temporary copies, never the provider's originals.
                // Moving them avoids a second full-size copy and never holds the index lock.
                try transferFile(attachment.sourceURL, directory.appendingPathComponent(name))
                try Task.checkCancellation()
                references.append(
                    .init(
                        id: attachment.id, fileName: attachment.fileName,
                        mimeType: attachment.mimeType, relativePath: "\(id)/\(name)"))
            }
            let item = MoroShareExtensionStagingItem(
                id: id, accountID: accountID, sourceApplication: "ShareExtension",
                target: .init(kind: "newPost"), payload: .init(content: content.text),
                attachments: references, createdAt: Date())
            let encoded = try JSONEncoder().encode(item)
            guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                throw CocoaError(.fileWriteUnknown)
            }
            try withIndexLock {
                try Task.checkCancellation()
                var items = try loadItems()
                items.append(object)
                try saveItems(items)
            }
            return id
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func remove(itemID: String) throws {
        guard UUID(uuidString: itemID) != nil else { return }
        defer {
            if let baseDirectoryURL { try? fileManager.removeItem(at: baseDirectoryURL.appendingPathComponent(itemID)) }
        }
        do {
            try withIndexLock {
                try saveItems(try loadItems().filter { ($0["id"] as? String) != itemID })
            }
        } catch {
            // A cancelled share must never reach the editor later. When the index
            // cannot be updated, leave a tombstone the app honours and purges.
            markCancelled(itemID: itemID)
            throw error
        }
    }

    private func markCancelled(itemID: String) {
        guard let baseDirectoryURL else { return }
        let marker = baseDirectoryURL.appendingPathComponent(MoroShareExtensionSharedContainer.cancelledMarkerPrefix + itemID)
        _ = fileManager.createFile(atPath: marker.path, contents: Data())
    }

    private func loadItems() throws -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            // An unreadable index would otherwise block every future share. Keep the
            // first unreadable copy for diagnosis and continue with a fresh index.
            if userDefaults.data(forKey: corruptBackupKey) == nil {
                userDefaults.set(data, forKey: corruptBackupKey)
            }
            return []
        }
        return items
    }
    private func saveItems(_ items: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        userDefaults.set(data, forKey: key)
        userDefaults.synchronize()
        guard userDefaults.data(forKey: key) == data else { throw CocoaError(.fileWriteUnknown) }
    }

    private func withIndexLock<T>(_ operation: () throws -> T) throws -> T {
        guard let baseDirectoryURL else { throw MoroShareExtensionInputError.sharedContainerUnavailable }
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        let descriptor = Darwin.open(
            baseDirectoryURL.appendingPathComponent(".index.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        guard MoroShareExtensionSharedContainer.acquireIndexLock(descriptor) else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        userDefaults.synchronize()
        return try operation()
    }
}

actor MoroShareExtensionImportService {
    private let store = MoroShareExtensionDraftStagingStore()
    private var isCancelled = false
    private var stagedItemID: String?
    func prepare(inputItems: [Any], accountID: String?) async throws -> String {
        guard !isCancelled else { throw CancellationError() }
        let content = try await MoroShareExtensionInputLoader.load(from: inputItems)
        defer { content.removeTemporaryFiles() }
        try Task.checkCancellation()
        guard !isCancelled else { throw CancellationError() }
        let id = try store.stage(accountID: accountID, content: content)
        stagedItemID = id
        return id
    }
    func cancel(itemID: String? = nil) {
        isCancelled = true
        // The actor owns the ID before it is delivered to the controller. Cancellation
        // can therefore clean a just-committed item without awaiting a slow provider.
        if let id = itemID ?? stagedItemID { try? store.remove(itemID: id) }
    }
}

extension NSItemProvider {
    fileprivate func moro_copyFileRepresentation(type: String, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url, error == nil else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    fileprivate func moro_loadDataRepresentation(type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: type) { data, error in
                guard let data, error == nil else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
