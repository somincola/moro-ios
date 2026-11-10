//
//  ComposeDraftStore.swift
//  moro
//
//  Compose payload models plus shared staging used by share import and re-draft flows.
//

import Foundation
import Darwin

nonisolated private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

nonisolated enum ComposeDraftCategory: String, Codable, Equatable {
    case auto
    case manual
}

nonisolated struct ComposeDraftAttachment: Codable, Equatable, Identifiable {
    let id: String
    let url: URL
    let previewURL: URL?
    let type: String
    let description: String?
    let focus: String?
    var sharedImportItemID: String? = nil
    var sharedImportAttachmentID: String? = nil

    init(
        id: String,
        url: URL,
        previewURL: URL?,
        type: String,
        description: String?,
        focus: String?
    ) {
        self.id = id
        self.url = url
        self.previewURL = previewURL
        self.type = type
        self.description = description
        self.focus = focus
    }

    init(_ attachment: MediaAttachment) {
        self.init(
            id: attachment.id,
            url: attachment.url,
            previewURL: attachment.previewURL,
            type: attachment.type,
            description: attachment.description,
            focus: attachment.focus
        )
        sharedImportItemID = attachment.sharedImportItemID
        sharedImportAttachmentID = attachment.sharedImportAttachmentID
    }

    var mediaAttachment: MediaAttachment {
        var attachment = MediaAttachment(
            id: id,
            url: url,
            previewURL: previewURL,
            type: type,
            description: description,
            focus: focus,
            uploadState: .uploaded
        )
        attachment.sharedImportItemID = sharedImportItemID
        attachment.sharedImportAttachmentID = sharedImportAttachmentID
        return attachment
    }
}

nonisolated struct ComposeDraftTarget: Codable, Equatable, Hashable {
    nonisolated enum Kind: String, Codable {
        case newPost
        case reply
        case quote
    }

    let kind: Kind
    let referenceStatus: Status?
    let inReplyToID: String?
    let quotingID: String?

    init(
        kind: Kind,
        referenceStatus: Status? = nil,
        inReplyToID: String? = nil,
        quotingID: String? = nil
    ) {
        self.kind = kind
        self.referenceStatus = referenceStatus
        self.inReplyToID = inReplyToID
        self.quotingID = quotingID
    }

    var matchKey: String {
        switch kind {
        case .newPost:
            return "newPost"
        case .reply:
            return "reply:\(inReplyToID ?? referenceStatus?.id ?? "unknown")"
        case .quote:
            return "quote:\(quotingID ?? referenceStatus?.id ?? "unknown")"
        }
    }

    var composeContext: ComposeViewModel.ComposeContext {
        switch kind {
        case .newPost:
            return .newPost
        case .reply:
            return .reply(to: referenceStatus)
        case .quote:
            return .quote(original: referenceStatus)
        }
    }
}

nonisolated struct ComposeDraftPayload: Codable, Equatable {
    let content: String
    let contentWarning: String
    let isContentWarningActive: Bool
    let visibility: MastodonVisibility
    let mediaAttachments: [ComposeDraftAttachment]
    let isPollActive: Bool
    let pollOptions: [String]
    let pollMultiple: Bool
    let pollExpiresIn: Int
    let isSchedulingEnabled: Bool
    let scheduledAt: Date?
    let selectedLanguageCode: String
    let quotePolicyRawValue: String

    var hasSubstantivePayload: Bool {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWarning = contentWarning.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPollOptions = pollOptions.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return !trimmedContent.isEmpty
            || (isContentWarningActive && !trimmedWarning.isEmpty)
            || !mediaAttachments.isEmpty
            || (isPollActive && hasPollOptions)
    }

    var previewText: String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent
        }

        let trimmedWarning = contentWarning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWarning.isEmpty {
            return trimmedWarning
        }

        if let pollPreview = pollOptions
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        {
            return pollPreview
        }

        return ""
    }
}

nonisolated extension ComposeDraftPayload {
    nonisolated private enum CodingKeys: String, CodingKey {
        case content
        case contentWarning
        case isContentWarningActive
        case visibility
        case mediaAttachments
        case isPollActive
        case pollOptions
        case pollMultiple
        case pollExpiresIn
        case isSchedulingEnabled
        case scheduledAt
        case selectedLanguageCode
        case quotePolicyRawValue
    }

    /// Drafts are long-lived user data. Decode additive fields with safe defaults so
    /// a newer app can still recover drafts written by an older schema.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        contentWarning = try container.decodeIfPresent(String.self, forKey: .contentWarning) ?? ""
        isContentWarningActive = try container.decodeIfPresent(Bool.self, forKey: .isContentWarningActive) ?? false
        visibility = try container.decodeIfPresent(MastodonVisibility.self, forKey: .visibility) ?? .public
        mediaAttachments = try container.decodeIfPresent([ComposeDraftAttachment].self, forKey: .mediaAttachments) ?? []
        isPollActive = try container.decodeIfPresent(Bool.self, forKey: .isPollActive) ?? false
        pollOptions = try container.decodeIfPresent([String].self, forKey: .pollOptions) ?? ["", ""]
        pollMultiple = try container.decodeIfPresent(Bool.self, forKey: .pollMultiple) ?? false
        pollExpiresIn = try container.decodeIfPresent(Int.self, forKey: .pollExpiresIn) ?? 24 * 60 * 60
        isSchedulingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSchedulingEnabled) ?? false
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        selectedLanguageCode = try container.decodeIfPresent(String.self, forKey: .selectedLanguageCode) ?? ""
        quotePolicyRawValue = try container.decodeIfPresent(String.self, forKey: .quotePolicyRawValue)
            ?? ComposeViewModel.QuotePolicy.anyone.rawValue
    }
}

nonisolated struct ComposeDraft: Identifiable, Codable, Equatable {
    let id: String
    let accountID: String?
    var category: ComposeDraftCategory
    let target: ComposeDraftTarget
    var payload: ComposeDraftPayload
    let createdAt: Date
    var updatedAt: Date
    var publishAttempt: ComposePublishAttempt? = nil
    /// Import provenance is persisted with the text/media so retries never append twice.
    var sharedImportItemIDs: [String]? = nil

    var displayPreviewText: String {
        let preview = payload.previewText
        return preview.isEmpty ? MoroL10n.ComposeDrafts.untitled : preview
    }

    var contextLabel: String {
        switch target.kind {
        case .newPost:
            return MoroL10n.ComposeDrafts.contextNewPost
        case .reply:
            return MoroL10n.ComposeDrafts.contextReply
        case .quote:
            return MoroL10n.ComposeDrafts.contextQuote
        }
    }

    var categoryLabel: String {
        switch category {
        case .auto:
            return MoroL10n.ComposeDrafts.badgeAuto
        case .manual:
            return MoroL10n.ComposeDrafts.badgeManual
        }
    }

    static func redraft(from status: Status, accountID: String?) -> ComposeDraft {
        let displayStatus = status.displayStatus
        let quoteStatus = displayStatus.quote?.displayableStatus?.displayStatus

        let target: ComposeDraftTarget
        if let quoteStatus {
            target = ComposeDraftTarget(
                kind: .quote,
                referenceStatus: quoteStatus,
                quotingID: quoteStatus.id
            )
        } else if let inReplyToID = displayStatus.inReplyToID {
            target = ComposeDraftTarget(
                kind: .reply,
                referenceStatus: nil,
                inReplyToID: inReplyToID
            )
        } else {
            target = ComposeDraftTarget(kind: .newPost)
        }

        let pollOptions = displayStatus.poll?.options.map(\.title) ?? ["", ""]
        let normalizedPollOptions = pollOptions.isEmpty ? ["", ""] : pollOptions
        let payload = ComposeDraftPayload(
            content: HTMLParser.stripHTML(displayStatus.content),
            contentWarning: displayStatus.spoilerText ?? "",
            isContentWarningActive: !(displayStatus.spoilerText?.isEmpty ?? true),
            visibility: MastodonVisibility(rawValue: displayStatus.visibility ?? "public") ?? .public,
            mediaAttachments: [],
            isPollActive: displayStatus.poll != nil,
            pollOptions: normalizedPollOptions,
            pollMultiple: displayStatus.poll?.multiple ?? false,
            pollExpiresIn: 24 * 60 * 60,
            isSchedulingEnabled: false,
            scheduledAt: nil,
            selectedLanguageCode: displayStatus.language ?? "",
            quotePolicyRawValue: ComposeViewModel.QuotePolicy.anyone.rawValue
        )

        let now = Date()
        return ComposeDraft(
            id: UUID().uuidString,
            accountID: accountID,
            category: .manual,
            target: target,
            payload: payload,
            createdAt: now,
            updatedAt: now
        )
    }
}

nonisolated struct SharedComposeDraftAttachmentInput {
    let sourceURL: URL
    let fileName: String
    let mimeType: String
    let id: String

    init(
        sourceURL: URL,
        fileName: String? = nil,
        mimeType: String,
        id: String = UUID().uuidString
    ) {
        self.sourceURL = sourceURL
        self.fileName = fileName ?? sourceURL.lastPathComponent
        self.mimeType = mimeType
        self.id = id
    }
}

nonisolated struct SharedComposeDraftAttachmentReference: Codable, Equatable, Identifiable {
    let id: String
    let fileName: String
    let mimeType: String
    let relativePath: String
}

nonisolated struct SharedComposeDraftStagingItem: Codable, Equatable, Identifiable {
    let id: String
    let accountID: String?
    let sourceApplication: String?
    let target: ComposeDraftTarget
    let payload: ComposeDraftPayload
    let attachments: [SharedComposeDraftAttachmentReference]
    let createdAt: Date

    var hasAttachments: Bool {
        !attachments.isEmpty
    }

    func asManualDraft(now: Date = Date()) -> ComposeDraft {
        ComposeDraft(
            id: ComposeDraftStore.sharedDraftIDPrefix + id,
            accountID: accountID,
            category: .manual,
            target: target,
            payload: payload,
            createdAt: createdAt,
            updatedAt: now
        )
    }

    func asImportRecoveryDraft(accountID activeAccountID: String? = nil, now: Date = Date()) -> ComposeDraft {
        var draft = ComposeDraft(id: ComposeDraftStore.sharedDraftIDPrefix + id,
            accountID: accountID ?? activeAccountID, category: .auto, target: target, payload: payload,
            createdAt: createdAt, updatedAt: now)
        draft.sharedImportItemIDs = [id]
        return draft
    }
}

final class SharedComposeDraftStagingStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = SharedComposeDraftStagingStore(
        userDefaults: MoroSharedContainer.sharedUserDefaults(),
        baseDirectoryURL: MoroSharedContainer.composeDraftStagingDirectoryURL()
    )

    nonisolated private enum Keys {
        static let items = "shared_compose_draft_staging_items_v1"
        static let corruptBackup = "shared_compose_draft_staging_items_v1_corrupt_backup"
    }

    nonisolated enum PersistenceError: Error {
        case writeVerificationFailed
        case indexLockUnavailable
        case indexCorrupt
    }

    private let userDefaults: UserDefaults
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var didReportLockFailure = false

    init(
        userDefaults: UserDefaults,
        baseDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.baseDirectoryURL = baseDirectoryURL
        self.fileManager = fileManager
    }

    func pendingItems() -> [SharedComposeDraftStagingItem] {
        (try? withLock {
            loadItemsLocked().sorted { $0.createdAt < $1.createdAt }
        }) ?? []
    }

    /// A failed read must never look like an empty queue to the publish guard. A busy lock
    /// throws `.indexLockUnavailable`; an undecodable index throws `.indexCorrupt` (its raw
    /// copy is backed up) so callers can offer an explicit discard instead of a dead end.
    func pendingItemsForPublishing() throws -> [SharedComposeDraftStagingItem] {
        try withLock {
            guard let data = userDefaults.data(forKey: Keys.items) else { return [] }
            do {
                return purgingCancelledLocked(try decoder.decode([SharedComposeDraftStagingItem].self, from: data))
            } catch {
                if userDefaults.data(forKey: Keys.corruptBackup) == nil {
                    userDefaults.set(data, forKey: Keys.corruptBackup)
                }
                AppLogger.error("Shared compose staging index is unreadable: \(error)")
                throw PersistenceError.indexCorrupt
            }
        }
    }

    /// The person explicitly discarded these shares. Drop them even if the index cannot be
    /// decoded: valid entries of other shares are recovered and the index is rewritten, so
    /// one corrupt write cannot leave a draft that can be neither published nor discarded.
    @discardableResult
    func discardItems(ids: Set<String>) -> Bool {
        do {
            try withLock {
                let items = loadItemsLocked()
                try saveItemsLocked(items.filter { !ids.contains($0.id) })
            }
        } catch {
            AppLogger.error("Failed to discard shared compose items: \(error)")
            return false
        }
        for id in ids where UUID(uuidString: id) != nil {
            try? fileManager.removeItem(at: baseDirectoryURL.appendingPathComponent(id, isDirectory: true))
        }
        return true
    }

    @discardableResult
    func stage(
        accountID: String?,
        sourceApplication: String? = nil,
        target: ComposeDraftTarget,
        payload: ComposeDraftPayload,
        attachments: [SharedComposeDraftAttachmentInput] = [],
        now: Date = Date()
    ) throws -> SharedComposeDraftStagingItem {
        try ensureBaseDirectory()

        let itemID = UUID().uuidString
        let itemDirectoryURL = baseDirectoryURL.appendingPathComponent(itemID, isDirectory: true)
        try fileManager.createDirectory(
            at: itemDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var attachmentReferences: [SharedComposeDraftAttachmentReference] = []
        do {
            for attachment in attachments {
                let destinationURL = try copyAttachment(
                    attachment,
                    into: itemDirectoryURL
                )
                attachmentReferences.append(
                    SharedComposeDraftAttachmentReference(
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

        let item = SharedComposeDraftStagingItem(
            id: itemID,
            accountID: accountID,
            sourceApplication: sourceApplication,
            target: target,
            payload: payload,
            attachments: attachmentReferences,
            createdAt: now
        )

        do {
            try withLock {
                var items = loadItemsLocked()
                items.append(item)
                try saveItemsLocked(items)
            }
            return item
        } catch {
            try? fileManager.removeItem(at: itemDirectoryURL)
            throw error
        }
    }

    func attachmentFileURL(
        for attachment: SharedComposeDraftAttachmentReference
    ) -> URL {
        baseDirectoryURL.appendingPathComponent(attachment.relativePath, isDirectory: false)
    }

    func nextPendingItem() -> SharedComposeDraftStagingItem? {
        pendingItems().first
    }

    @discardableResult
    func removeItem(id: String) -> Bool {
        do {
            let removed = try withLock {
                var items = loadItemsLocked()
                let beforeCount = items.count
                items.removeAll { $0.id == id }
                guard items.count != beforeCount else { return false }

                try saveItemsLocked(items)
                return true
            }
            if removed {
                try? fileManager.removeItem(at: baseDirectoryURL.appendingPathComponent(id, isDirectory: true))
            }
            return removed
        } catch {
            AppLogger.error("Failed to persist shared draft removal: \(error)")
            return false
        }
    }

    /// Commits progress after each successful upload. Only unconsumed files remain in
    /// staging, so a cancellation or relaunch cannot upload completed attachments twice.
    @discardableResult
    func acknowledgeImportedAttachment(itemID: String, attachmentID: String) -> Bool {
        do {
            let consumedURL = try withLock { () -> URL? in
                var items = loadItemsLocked()
                guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
                    let importedAttachment = items[itemIndex].attachments.first(where: { $0.id == attachmentID })
                else {
                    return nil
                }

                let item = items[itemIndex]
                let remainingAttachments = item.attachments.filter { $0.id != attachmentID }
                if remainingAttachments.isEmpty {
                    items.remove(at: itemIndex)
                } else {
                    items[itemIndex] = SharedComposeDraftStagingItem(
                        id: item.id,
                        accountID: item.accountID,
                        sourceApplication: item.sourceApplication,
                        target: item.target,
                        payload: item.payload,
                        attachments: remainingAttachments,
                        createdAt: item.createdAt
                    )
                }

                try saveItemsLocked(items)
                return remainingAttachments.isEmpty
                    ? baseDirectoryURL.appendingPathComponent(itemID, isDirectory: true)
                    : attachmentFileURL(for: importedAttachment)
            }
            guard let consumedURL else { return false }
            try? fileManager.removeItem(at: consumedURL)
            return true
        } catch {
            AppLogger.error("Failed to persist shared attachment progress: \(error)")
            return false
        }
    }

    func clear() {
        do {
            let items = try withLock {
                let items = loadItemsLocked()
                userDefaults.removeObject(forKey: Keys.items)
                guard userDefaults.data(forKey: Keys.items) == nil else {
                    throw PersistenceError.writeVerificationFailed
                }
                return items
            }
            for item in items {
                try? fileManager.removeItem(
                    at: baseDirectoryURL.appendingPathComponent(item.id, isDirectory: true)
                )
            }
        } catch {
            AppLogger.error("Failed to clear shared compose staging: \(error)")
        }
    }

    private func loadItemsLocked() -> [SharedComposeDraftStagingItem] {
        purgingCancelledLocked(decodeItemsLocked())
    }

    private func decodeItemsLocked() -> [SharedComposeDraftStagingItem] {
        guard let data = userDefaults.data(forKey: Keys.items) else { return [] }
        do {
            return try decoder.decode([SharedComposeDraftStagingItem].self, from: data)
        } catch {
            if userDefaults.data(forKey: Keys.corruptBackup) == nil {
                userDefaults.set(data, forKey: Keys.corruptBackup)
            }
            if let recovered = try? decoder
                .decode([LossyDecodable<SharedComposeDraftStagingItem>].self, from: data)
                .compactMap(\.value),
               !recovered.isEmpty {
                AppLogger.error("Recovered valid entries from partially corrupt shared compose staging metadata")
                return recovered
            }
            AppLogger.error("Failed to decode shared compose staging metadata: \(error)")
            return []
        }
    }

    private func saveItemsLocked(_ items: [SharedComposeDraftStagingItem]) throws {
        let data = try encoder.encode(items)
        userDefaults.set(data, forKey: Keys.items)
        guard userDefaults.data(forKey: Keys.items) == data else {
            throw PersistenceError.writeVerificationFailed
        }
    }

    private func ensureBaseDirectory() throws {
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func copyAttachment(
        _ attachment: SharedComposeDraftAttachmentInput,
        into directoryURL: URL
    ) throws -> URL {
        let destinationURL = uniqueDestinationURL(
            preferredFileName: sanitizedFileName(attachment.fileName),
            in: directoryURL
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: attachment.sourceURL, to: destinationURL)
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

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        // The extension is another process. Synchronize the same index under a file
        // lock, so its append cannot race this process's per-attachment acknowledgement.
        do { try ensureBaseDirectory() } catch { reportLockFailure(); throw error }
        let descriptor = Darwin.open(
            baseDirectoryURL.appendingPathComponent(".index.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { reportLockFailure(); throw PersistenceError.indexLockUnavailable }
        defer { Darwin.close(descriptor) }
        guard Self.acquireIndexLock(descriptor) else {
            reportLockFailure()
            throw PersistenceError.indexLockUnavailable
        }
        defer { flock(descriptor, LOCK_UN) }
        didReportLockFailure = false
        defer {
            userDefaults.synchronize()
        }
        userDefaults.synchronize()
        return try operation()
    }

    /// Removes what nothing will ever import: shares nobody claimed for `maxUnclaimedAge`
    /// (their account was removed, or they were simply forgotten), and files or cancel
    /// markers left in the staging directory without an index entry (the extension was
    /// killed between moving files and committing the index). `claimedIDs` are shares a
    /// draft still owns; those are kept however old. Entries newer than `graceInterval`
    /// are left alone so a share being staged right now is never touched.
    @discardableResult
    func sweep(
        claimedIDs: Set<String>, now: Date = Date(),
        maxUnclaimedAge: TimeInterval = 7 * 24 * 3600, graceInterval: TimeInterval = 3600
    ) -> Int {
        var removed = 0
        var expired: Set<String> = []
        let indexedIDs: Set<String>
        do {
            indexedIDs = try withLock {
                let items = loadItemsLocked()
                expired = Set(items.filter {
                    !claimedIDs.contains($0.id) && now.timeIntervalSince($0.createdAt) > maxUnclaimedAge
                }.map(\.id))
                if !expired.isEmpty {
                    try saveItemsLocked(items.filter { !expired.contains($0.id) })
                }
                return Set(items.map(\.id)).subtracting(expired)
            }
        } catch {
            AppLogger.error("Skipped the shared compose staging sweep: \(error)")
            return 0
        }
        // File work happens outside the index lock.
        for id in expired {
            try? fileManager.removeItem(at: baseDirectoryURL.appendingPathComponent(id, isDirectory: true))
            removed += 1
        }
        let entries = (try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            let itemID = name.hasPrefix(Self.cancelledMarkerPrefix)
                ? String(name.dropFirst(Self.cancelledMarkerPrefix.count)) : name
            guard UUID(uuidString: itemID) != nil, !indexedIDs.contains(itemID) else { continue }
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            guard now.timeIntervalSince(modified) > graceInterval else { continue }
            if (try? fileManager.removeItem(at: entry)) != nil, !name.hasPrefix(Self.cancelledMarkerPrefix) {
                removed += 1
            }
        }
        return removed
    }

    /// Must match `MoroShareExtensionSharedContainer.cancelledMarkerPrefix`.
    nonisolated static let cancelledMarkerPrefix = ".cancelled-"

    /// Ordinary contention with the extension is retried briefly (≤ ~200 ms) instead of
    /// surfacing as a failure; the wait stays bounded so a suspended peer cannot hang us.
    nonisolated static func acquireIndexLock(
        _ descriptor: Int32, attempts: Int = 20, interval: useconds_t = 10_000
    ) -> Bool {
        for attempt in 0..<attempts {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else { return false }
            if attempt + 1 < attempts { usleep(interval) }
        }
        return false
    }

    private func cancelledMarkerURL(for itemID: String) -> URL {
        baseDirectoryURL.appendingPathComponent(Self.cancelledMarkerPrefix + itemID, isDirectory: false)
    }

    /// The extension leaves a tombstone when it cannot remove a cancelled item from the
    /// index. Such items are never offered to the editor; they are purged here instead.
    private func purgingCancelledLocked(_ items: [SharedComposeDraftStagingItem]) -> [SharedComposeDraftStagingItem] {
        let cancelled = items.filter { fileManager.fileExists(atPath: cancelledMarkerURL(for: $0.id).path) }
        guard !cancelled.isEmpty else { return items }
        let cancelledIDs = Set(cancelled.map(\.id))
        let remaining = items.filter { !cancelledIDs.contains($0.id) }
        do {
            try saveItemsLocked(remaining)
            for id in cancelledIDs {
                try? fileManager.removeItem(at: baseDirectoryURL.appendingPathComponent(id, isDirectory: true))
                try? fileManager.removeItem(at: cancelledMarkerURL(for: id))
            }
        } catch {
            AppLogger.error("Failed to purge cancelled shared compose items: \(error)")
        }
        return remaining
    }

    private func reportLockFailure() {
        guard !didReportLockFailure else { return }
        didReportLockFailure = true
        AppLogger.error("Shared compose staging index lock unavailable; operation skipped")
    }
}

final class ComposeDraftStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = ComposeDraftStore.makeSharedStore()

    nonisolated private enum Keys {
        static let drafts = "compose_drafts_v1"
        static let corruptBackup = "compose_drafts_v1_corrupt_backup"
    }

    private let userDefaults: UserDefaults
    private let legacyUserDefaults: UserDefaults?
    private let stagingStore: SharedComposeDraftStagingStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var cachedDrafts: [ComposeDraft]?

    private static func makeSharedStore() -> ComposeDraftStore {
        ComposeDraftStore(
            userDefaults: MoroSharedContainer.sharedUserDefaults(),
            legacyUserDefaults: .standard,
            stagingStore: .shared
        )
    }

    init(
        userDefaults: UserDefaults = .standard,
        legacyUserDefaults: UserDefaults? = nil,
        stagingStore: SharedComposeDraftStagingStore = .shared
    ) {
        self.userDefaults = userDefaults
        self.legacyUserDefaults = legacyUserDefaults
        self.stagingStore = stagingStore
        migrateLegacyDraftsIfNeeded()
    }

    func drafts(
        for accountID: String?,
        matching target: ComposeDraftTarget? = nil
    ) -> [ComposeDraft] {
        withLock {
            loadDraftsLocked()
                .filter { draft in
                    draft.accountID == accountID
                        && (target == nil || draft.target.matchKey == target?.matchKey)
                }
                .sorted { lhs, rhs in
                    if lhs.category != rhs.category {
                        return lhs.category == .manual
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }
        }
    }

    func draft(id: String) -> ComposeDraft? {
        withLock {
            loadDraftsLocked().first { $0.id == id }
        }
    }

    @discardableResult
    func save(_ draft: ComposeDraft) -> Bool {
        withLock {
            var drafts = loadDraftsLocked()
            if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                drafts[index] = replacing(drafts[index], with: draft)
            } else if draft.category == .auto, draft.sharedImportItemIDs?.isEmpty != false,
                      let index = drafts.firstIndex(where: {
                          $0.category == .auto
                              && $0.sharedImportItemIDs?.isEmpty != false
                              && $0.accountID == draft.accountID
                              && $0.target.matchKey == draft.target.matchKey
                      }) {
                // A failed retry or repeated autosave updates one recovery point per
                // compose context instead of growing an unbounded duplicate list.
                drafts[index] = replacing(
                    drafts[index],
                    with: draft,
                    savedID: draft.id
                )
            } else {
                drafts.append(draft)
            }
            return saveDraftsLocked(drafts)
        }
    }

    /// A draft made from a share is named after its staging item.
    nonisolated static let sharedDraftIDPrefix = "shared-"

    @discardableResult
    func removeDraft(id: String, removeStaging: Bool = true) -> Bool {
        var sharedIDs = Set(draft(id: id)?.sharedImportItemIDs ?? [])
        if id.hasPrefix(Self.sharedDraftIDPrefix) {
            sharedIDs.insert(String(id.dropFirst(Self.sharedDraftIDPrefix.count)))
        }
        if removeStaging, !sharedIDs.isEmpty {
            do {
                let stagedIDs = Set(try stagingStore.pendingItemsForPublishing().map(\.id))
                for sharedID in sharedIDs where stagedIDs.contains(sharedID) {
                    guard stagingStore.removeItem(id: sharedID) else { return false }
                }
            } catch SharedComposeDraftStagingStore.PersistenceError.indexCorrupt {
                // Discarding is explicit; repair the index rather than trapping the draft.
                guard stagingStore.discardItems(ids: sharedIDs) else { return false }
            } catch {
                AppLogger.error("Failed to remove shared staging before discarding draft: \(error)")
                return false
            }
        }
        let removed = withLock {
            var drafts = loadDraftsLocked()
            let beforeCount = drafts.count
            drafts.removeAll { $0.id == id }
            guard drafts.count != beforeCount else { return false }
            return saveDraftsLocked(drafts)
        }
        return removed
    }

    func draftForSharedImport(_ itemID: String, accountID: String?) -> ComposeDraft? {
        guard let owner = draftOwningSharedImport(itemID), owner.accountID == accountID else { return nil }
        return owner
    }

    func draftOwningSharedImport(_ itemID: String) -> ComposeDraft? {
        withLock { loadDraftsLocked().first {
            $0.id == Self.sharedDraftIDPrefix + itemID || $0.sharedImportItemIDs?.contains(itemID) == true
        } }
    }

    func pendingSharedStagingItems() -> [SharedComposeDraftStagingItem] {
        stagingStore.pendingItems()
    }

    func pendingSharedStagingItemsForPublishing() throws -> [SharedComposeDraftStagingItem] {
        try stagingStore.pendingItemsForPublishing()
    }

    func nextPendingSharedStagingItem() -> SharedComposeDraftStagingItem? {
        stagingStore.nextPendingItem()
    }

    @discardableResult
    func stageSharedDraft(
        accountID: String?,
        sourceApplication: String? = nil,
        target: ComposeDraftTarget,
        payload: ComposeDraftPayload,
        attachments: [SharedComposeDraftAttachmentInput] = [],
        now: Date = Date()
    ) throws -> SharedComposeDraftStagingItem {
        try stagingStore.stage(
            accountID: accountID,
            sourceApplication: sourceApplication,
            target: target,
            payload: payload,
            attachments: attachments,
            now: now
        )
    }

    func sharedAttachmentFileURL(
        for attachment: SharedComposeDraftAttachmentReference
    ) -> URL {
        stagingStore.attachmentFileURL(for: attachment)
    }

    @discardableResult
    func removePendingSharedStagingItem(id: String) -> Bool {
        stagingStore.removeItem(id: id)
    }

    /// Launch-time housekeeping for the share staging area; see `SharedComposeDraftStagingStore.sweep`.
    @discardableResult
    func sweepSharedStaging(now: Date = Date()) -> Int {
        let claimed = withLock {
            loadDraftsLocked().reduce(into: Set<String>()) { ids, draft in
                ids.formUnion(draft.sharedImportItemIDs ?? [])
                if draft.id.hasPrefix(Self.sharedDraftIDPrefix) {
                    ids.insert(String(draft.id.dropFirst(Self.sharedDraftIDPrefix.count)))
                }
            }
        }
        return stagingStore.sweep(claimedIDs: claimed, now: now)
    }

    /// Explicit discard that also works when the shared index is unreadable.
    @discardableResult
    func discardSharedStagingItems(ids: Set<String>) -> Bool {
        stagingStore.discardItems(ids: ids)
    }

    @discardableResult
    func acknowledgeImportedSharedAttachment(
        stagingItemID: String,
        attachmentID: String
    ) -> Bool {
        stagingStore.acknowledgeImportedAttachment(
            itemID: stagingItemID,
            attachmentID: attachmentID
        )
    }

    private func loadDraftsLocked() -> [ComposeDraft] {
        if let cachedDrafts {
            return cachedDrafts
        }

        guard let data = userDefaults.data(forKey: Keys.drafts) else { return [] }
        do {
            let drafts = try decoder.decode([ComposeDraft].self, from: data)
            cachedDrafts = drafts
            return drafts
        } catch {
            if userDefaults.data(forKey: Keys.corruptBackup) == nil {
                userDefaults.set(data, forKey: Keys.corruptBackup)
            }
            if let recovered = try? decoder
                .decode([LossyDecodable<ComposeDraft>].self, from: data)
                .compactMap(\.value),
               !recovered.isEmpty {
                AppLogger.error("Recovered valid entries from partially corrupt compose drafts")
                cachedDrafts = recovered
                return recovered
            }
            AppLogger.error("Failed to decode compose drafts: \(error)")
            cachedDrafts = []
            return []
        }
    }

    private func saveDraftsLocked(_ drafts: [ComposeDraft]) -> Bool {
        do {
            let data = try encoder.encode(drafts)
            userDefaults.set(data, forKey: Keys.drafts)
            guard userDefaults.data(forKey: Keys.drafts) == data else {
                AppLogger.error("Failed to verify compose draft persistence")
                return false
            }
            cachedDrafts = drafts
            return true
        } catch {
            AppLogger.error("Failed to encode compose drafts: \(error)")
            return false
        }
    }

    private func replacing(
        _ existing: ComposeDraft,
        with draft: ComposeDraft,
        savedID: String? = nil
    ) -> ComposeDraft {
        var replacement = ComposeDraft(
            id: savedID ?? existing.id,
            accountID: draft.accountID,
            category: existing.category == .manual ? .manual : draft.category,
            target: draft.target,
            payload: draft.payload,
            createdAt: existing.createdAt,
            updatedAt: draft.updatedAt,
            publishAttempt: draft.publishAttempt
        )
        replacement.sharedImportItemIDs = draft.sharedImportItemIDs
        return replacement
    }

    private func migrateLegacyDraftsIfNeeded() {
        guard let legacyUserDefaults,
              legacyUserDefaults !== userDefaults,
              userDefaults.data(forKey: Keys.drafts) == nil,
              let legacyData = legacyUserDefaults.data(forKey: Keys.drafts) else {
            return
        }

        guard (try? decoder.decode([ComposeDraft].self, from: legacyData)) != nil else {
            AppLogger.error("Skipped invalid legacy compose draft migration")
            return
        }

        userDefaults.set(legacyData, forKey: Keys.drafts)
        if userDefaults.data(forKey: Keys.drafts) == legacyData {
            legacyUserDefaults.removeObject(forKey: Keys.drafts)
        }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
