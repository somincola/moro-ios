//
//  ShareSupport.swift
//  moroShareExtension
//
//  Shared-container helpers for the Share Extension MVP.
//

import Foundation
import UniformTypeIdentifiers

enum MoroShareExtensionSharedContainer {
    static let appGroupIdentifier = "group.com.somincola.moro.app"
    static let composeDraftStagingDirectoryName = "ComposeDraftStaging"

    static func sharedUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func sharedContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func composeDraftStagingDirectoryURL(fileManager: FileManager = .default) -> URL {
        let baseURL = sharedContainerURL(fileManager: fileManager)
            ?? fileManager.temporaryDirectory.appendingPathComponent("moro-shared", isDirectory: true)
        return baseURL.appendingPathComponent(composeDraftStagingDirectoryName, isDirectory: true)
    }
}

struct MoroShareExtensionBootstrapSnapshot: Decodable {
    struct SnapshotAccount: Decodable {
        let id: String
    }

    let account: SnapshotAccount
}

final class MoroShareExtensionSessionBootstrapReader {
    private enum Keys {
        static let snapshot = "shared_active_account_session_snapshot_v1"
    }

    private let userDefaults: UserDefaults
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = MoroShareExtensionSharedContainer.sharedUserDefaults()) {
        self.userDefaults = userDefaults
    }

    func loadActiveAccountID() -> String? {
        guard let data = userDefaults.data(forKey: Keys.snapshot),
              let snapshot = try? decoder.decode(MoroShareExtensionBootstrapSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.account.id
    }
}

struct MoroShareExtensionPreparedAttachment {
    let data: Data
    let fileName: String
    let mimeType: String
    let id: String

    init(
        data: Data,
        fileName: String,
        mimeType: String,
        id: String = UUID().uuidString
    ) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.id = id
    }
}

struct MoroShareExtensionLoadedContent {
    let text: String
    let attachments: [MoroShareExtensionPreparedAttachment]

    var hasSubstantivePayload: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var summaryText: String {
        var parts: [String] = []

        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(L("share.summary.text"))
        }

        if !attachments.isEmpty {
            parts.append(L("share.summary.images", Int64(attachments.count)))
        }

        return parts.isEmpty ? L("share.error.noContent") : parts.joined(separator: L("share.summary.separator"))
    }
}

enum MoroShareExtensionInputLoader {
    static func load(from inputItems: [Any]) async -> MoroShareExtensionLoadedContent {
        let extensionItems = inputItems.compactMap { $0 as? NSExtensionItem }
        let itemProviders = extensionItems.flatMap { $0.attachments ?? [] }

        let textProvider = itemProviders.first {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        let urlProvider = itemProviders.first {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        let imageProviders = itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }

        async let text = loadPlainText(from: textProvider)
        async let url = loadURLString(from: urlProvider)
        let attachments = await loadImageAttachments(from: Array(imageProviders.prefix(4)))

        var parts: [String] = []
        if let text = await text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            parts.append(text)
        }

        if let url = await url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty,
           !parts.contains(url) {
            parts.append(url)
        }

        return MoroShareExtensionLoadedContent(
            text: parts.joined(separator: "\n"),
            attachments: attachments
        )
    }

    private static func loadPlainText(from provider: NSItemProvider?) async -> String? {
        guard let provider else { return nil }

        do {
            let item = try await provider.moro_loadItem(forTypeIdentifier: UTType.plainText.identifier)
            if let text = item as? String {
                return text
            }
            if let attributed = item as? NSAttributedString {
                return attributed.string
            }
            if let url = item as? URL {
                return url.absoluteString
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func loadURLString(from provider: NSItemProvider?) async -> String? {
        guard let provider else { return nil }

        do {
            let item = try await provider.moro_loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = item as? URL {
                return url.absoluteString
            }
            if let text = item as? String {
                return text
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func loadImageAttachments(
        from providers: [NSItemProvider]
    ) async -> [MoroShareExtensionPreparedAttachment] {
        var attachments: [MoroShareExtensionPreparedAttachment] = []

        for (index, provider) in providers.enumerated() {
            guard let attachment = await loadImageAttachment(from: provider, index: index) else {
                continue
            }
            attachments.append(attachment)
        }

        return attachments
    }

    private static func loadImageAttachment(
        from provider: NSItemProvider,
        index: Int
    ) async -> MoroShareExtensionPreparedAttachment? {
        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        let type = UTType(typeIdentifier)
        let mimeType = type?.preferredMIMEType ?? "image/jpeg"
        let fileExtension = type?.preferredFilenameExtension ?? "jpg"
        let baseName = sanitizedFileBaseName(provider.suggestedName, fallback: "shared-image-\(index + 1)")
        let fileName = "\(baseName).\(fileExtension)"

        do {
            let data = try await provider.moro_loadDataRepresentation(forTypeIdentifier: typeIdentifier)
            return MoroShareExtensionPreparedAttachment(
                data: data,
                fileName: fileName,
                mimeType: mimeType
            )
        } catch {
            do {
                let data = try await provider.moro_loadFileDataRepresentation(forTypeIdentifier: typeIdentifier)
                return MoroShareExtensionPreparedAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            } catch {
                return nil
            }
        }
    }

    private static func sanitizedFileBaseName(_ value: String?, fallback: String) -> String {
        let rawValue = (value ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedExtension = (rawValue as NSString).deletingPathExtension
        let candidate = strippedExtension.isEmpty ? fallback : strippedExtension
        let invalidScalars = CharacterSet(charactersIn: "/:\\")
        let sanitized = candidate.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? "-" : Character(scalar)
        }
        return String(sanitized)
    }
}

private struct MoroShareExtensionDraftMediaAttachment: Codable {}

private struct MoroShareExtensionDraftTarget: Codable {
    let kind: String
    let referenceStatus: String?
    let inReplyToID: String?
    let quotingID: String?

    init(
        kind: String,
        referenceStatus: String? = nil,
        inReplyToID: String? = nil,
        quotingID: String? = nil
    ) {
        self.kind = kind
        self.referenceStatus = referenceStatus
        self.inReplyToID = inReplyToID
        self.quotingID = quotingID
    }
}

private struct MoroShareExtensionDraftPayload: Codable {
    let content: String
    let contentWarning: String
    let isContentWarningActive: Bool
    let visibility: String
    let mediaAttachments: [MoroShareExtensionDraftMediaAttachment]
    let isPollActive: Bool
    let pollOptions: [String]
    let pollMultiple: Bool
    let pollExpiresIn: Int
    let isSchedulingEnabled: Bool
    let scheduledAt: Date?
    let selectedLanguageCode: String
    let quotePolicyRawValue: String
}

private struct MoroShareExtensionAttachmentReference: Codable {
    let id: String
    let fileName: String
    let mimeType: String
    let relativePath: String
}

private struct MoroShareExtensionStagingItem: Codable {
    let id: String
    let accountID: String?
    let sourceApplication: String?
    let target: MoroShareExtensionDraftTarget
    let payload: MoroShareExtensionDraftPayload
    let attachments: [MoroShareExtensionAttachmentReference]
    let createdAt: Date
}

final class MoroShareExtensionDraftStagingStore {
    private enum Keys {
        static let items = "shared_compose_draft_staging_items_v1"
    }

    private let userDefaults: UserDefaults
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = MoroShareExtensionSharedContainer.sharedUserDefaults(),
        baseDirectoryURL: URL = MoroShareExtensionSharedContainer.composeDraftStagingDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
    }

    func stage(
        accountID: String?,
        sourceApplication: String?,
        content: MoroShareExtensionLoadedContent,
        now: Date = Date()
    ) throws {
        try ensureBaseDirectory()

        let itemID = UUID().uuidString
        let itemDirectoryURL = baseDirectoryURL.appendingPathComponent(itemID, isDirectory: true)
        try fileManager.createDirectory(
            at: itemDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var attachmentReferences: [MoroShareExtensionAttachmentReference] = []
        do {
            for attachment in content.attachments {
                let destinationURL = try writeAttachment(
                    attachment,
                    into: itemDirectoryURL
                )
                attachmentReferences.append(
                    MoroShareExtensionAttachmentReference(
                        id: attachment.id,
                        fileName: destinationURL.lastPathComponent,
                        mimeType: attachment.mimeType,
                        relativePath: "\(itemID)/\(destinationURL.lastPathComponent)"
                    )
                )
            }
        } catch {
            try? fileManager.removeItem(at: itemDirectoryURL)
            throw error
        }

        let item = MoroShareExtensionStagingItem(
            id: itemID,
            accountID: accountID,
            sourceApplication: sourceApplication,
            target: MoroShareExtensionDraftTarget(kind: "newPost"),
            payload: MoroShareExtensionDraftPayload(
                content: content.text,
                contentWarning: "",
                isContentWarningActive: false,
                visibility: "public",
                mediaAttachments: [],
                isPollActive: false,
                pollOptions: [],
                pollMultiple: false,
                pollExpiresIn: 86400,
                isSchedulingEnabled: false,
                scheduledAt: nil,
                selectedLanguageCode: "",
                quotePolicyRawValue: "public"
            ),
            attachments: attachmentReferences,
            createdAt: now
        )

        var items = loadItems()
        items.append(item)
        saveItems(items)
    }

    private func loadItems() -> [MoroShareExtensionStagingItem] {
        guard let data = userDefaults.data(forKey: Keys.items) else { return [] }
        return (try? decoder.decode([MoroShareExtensionStagingItem].self, from: data)) ?? []
    }

    private func saveItems(_ items: [MoroShareExtensionStagingItem]) {
        guard let data = try? encoder.encode(items) else { return }
        userDefaults.set(data, forKey: Keys.items)
    }

    private func ensureBaseDirectory() throws {
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func writeAttachment(
        _ attachment: MoroShareExtensionPreparedAttachment,
        into directoryURL: URL
    ) throws -> URL {
        let destinationURL = uniqueDestinationURL(
            preferredFileName: sanitizedFileName(attachment.fileName),
            in: directoryURL
        )
        try attachment.data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func uniqueDestinationURL(
        preferredFileName: String,
        in directoryURL: URL
    ) -> URL {
        let nsFileName = preferredFileName as NSString
        let baseName = nsFileName.deletingPathExtension
        let pathExtension = nsFileName.pathExtension

        var candidateURL = directoryURL.appendingPathComponent(preferredFileName, isDirectory: false)
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            let candidateName = pathExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(pathExtension)"
            candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false)
            suffix += 1
        }

        return candidateURL
    }

    private func sanitizedFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UUID().uuidString }

        let invalidScalars = CharacterSet(charactersIn: "/:\\")
        let sanitized = trimmed.unicodeScalars.map { scalar in
            invalidScalars.contains(scalar) ? "-" : Character(scalar)
        }

        return String(sanitized)
    }
}

private extension NSItemProvider {
    func moro_loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let item else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }

                continuation.resume(returning: item)
            }
        }
    }

    func moro_loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    func moro_loadFileDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }

                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
