//
//  ComposeDraftStore.swift
//  moro
//
//  Compose payload models plus shared staging used by share import and re-draft flows.
//

import Foundation

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

enum ComposeDraftCategory: String, Codable, Equatable {
    case auto
    case manual
}

struct ComposeDraftAttachment: Codable, Equatable, Identifiable {
    let id: String
    let url: URL
    let previewURL: URL?
    let type: String
    let description: String?
    let focus: String?

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
    }

    var mediaAttachment: MediaAttachment {
        MediaAttachment(
            id: id,
            url: url,
            previewURL: previewURL,
            type: type,
            description: description,
            focus: focus,
            uploadState: .uploaded
        )
    }
}

struct ComposeDraftTarget: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
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

struct ComposeDraftPayload: Codable, Equatable {
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

extension ComposeDraftPayload {
    private enum CodingKeys: String, CodingKey {
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

struct ComposeDraft: Identifiable, Codable, Equatable {
    let id: String
    let accountID: String?
    var category: ComposeDraftCategory
    let target: ComposeDraftTarget
    var payload: ComposeDraftPayload
    let createdAt: Date
    var updatedAt: Date

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

struct SharedComposeDraftAttachmentInput {
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

struct SharedComposeDraftAttachmentReference: Codable, Equatable, Identifiable {
    let id: String
    let fileName: String
    let mimeType: String
    let relativePath: String
}

struct SharedComposeDraftStagingItem: Codable, Equatable, Identifiable {
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
            id: "shared-\(id)",
            accountID: accountID,
            category: .manual,
            target: target,
            payload: payload,
            createdAt: createdAt,
            updatedAt: now
        )
    }
}

final class SharedComposeDraftStagingStore {
    static let shared = SharedComposeDraftStagingStore(
        userDefaults: MoroSharedContainer.sharedUserDefaults(),
        baseDirectoryURL: MoroSharedContainer.composeDraftStagingDirectoryURL()
    )

    private enum Keys {
        static let items = "shared_compose_draft_staging_items_v1"
        static let corruptBackup = "shared_compose_draft_staging_items_v1_corrupt_backup"
    }

    private enum PersistenceError: Error {
        case writeVerificationFailed
    }

    private let userDefaults: UserDefaults
    private let baseDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

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
        withLock {
            loadItemsLocked().sorted { $0.createdAt < $1.createdAt }
        }
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
        try withLock {
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
                var items = loadItemsLocked()
                items.append(item)
                try saveItemsLocked(items)
                return item
            } catch {
                try? fileManager.removeItem(at: itemDirectoryURL)
                throw error
            }
        }
    }

    func attachmentFileURL(
        for attachment: SharedComposeDraftAttachmentReference
    ) -> URL {
        baseDirectoryURL.appendingPathComponent(attachment.relativePath, isDirectory: false)
    }

    func nextPendingItem() -> SharedComposeDraftStagingItem? {
        withLock {
            loadItemsLocked().min { $0.createdAt < $1.createdAt }
        }
    }

    @discardableResult
    func removeItem(id: String) -> Bool {
        withLock {
            var items = loadItemsLocked()
            let beforeCount = items.count
            items.removeAll { $0.id == id }
            guard items.count != beforeCount else { return false }

            do {
                try saveItemsLocked(items)
            } catch {
                AppLogger.error("Failed to persist shared draft removal: \(error)")
                return false
            }

            try? fileManager.removeItem(
                at: baseDirectoryURL.appendingPathComponent(id, isDirectory: true)
            )
            return true
        }
    }

    /// Commits progress after each successful upload. Only unconsumed files remain in
    /// staging, so a cancellation or relaunch cannot upload completed attachments twice.
    @discardableResult
    func acknowledgeImportedAttachment(itemID: String, attachmentID: String) -> Bool {
        withLock {
            var items = loadItemsLocked()
            guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
                  let importedAttachment = items[itemIndex].attachments.first(where: { $0.id == attachmentID }) else {
                return false
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

            do {
                try saveItemsLocked(items)
            } catch {
                AppLogger.error("Failed to persist shared attachment progress: \(error)")
                return false
            }

            if remainingAttachments.isEmpty {
                try? fileManager.removeItem(
                    at: baseDirectoryURL.appendingPathComponent(itemID, isDirectory: true)
                )
            } else {
                try? fileManager.removeItem(at: attachmentFileURL(for: importedAttachment))
            }
            return true
        }
    }

    func clear() {
        withLock {
            let items = loadItemsLocked()
            items.forEach { item in
                try? fileManager.removeItem(
                    at: baseDirectoryURL.appendingPathComponent(item.id, isDirectory: true)
                )
            }
            userDefaults.removeObject(forKey: Keys.items)
        }
    }

    private func loadItemsLocked() -> [SharedComposeDraftStagingItem] {
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

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

final class ComposeDraftStore {
    static let shared = ComposeDraftStore.makeSharedStore()

    private enum Keys {
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
            } else if draft.category == .auto,
                      let index = drafts.firstIndex(where: {
                          $0.category == .auto
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

    @discardableResult
    func removeDraft(id: String) -> Bool {
        withLock {
            var drafts = loadDraftsLocked()
            let beforeCount = drafts.count
            drafts.removeAll { $0.id == id }
            guard drafts.count != beforeCount else { return false }
            return saveDraftsLocked(drafts)
        }
    }

    func pendingSharedStagingItems() -> [SharedComposeDraftStagingItem] {
        stagingStore.pendingItems()
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

    func removePendingSharedStagingItem(id: String) {
        stagingStore.removeItem(id: id)
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
        ComposeDraft(
            id: savedID ?? existing.id,
            accountID: draft.accountID,
            category: existing.category == .manual ? .manual : draft.category,
            target: draft.target,
            payload: draft.payload,
            createdAt: existing.createdAt,
            updatedAt: draft.updatedAt
        )
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
