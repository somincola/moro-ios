//
//  ComposeViewModel.swift
//  moro
//
//  Manages compose view state for posting new statuses, replies, quotes, and edits.
//

import Foundation
import Combine
import SwiftUI

enum ComposeMediaSelectionPolicy {
    static let maximumAttachmentCount = 4
    static let maximumConcurrentImports = 2

    static func remainingSlots(existingCount: Int) -> Int {
        max(0, maximumAttachmentCount - max(0, existingCount))
    }

    static func acceptedSelectionCount(requestedCount: Int, existingCount: Int) -> Int {
        min(max(0, requestedCount), remainingSlots(existingCount: existingCount))
    }
}

@MainActor
final class ComposeViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    // MARK: - Compose Context
    
    enum ComposeContext: Hashable {
        case newPost
        case reply(to: Status?)
        case quote(original: Status?)
        case edit(status: Status)
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .newPost:
                hasher.combine("newPost")
            case .reply(let status):
                hasher.combine("reply")
                hasher.combine(status?.id)
            case .quote(let status):
                hasher.combine("quote")
                hasher.combine(status?.id)
            case .edit(let status):
                hasher.combine("edit")
                hasher.combine(status.id)
            }
        }
        
        static func == (lhs: ComposeContext, rhs: ComposeContext) -> Bool {
            switch (lhs, rhs) {
            case (.newPost, .newPost):
                return true
            case (.reply(let ls), .reply(let rs)):
                return ls?.id == rs?.id
            case (.quote(let ls), .quote(let rs)):
                return ls?.id == rs?.id
            case (.edit(let ls), .edit(let rs)):
                return ls.id == rs.id
            default:
                return false
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published var content: String = ""
    @Published var contentWarning: String = ""
    @Published var isContentWarningActive: Bool = false
    @Published var visibility: MastodonVisibility = .public
    @Published var mediaAttachments: [MediaAttachment] = []
    @Published var isPublishing: Bool = false
    @Published private(set) var hasPublished = false
    @Published var publishError: Error?
    @Published var isSchedulingEnabled: Bool = false
    @Published var scheduledAt: Date = ComposeViewModel.defaultScheduledDate()
    @Published var selectedLanguageCode: String = ""
    @Published private(set) var editSourceState: EditSourceState = .notRequired

    enum EditSourceState {
        case notRequired, pending, loading, ready, failed
    }

    var isEditingSourceReady: Bool {
        editSourceState == .notRequired || editSourceState == .ready
    }
    
    // Character counting
    @Published var characterCount: Int = 0
    @Published var maxCharacters: Int = 500
    
    // Media upload state tracking
    @Published var mediaUploadStates: [String: MediaAttachment.UploadState] = [:] // attachmentID -> upload state

    var remainingMediaAttachmentSlots: Int {
        ComposeMediaSelectionPolicy.remainingSlots(existingCount: mediaAttachments.count)
    }

    var canAddMedia: Bool {
        remainingMediaAttachmentSlots > 0
    }
    
    // Poll
    @Published var isPollActive: Bool = false
    @Published var pollOptions: [String] = ["", ""]
    @Published var pollMultiple: Bool = false
    @Published var pollExpiresIn: Int = 86400 // 24 hours in seconds
    
    // Emoji picker
    @Published var showEmojiPicker: Bool = false
    
    // Original status for reply/quote display
    @Published var originalStatus: Status?
    
    // Quote policy (who can quote this post)
    enum QuotePolicy: String, Codable {
        case anyone = "public"      // 任何人
        case followers = "followers" // 粉丝
        case none = "none"          // 仅自己（不允许引用）

        // Keep the persisted draft value `none` compatible with older app versions.
        var apiValue: MastodonQuoteApprovalPolicy {
            switch self {
            case .anyone: return .anyone
            case .followers: return .followers
            case .none: return .nobody
            }
        }
    }

    enum PublishBlocker: Equatable {
        case editSourceUnavailable
        case emptyContent
        case publishing
        case mediaUploading
        case mediaUploadFailed
        case sharedImportIncomplete
        case characterLimitExceeded
        case pollNeedsMoreOptions
        case pollCannotIncludeMedia
        case scheduledDateTooSoon
    }

    enum MediaImportFailure: Equatable, Sendable {
        case imageProcessing
        case fileAccess
        case fileRead
        case upload
        case retryUnavailable
    }

    enum MediaImportOutcome: Equatable, Sendable {
        case uploaded
        case cancelled
        case failed(MediaImportFailure)
    }

    enum SharedImportOutcome: Equatable {
        case complete
        case partial
        case failed
        case cancelled
        case blocked
        /// The share was cancelled in the extension (its staging item is gone) after the
        /// app had already read it. Nothing of it should remain in the editor.
        case withdrawn
    }

    private enum MediaUploadResult {
        case uploaded
        case removed
        case failed
    }

    @Published var quotePolicy: QuotePolicy = .anyone
    
    let context: ComposeContext
    let apiClient: MastodonAPI
    private let feedCoordinator: FeedCoordinator
    private let instanceMetadataStore: InstanceMetadataStore
    private var cancellables = Set<AnyCancellable>()
    private let currentUserID: String?
    private static let minimumScheduleLeadTime: TimeInterval = 5 * 60
    private var publishReplyToID: String?
    private var publishQuotingID: String?
    private(set) var activeDraftID: String?
    private var activeSharedImportItemIDs: Set<String> = []
    @Published private(set) var isImportingSharedMedia = false
    private var sharedImportDraftStore: ComposeDraftStore?
    private var sharedImportGeneration = UUID()
    private(set) var sharedImportFailureMessage: String?
    var sharedImportAccountID: String? { currentUserID }
    func cancelSharedImports() { sharedImportGeneration = UUID() }
    func configureSharedImportRecovery(using draftStore: ComposeDraftStore) {
        sharedImportDraftStore = draftStore
        refreshPendingSharedMedia()
    }

    /// Last known staging state for this draft's shares. Rendering reads this snapshot;
    /// it never takes the cross-process index lock. Starts conservative (pending) until
    /// the recovery store is bound and read.
    @Published private var stagedSharedMediaPending = true

    var hasPendingSharedMedia: Bool {
        if isImportingSharedMedia { return true }
        guard !activeSharedImportItemIDs.isEmpty else { return false }
        return stagedSharedMediaPending
    }

    /// Reads the shared index once and updates the snapshot. Called after imports, retry,
    /// ignore, draft changes and on returning to the foreground, and authoritatively right
    /// before publishing. A transient read failure keeps the draft "incomplete".
    @discardableResult
    func refreshPendingSharedMedia() -> Bool {
        let pending: Bool
        var unreadable = false
        if activeSharedImportItemIDs.isEmpty {
            pending = false
        } else if let sharedImportDraftStore {
            do {
                pending = try sharedImportDraftStore.pendingSharedStagingItemsForPublishing().contains {
                    activeSharedImportItemIDs.contains($0.id) && !$0.attachments.isEmpty
                }
            } catch SharedComposeDraftStagingStore.PersistenceError.indexCorrupt {
                pending = true
                unreadable = true
            } catch { pending = true }
        } else {
            pending = true
        }
        if stagedSharedMediaPending != pending { stagedSharedMediaPending = pending }
        if sharedStagingUnreadable != unreadable { sharedStagingUnreadable = unreadable }
        return isImportingSharedMedia || pending
    }

    /// Only a readable index that no longer lists the item counts as withdrawn (cancelled in
    /// the extension, or tombstoned). A busy or unreadable index is not evidence of that.
    private func isWithdrawn(_ itemID: String, draftStore: ComposeDraftStore) -> Bool {
        guard let items = try? draftStore.pendingSharedStagingItemsForPublishing() else { return false }
        return !items.contains { $0.id == itemID }
    }

    /// Drops reserved tiles of a batch that never began preparing. Tiles that failed keep
    /// their failed state (and retry button); uploaded tiles are untouched.
    private func releaseUnstartedSharedReservations(itemID: String) {
        let unstarted = mediaAttachments.filter { attachment in
            guard attachment.sharedImportItemID == itemID, attachment.url.scheme == "temp",
                  attachment.sourceUploadData == nil, attachment.previewImage == nil else { return false }
            if case .uploading = attachment.uploadState { return true }
            return false
        }
        for attachment in unstarted { _ = removeMedia(id: attachment.id) }
    }

    private func removeSharedPlaceholders(itemID: String) {
        let placeholders = mediaAttachments.filter { $0.sharedImportItemID == itemID && !$0.uploadState.isUploaded }
        for attachment in placeholders { _ = removeMedia(id: attachment.id) }
    }

    /// The draft's share queue cannot be decoded. Publishing stays blocked, and the editor
    /// offers the explicit discard, which repairs the index.
    @Published private(set) var sharedStagingUnreadable = false

    /// Drops this draft's remaining shared files after the person chose to discard them.
    /// Works even when the shared index is unreadable. Uploaded attachments are kept.
    @discardableResult
    func discardRemainingSharedImports(using draftStore: ComposeDraftStore) -> Bool {
        guard !activeSharedImportItemIDs.isEmpty else { return true }
        guard draftStore.discardSharedStagingItems(ids: activeSharedImportItemIDs) else { return false }
        for attachment in mediaAttachments where !attachment.uploadState.isUploaded
            && attachment.sharedImportItemID.map({ activeSharedImportItemIDs.contains($0) }) == true {
            _ = removeMedia(id: attachment.id)
        }
        refreshPendingSharedMedia()
        return true
    }
    private var activeDraftCreatedAt: Date?
    private var activeDraftCategory: ComposeDraftCategory?
    private var editSource: StatusSource?
    private var publishAttempt: ComposePublishAttempt?
    private var completedPublishResult: StatusPublishResult?

    init(
        context: ComposeContext,
        apiClient: MastodonAPI,
        currentUserID: String? = nil,
        feedCoordinator: FeedCoordinator? = nil,
        instanceMetadataStore: InstanceMetadataStore? = nil,
        accountCache: AccountCache? = nil,
        initialDraft: ComposeDraft? = nil
    ) {
        self.context = context
        self.apiClient = apiClient
        self.feedCoordinator = feedCoordinator ?? .shared
        let resolvedInstanceMetadataStore = instanceMetadataStore ?? .shared
        self.instanceMetadataStore = resolvedInstanceMetadataStore
        self.currentUserID = currentUserID

        if let cachedLimit = resolvedInstanceMetadataStore
            .cachedInstance(for: apiClient)?
            .configuration?.statuses?.maxCharacters,
           cachedLimit > 0 {
            maxCharacters = cachedLimit
        }
        
        // Initialize based on context
        switch context {
        case .newPost:
            // Use default visibility from AppSettings
            visibility = defaultVisibilityFromSettings()
            quotePolicy = .anyone // Default: anyone can quote
            publishReplyToID = nil
            publishQuotingID = nil
        case .reply(let status):
            if let status {
                initializeForReply(to: status, accountCache: accountCache ?? CacheManager.shared.accountCache)
            } else {
                visibility = defaultVisibilityFromSettings()
            }
            quotePolicy = .anyone // Default for now
            publishReplyToID = status?.displayStatus.id
            publishQuotingID = nil
        case .quote(let original):
            originalStatus = original
            content = ""
            // Use default visibility from AppSettings for quotes
            visibility = defaultVisibilityFromSettings()
            quotePolicy = .anyone // Default for quotes
            publishReplyToID = nil
            publishQuotingID = original?.displayStatus.id
        case .edit(let status):
            let displayStatus = status.displayStatus
            editSourceState = .pending
            if let spoilerText = displayStatus.spoilerText, !spoilerText.isEmpty {
                isContentWarningActive = true
                contentWarning = spoilerText
            }
            visibility = MastodonVisibility(rawValue: displayStatus.visibility ?? "public") ?? .public
            mediaAttachments = displayStatus.mediaAttachments.map {
                MediaAttachment(
                    id: $0.id,
                    url: $0.url,
                    previewURL: $0.previewURL,
                    type: $0.type,
                    description: $0.description,
                    focus: nil,
                    originalDescription: $0.description,
                    originalFocus: nil,
                    uploadState: .uploaded
                )
            }
            mediaUploadStates = Dictionary(
                uniqueKeysWithValues: mediaAttachments.map { ($0.id, $0.uploadState) }
            )
            selectedLanguageCode = displayStatus.language ?? ""
            quotePolicy = .anyone // Default for edits (future: parse from status)
            publishReplyToID = nil
            publishQuotingID = nil
        }

        if let initialDraft {
            applyDraft(initialDraft)
        }
        
        // Count the way Mastodon does (URLs = 23 chars, remote-mention domains excluded)
        // so we don't block valid posts. The server checks the content warning and the
        // text together, so an active CW counts too — including one inherited by a reply.
        Publishers.CombineLatest3($content, $contentWarning, $isContentWarningActive)
            .map { content, contentWarning, isContentWarningActive in
                MastodonTextCounter.count(
                    text: content,
                    spoilerText: isContentWarningActive ? contentWarning : ""
                )
            }
            .assign(to: &$characterCount)
    }

    /// Load once per editor. A failed/cancelled request can be retried, while a late
    /// response must never replace text the user has already changed or restored.
    func loadEditingSourceIfNeeded() async {
        guard case .edit(let status) = context,
              editSource == nil,
              editSourceState != .loading else { return }

        let displayStatus = status.displayStatus
        let previousContent = content
        let previousWarning = contentWarning
        let previousWarningActive = isContentWarningActive
        let warningWasUnedited = previousWarning == (displayStatus.spoilerText ?? "")
            && previousWarningActive == !(displayStatus.spoilerText ?? "").isEmpty
        editSourceState = .loading

        do {
            let source = try await apiClient.fetchStatusSource(id: displayStatus.id)
            try Task.checkCancellation()
            guard source.id == displayStatus.id else {
                throw ComposeError.editSourceUnavailable
            }
            if activeDraftID == nil, previousContent.isEmpty, content == previousContent {
                content = source.text
            }
            if activeDraftID == nil, warningWasUnedited,
               contentWarning == previousWarning,
               isContentWarningActive == previousWarningActive {
                contentWarning = source.spoilerText
                isContentWarningActive = !source.spoilerText.isEmpty
            }
            editSource = source
            editSourceState = .ready
        } catch {
            editSourceState = Task.isCancelled || error is CancellationError ? .pending : .failed
        }
    }

    var effectiveQuoteApprovalPolicy: MastodonQuoteApprovalPolicy {
        switch visibility {
        case .followers, .direct, ._other: return .nobody
        case .public, .unlisted: return quotePolicy.apiValue
        }
    }

    /// Reads the authenticated server's shared v2 metadata; keeps the 500 fallback when
    /// the server is unavailable or doesn't advertise a positive limit.
    func loadInstanceLimits() async {
        guard let instance = try? await instanceMetadataStore.load(apiClient: apiClient),
            let limit = instance.configuration?.statuses?.maxCharacters,
            limit > 0
        else { return }
        if maxCharacters != limit {
            maxCharacters = limit
        }
    }

    static func defaultScheduledDate(from referenceDate: Date = Date()) -> Date {
        let target = referenceDate.addingTimeInterval(30 * 60)
        let roundedTimestamp = ceil(target.timeIntervalSince1970 / 300) * 300
        return Date(timeIntervalSince1970: roundedTimestamp)
    }

    /// Media sensitivity follows the content warning: visual media under an active,
    /// non-empty CW is marked sensitive so other clients blur it behind the warning.
    /// No visual media → nil (omit the field).
    nonisolated static func resolveMediaSensitivity(
        hasVisualMedia: Bool,
        contentWarningActive: Bool,
        contentWarning: String
    ) -> Bool? {
        guard hasVisualMedia else { return nil }
        return contentWarningActive
            && !contentWarning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareSchedulingDateIfNeeded(referenceDate: Date = Date()) {
        guard isScheduledPublishingActive else { return }
        let minimumDate = referenceDate.addingTimeInterval(Self.minimumScheduleLeadTime)
        if scheduledAt < minimumDate {
            scheduledAt = Self.defaultScheduledDate(from: referenceDate)
        }
    }

    var minimumScheduledDate: Date {
        Date().addingTimeInterval(Self.minimumScheduleLeadTime)
    }

    var scheduledPublishDate: Date? {
        guard isScheduledPublishingActive else { return nil }
        return scheduledAt
    }

    var isScheduledPublishingActive: Bool {
        ComposeFeatureAvailability.scheduledPublishing && isSchedulingEnabled
    }

    var effectivePostLanguageCode: String? {
        let selectedCode = selectedLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedCode.isEmpty {
            return selectedCode
        }

        let defaultCode = AppSettings.shared.effectiveDefaultPostLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultCode.isEmpty ? nil : defaultCode
    }

    private var publishLanguageCode: String? {
        switch context {
        case .edit:
            let selectedCode = selectedLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return selectedCode.isEmpty ? nil : selectedCode
        case .newPost, .reply, .quote:
            return effectivePostLanguageCode
        }
    }
    
    // MARK: - Initialization Helpers
    
    /// Get default visibility from AppSettings.
    @MainActor
    private func defaultVisibilityFromSettings() -> MastodonVisibility {
        let settingsVisibility = AppSettings.shared.defaultPostVisibility
        switch settingsVisibility {
        case .public:
            return .public
        case .unlisted:
            return .unlisted
        case .followersOnly:
            return .followers
        case .mentionedOnly:
            return .direct
        }
    }
    
    private func initializeForReply(to status: Status, accountCache: AccountCache) {
        // Get the actual status to reply to (handle reblog case)
        // If it's a reblog, we want to reply to the original post, not the reblog wrapper
        let statusToReplyTo: Status = status.displayStatus
        
        originalStatus = statusToReplyTo
        content = ComposeReplyRecipients.text(
            for: statusToReplyTo, currentUserID: currentUserID, accountCache: accountCache
        )

        // Inherit CW
        if let spoilerText = status.spoilerText, !spoilerText.isEmpty {
            isContentWarningActive = true
            contentWarning = spoilerText
        }
        
        // Inherit visibility (reply can't be more permissive than original)
        if let originalVisibility = status.visibility {
            let originalVis = MastodonVisibility(rawValue: originalVisibility) ?? .public
            // Ensure reply visibility is not more permissive
            visibility = originalVis
        }
    }
    
    func applyRestoredDraft(_ draft: ComposeDraft) {
        cancelSharedImports()
        applyDraft(draft)
    }

    private func applyDraft(_ draft: ComposeDraft) {
        guard !isPublishing, !hasPublished else { return }
        publishAttempt = draft.publishAttempt
        activeDraftID = draft.id
        activeDraftCreatedAt = draft.createdAt
        activeDraftCategory = draft.category
        activeSharedImportItemIDs = Set(draft.sharedImportItemIDs ?? [])
        if draft.id.hasPrefix(ComposeDraftStore.sharedDraftIDPrefix) {
            activeSharedImportItemIDs.insert(String(draft.id.dropFirst(ComposeDraftStore.sharedDraftIDPrefix.count)))
        }
        refreshPendingSharedMedia()
        publishReplyToID = draft.target.inReplyToID
        publishQuotingID = draft.target.quotingID
        originalStatus = draft.target.referenceStatus

        let payload = draft.payload
        content = payload.content
        contentWarning = payload.contentWarning
        isContentWarningActive = payload.isContentWarningActive
        visibility = payload.visibility
        mediaAttachments = payload.mediaAttachments.map(\.mediaAttachment)
        mediaUploadStates = Dictionary(
            uniqueKeysWithValues: mediaAttachments.map { ($0.id, $0.uploadState) }
        )
        isPollActive = payload.isPollActive
        pollOptions = payload.pollOptions.count >= 2 ? payload.pollOptions : ["", ""]
        pollMultiple = payload.pollMultiple
        pollExpiresIn = payload.pollExpiresIn
        isSchedulingEnabled = ComposeFeatureAvailability.scheduledPublishing && payload.isSchedulingEnabled
        scheduledAt = isSchedulingEnabled
            ? (payload.scheduledAt ?? Self.defaultScheduledDate())
            : Self.defaultScheduledDate()
        selectedLanguageCode = payload.selectedLanguageCode
        quotePolicy = QuotePolicy(rawValue: payload.quotePolicyRawValue) ?? .anyone
    }
    
    // MARK: - Media Management
    
    func addMedia(_ attachment: Status.Attachment, uploadState: MediaAttachment.UploadState = .uploaded) {
        let mediaAttachment = MediaAttachment(
            id: attachment.id,
            url: attachment.url,
            previewURL: attachment.previewURL,
            type: attachment.type,
            description: attachment.description,
            focus: nil,
            originalDescription: attachment.description,
            originalFocus: nil,
            uploadState: uploadState
        )
        mediaAttachments.append(mediaAttachment)
        mediaUploadStates[attachment.id] = uploadState
    }
    
    func updateMediaUploadState(id: String, state: MediaAttachment.UploadState) {
        mediaUploadStates[id] = state
        if let index = mediaAttachments.firstIndex(where: { $0.id == id }) {
            mediaAttachments[index].uploadState = state
        }
    }

    /// Adds lightweight placeholders immediately after the system picker is confirmed.
    /// Expensive Photos transfers and image preparation then happen behind visible progress UI.
    func reservePhotoImports(count: Int) -> [String] {
        let acceptedCount = ComposeMediaSelectionPolicy.acceptedSelectionCount(
            requestedCount: count,
            existingCount: mediaAttachments.count
        )

        return (0..<acceptedCount).map { _ in
            let reservationID = UUID().uuidString
            let attachment = MediaAttachment(
                id: reservationID,
                url: URL(string: "temp://\(reservationID)")!,
                previewURL: nil,
                type: "image",
                description: nil,
                focus: nil,
                uploadState: .uploading(progress: 0.0)
            )
            mediaAttachments.append(attachment)
            mediaUploadStates[reservationID] = .uploading(progress: 0.0)
            return reservationID
        }
    }

    func cancelPhotoImportReservation(id: String) {
        _ = removeMedia(id: id)
    }
    
    func mediaAttachment(id: String) -> MediaAttachment? {
        mediaAttachments.first { $0.id == id }
    }

    func moveMedia(from source: IndexSet, to destination: Int) {
        guard !isPublishing, destination >= 0, destination <= mediaAttachments.count,
            source.allSatisfy({ mediaAttachments.indices.contains($0) }) else { return }
        mediaAttachments.move(fromOffsets: source, toOffset: destination)
    }

    @discardableResult
    func removeMedia(id: String) -> Bool {
        guard let index = mediaAttachments.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let removedAttachment = mediaAttachments.remove(at: index)
        mediaUploadStates.removeValue(forKey: removedAttachment.id)
        return true
    }

    @discardableResult
    func updateMediaAltText(id: String, altText: String) -> Bool {
        guard let index = mediaAttachments.firstIndex(where: { $0.id == id }) else {
            return false
        }
        mediaAttachments[index].description = altText.isEmpty ? nil : altText
        return true
    }

    func importPhotoData(
        _ data: Data,
        reservationID: String? = nil
    ) async -> MediaImportOutcome {
        if let reservationID,
           !mediaAttachments.contains(where: { $0.id == reservationID }) {
            return .cancelled
        }

        do {
            let prepared = try await ComposeMediaProcessor.shared.preparePhotoData(data)
            return await importPreparedMedia(prepared, reservationID: reservationID)
        } catch is CancellationError {
            if let reservationID {
                cancelPhotoImportReservation(id: reservationID)
            }
            return .cancelled
        } catch {
            if let reservationID {
                cancelPhotoImportReservation(id: reservationID)
            }
            return .failed(.imageProcessing)
        }
    }

    func importCameraImage(_ image: UIImage) async -> MediaImportOutcome {
        do {
            let prepared = try await ComposeMediaProcessor.shared.prepareCameraImage(image)
            return await importPreparedMedia(prepared)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(.imageProcessing)
        }
    }

    func importFile(at url: URL) async -> MediaImportOutcome {
        guard url.startAccessingSecurityScopedResource() else {
            return .failed(.fileAccess)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let resolved = ComposeMediaType.resolve(fileExtension: url.pathExtension)
        do {
            let prepared = try await ComposeMediaProcessor.shared.prepareFile(
                at: url,
                mimeType: resolved.mimeType,
                mediaType: resolved.mediaKind
            )
            return await importPreparedMedia(prepared)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(.fileRead)
        }
    }

    func retryMediaUpload(attachmentID: String) async -> MediaImportOutcome {
        guard let attachment = mediaAttachments.first(where: { $0.id == attachmentID }),
              let sourceData = attachment.sourceUploadData,
              let sourceMimeType = attachment.sourceMimeType else {
            return .failed(.retryUnavailable)
        }

        updateMediaUploadState(id: attachment.id, state: .uploading(progress: 0.0))
        switch await uploadTemporaryAttachment(
            tempID: attachment.id,
            data: sourceData,
            mimeType: sourceMimeType
        ) {
        case .uploaded:
            return .uploaded
        case .removed:
            return .cancelled
        case .failed:
            return .failed(.upload)
        }
    }

    func importSharedAttachments(
        from sharedImport: SharedComposeAttachmentImportPayload,
        draftStore: ComposeDraftStore
    ) async -> SharedImportOutcome {
        configureSharedImportRecovery(using: draftStore)
        guard !Task.isCancelled else { return .cancelled }
        guard !isImportingSharedMedia else { return .cancelled }
        guard let failure = sharedImportBlocker(for: sharedImport) else {
            return await performSharedImport(sharedImport, draftStore: draftStore)
        }
        sharedImportFailureMessage = failure
        return .blocked
    }

    func sharedImportBlocker(for sharedImport: SharedComposeAttachmentImportPayload) -> String? {
        if isPublishing || hasPublished || !isEditingSourceReady { return MoroL10n.ShareImport.busy }
        if case .edit = context { return MoroL10n.ShareImport.editingPost }
        if isPollActive, !sharedImport.attachments.isEmpty { return MoroL10n.Compose.validationPollCannotIncludeMedia }
        let newCount = sharedImport.attachments.filter { reference in
            !mediaAttachments.contains { $0.sharedImportItemID == sharedImport.stagingItemID
                && $0.sharedImportAttachmentID == reference.id }
        }.count
        if newCount > remainingMediaAttachmentSlots { return MoroL10n.ShareImport.mediaLimit }
        return nil
    }

    private func performSharedImport(
        _ sharedImport: SharedComposeAttachmentImportPayload, draftStore: ComposeDraftStore
    ) async -> SharedImportOutcome {
        isImportingSharedMedia = true
        let generation = sharedImportGeneration
        defer {
            isImportingSharedMedia = false
            refreshPendingSharedMedia()
        }
        sharedImportFailureMessage = nil
        // A share this editor already took in may legitimately be gone from staging once fully
        // consumed (a repeated URL/foreground delivery). Only a new one can be "withdrawn".
        if !activeSharedImportItemIDs.contains(sharedImport.stagingItemID),
           isWithdrawn(sharedImport.stagingItemID, draftStore: draftStore) {
            SharedComposeHandoff.shared.acknowledge(sharedImport.stagingItemID)
            return .withdrawn
        }
        let previousContent = content
        let previousIDs = activeSharedImportItemIDs
        if activeSharedImportItemIDs.insert(sharedImport.stagingItemID).inserted {
            let incomingText = sharedImport.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !incomingText.isEmpty {
                content = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? incomingText : content + "\n\n" + incomingText
            }
        }
        guard draftStore.save(makeDraft(category: .auto)) else {
            content = previousContent
            activeSharedImportItemIDs = previousIDs
            sharedImportFailureMessage = MoroL10n.ComposeDrafts.saveFailed
            return .failed
        }
        SharedComposeHandoff.shared.acknowledge(sharedImport.stagingItemID)
        if sharedImport.attachments.isEmpty {
            draftStore.removePendingSharedStagingItem(id: sharedImport.stagingItemID)
            return .complete
        }
        var successfulUploadCount = 0
        var encounteredFailure = false
        var progressPersistenceFailed = false

        // Reserve every tile of the batch up front, like the photo picker does, so the grid
        // settles on its final layout once instead of reflowing after each upload.
        for attachment in sharedImport.attachments where !mediaAttachments.contains(where: {
            $0.sharedImportItemID == sharedImport.stagingItemID && $0.sharedImportAttachmentID == attachment.id
        }) {
            guard let id = reservePhotoImports(count: 1).first,
                  let index = mediaAttachments.firstIndex(where: { $0.id == id }) else { break }
            mediaAttachments[index].sharedImportItemID = sharedImport.stagingItemID
            mediaAttachments[index].sharedImportAttachmentID = attachment.id
        }
        // A tile that never started (cancelled, discarded or withdrawn mid-batch) must not
        // stay behind as an endless spinner; its file remains staged for a later retry.
        defer { releaseUnstartedSharedReservations(itemID: sharedImport.stagingItemID) }

        for attachment in sharedImport.attachments {
            if Task.isCancelled {
                return successfulUploadCount > 0 ? .partial : .cancelled
            }
            let alreadyUploaded = mediaAttachments.contains {
                $0.sharedImportItemID == sharedImport.stagingItemID && $0.sharedImportAttachmentID == attachment.id
                    && $0.uploadState.isUploaded
            }
            if !alreadyUploaded, isWithdrawn(sharedImport.stagingItemID, draftStore: draftStore) {
                removeSharedPlaceholders(itemID: sharedImport.stagingItemID)
                activeSharedImportItemIDs.remove(sharedImport.stagingItemID)
                sharedImportFailureMessage = nil
                _ = draftStore.save(makeDraft(category: .auto))
                return .withdrawn
            }

            let existing = mediaAttachments.first {
                $0.sharedImportItemID == sharedImport.stagingItemID && $0.sharedImportAttachmentID == attachment.id
            }
            let outcome: MediaImportOutcome
            if existing?.uploadState.isUploaded == true {
                outcome = .uploaded
            } else if let existing, existing.sourceUploadData != nil {
                outcome = await retryMediaUpload(attachmentID: existing.id)
            } else {
                let reservationID: String
                if let existing { reservationID = existing.id }
                else if let id = reservePhotoImports(count: 1).first { reservationID = id }
                else { encounteredFailure = true; continue }
                if let index = mediaAttachments.firstIndex(where: { $0.id == reservationID }) {
                    mediaAttachments[index].sharedImportItemID = sharedImport.stagingItemID
                    mediaAttachments[index].sharedImportAttachmentID = attachment.id
                }
                let fileURL = draftStore.sharedAttachmentFileURL(for: attachment)
                do {
                    let prepared = try await ComposeMediaProcessor.shared.prepareFile(
                        at: fileURL, mimeType: attachment.mimeType,
                        mediaType: attachment.mimeType.lowercased().hasPrefix("video/") ? "video" : "image")
                    try Task.checkCancellation()
                    outcome = await importPreparedMedia(prepared, reservationID: reservationID)
                } catch is CancellationError {
                    return successfulUploadCount > 0 ? .partial : .cancelled
                } catch {
                    updateMediaUploadState(id: reservationID, state: .failed(error: error))
                    encounteredFailure = true
                    continue
                }
            }
            // Even a transport that ignores cancellation cannot recreate a discarded draft.
            guard generation == sharedImportGeneration else { return .cancelled }
            guard outcome == .uploaded else {
                encounteredFailure = true
                continue
            }

            successfulUploadCount += 1
            // Persist the uploaded server attachment before consuming its staged file.
            // This keeps completed work recoverable if the import task is cancelled
            // before the remaining attachments finish.
            let didSaveDraftProgress = draftStore.save(makeDraft(category: .auto))
            guard didSaveDraftProgress else {
                progressPersistenceFailed = true
                encounteredFailure = true
                continue
            }

            do {
                let needsAcknowledgement = try draftStore.pendingSharedStagingItemsForPublishing()
                    .first(where: { $0.id == sharedImport.stagingItemID })?
                    .attachments.contains(where: { $0.id == attachment.id }) == true
                let didAcknowledgeAttachment = !needsAcknowledgement || draftStore.acknowledgeImportedSharedAttachment(
                    stagingItemID: sharedImport.stagingItemID, attachmentID: attachment.id)
                progressPersistenceFailed = progressPersistenceFailed || !didAcknowledgeAttachment
            } catch {
                progressPersistenceFailed = true
            }
        }

        // Failed or unacknowledged files stay recoverable. The editor offers an explicit
        // retry; publishing/discarding the owning draft cleans up all remaining staging.
        if encounteredFailure || progressPersistenceFailed { sharedImportFailureMessage = MoroL10n.ShareImport.retryMessage }
        guard successfulUploadCount > 0 else { return .failed }
        if !encounteredFailure
            && !progressPersistenceFailed
            && successfulUploadCount == sharedImport.attachments.count {
            return .complete
        }
        return .partial
    }

    func importPreparedMedia(
        _ preparedMedia: ComposeMediaProcessor.PreparedMedia,
        reservationID: String? = nil
    ) async -> MediaImportOutcome {
        let tempID: String
        if let reservationID {
            guard populatePhotoImportReservation(
                id: reservationID,
                with: preparedMedia
            ) else {
                return .cancelled
            }
            tempID = reservationID
        } else {
            guard canAddMedia else { return .cancelled }
            tempID = appendTemporaryMediaAttachment(preparedMedia)
        }
        updateMediaUploadState(id: tempID, state: .uploading(progress: 0.05))
        let uploadResult = await uploadTemporaryAttachment(
            tempID: tempID,
            data: preparedMedia.uploadData,
            mimeType: preparedMedia.uploadMimeType
        )
        switch uploadResult {
        case .uploaded:
            return .uploaded
        case .removed:
            return .cancelled
        case .failed:
            return .failed(.upload)
        }
    }

    private func populatePhotoImportReservation(
        id: String,
        with preparedMedia: ComposeMediaProcessor.PreparedMedia
    ) -> Bool {
        guard let index = mediaAttachments.firstIndex(where: { $0.id == id }) else {
            mediaUploadStates.removeValue(forKey: id)
            return false
        }

        mediaAttachments[index].previewImage = preparedMedia.previewImage
        mediaAttachments[index].sourceUploadData = preparedMedia.uploadData
        mediaAttachments[index].sourceMimeType = preparedMedia.uploadMimeType
        return true
    }

    private func appendTemporaryMediaAttachment(
        _ preparedMedia: ComposeMediaProcessor.PreparedMedia
    ) -> String {
        let tempID = UUID().uuidString
        let tempAttachment = MediaAttachment(
            id: tempID,
            url: URL(string: "temp://\(tempID)")!,
            previewURL: nil,
            type: preparedMedia.mediaType,
            description: nil,
            focus: nil,
            uploadState: .uploading(progress: 0.0),
            previewImage: preparedMedia.previewImage,
            sourceUploadData: preparedMedia.uploadData,
            sourceMimeType: preparedMedia.uploadMimeType
        )

        mediaAttachments.append(tempAttachment)
        mediaUploadStates[tempID] = .uploading(progress: 0.0)
        return tempID
    }

    private func uploadTemporaryAttachment(
        tempID: String,
        data: Data,
        mimeType: String
    ) async -> MediaUploadResult {
        do {
            updateMediaUploadState(id: tempID, state: .uploading(progress: 0.1))
            let attachment = try await apiClient.uploadMedia(
                data: data,
                mimeType: mimeType,
                description: nil
            )

            guard let index = mediaAttachments.firstIndex(where: { $0.id == tempID }) else {
                // The user removed this attachment while its request was in flight.
                // Do not resurrect it or leave a ghost upload-state entry.
                mediaUploadStates.removeValue(forKey: tempID)
                return .removed
            }

            updateMediaUploadState(id: tempID, state: .uploading(progress: 0.9))
            let existingDescription = mediaAttachments[index].description
            let existingFocus = mediaAttachments[index].focus
            let sharedItemID = mediaAttachments[index].sharedImportItemID
            let sharedAttachmentID = mediaAttachments[index].sharedImportAttachmentID
            mediaAttachments[index] = MediaAttachment(
                id: attachment.id,
                url: attachment.url,
                previewURL: attachment.previewURL,
                type: attachment.type,
                description: existingDescription ?? attachment.description,
                focus: existingFocus,
                originalDescription: attachment.description,
                originalFocus: nil,
                uploadState: .uploaded,
                // Keep the downsampled local preview: the server copy may still be processing
                // or loading, and the tile must never flash blank after a successful upload.
                previewImage: mediaAttachments[index].previewImage,
                sourceUploadData: nil,
                sourceMimeType: nil
            )
            mediaAttachments[index].sharedImportItemID = sharedItemID
            mediaAttachments[index].sharedImportAttachmentID = sharedAttachmentID
            mediaUploadStates[attachment.id] = .uploaded
            mediaUploadStates.removeValue(forKey: tempID)
            return .uploaded
        } catch {
            guard mediaAttachments.contains(where: { $0.id == tempID }) else {
                mediaUploadStates.removeValue(forKey: tempID)
                return .removed
            }
            updateMediaUploadState(id: tempID, state: .failed(error: error))
            AppLogger.error("Failed to upload media: \(error)")
            return .failed
        }
    }
    
    // MARK: - Publishing
    
    func publish() async throws -> StatusPublishResult {
        // A completed editor can never create another post, even if dismissal is delayed.
        if let completedPublishResult { return completedPublishResult }
        guard isEditingSourceReady else {
            throw ComposeError.editSourceUnavailable
        }
        guard !isPublishing else {
            throw ComposeError.alreadyPublishing
        }

        guard !hasUploadingMedia else {
            throw ComposeError.mediaUploading
        }

        guard !hasFailedMedia else {
            throw ComposeError.uploadFailed
        }

        guard !refreshPendingSharedMedia() else {
            throw ComposeError.sharedImportIncomplete
        }

        guard characterCount <= maxCharacters else {
            throw ComposeError.characterLimitExceeded
        }

        if isPollActive && !mediaAttachments.isEmpty {
            throw ComposeError.pollCannotIncludeMedia
        }

        if let scheduledPublishDate, scheduledPublishDate < minimumScheduledDate {
            throw ComposeError.invalidScheduledDate
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPollOptions = self.normalizedPollOptions
        if isPollActive && normalizedPollOptions.count < 2 {
            throw ComposeError.invalidPoll
        }

        guard !trimmedContent.isEmpty || isPollActive || !mediaAttachments.isEmpty else {
            throw ComposeError.emptyContent
        }
        
        isPublishing = true
        publishError = nil
        
        defer {
            isPublishing = false
        }
        
        do {
            // Freeze the request before the first suspension point.
            let attachments = mediaAttachments
            // Collect media IDs for posting
            let mediaIDs = mediaAttachments.compactMap { attachment -> String? in
                guard case .uploaded = attachment.uploadState else { return nil }
                guard attachment.url.scheme != "temp", !attachment.id.isEmpty else { return nil }
                return attachment.id
            }

            let pollPayload: StatusPollPayload? = isPollActive
                ? StatusPollPayload(
                    options: normalizedPollOptions,
                    expiresIn: pollExpiresIn,
                    multiple: pollMultiple,
                    hideTotals: nil
                )
                : nil
            
            // Media inherits the content warning's sensitivity: a CW post with media must
            // mark the media sensitive so other clients blur it behind the warning.
            let hasVisualMedia = mediaAttachments.contains { $0.type == "image" || $0.type == "video" }
            let isSensitive = Self.resolveMediaSensitivity(
                hasVisualMedia: hasVisualMedia,
                contentWarningActive: isContentWarningActive,
                contentWarning: contentWarning
            )

            let publishDate = scheduledPublishDate
            let payload = StatusPublishPayload(
                status: content, visibility: visibility,
                mediaIDs: mediaIDs.isEmpty ? nil : mediaIDs,
                inReplyToID: publishReplyToID,
                spoilerText: isContentWarningActive && !contentWarning.isEmpty ? contentWarning : nil,
                sensitive: isSensitive, quoteID: publishQuotingID,
                quoteApprovalPolicy: effectiveQuoteApprovalPolicy,
                language: publishLanguageCode, scheduledAt: publishDate?.ISO8601Format(), poll: pollPayload)

            for attachment in attachments where attachment.requiresMetadataSync {
                _ = try await apiClient.updateMedia(
                    id: attachment.id, description: attachment.description, focus: attachment.focus)
            }

            let result: StatusPublishResult
            if case .edit(let status) = context {
                let warningIsUnchanged = contentWarning == editSource?.spoilerText
                    && isContentWarningActive == !(editSource?.spoilerText ?? "").isEmpty
                let updatedStatus = try await apiClient.editStatus(
                    id: status.displayStatus.id,
                    text: content,
                    visibility: visibility,
                    mediaIDs: mediaIDs,
                    inReplyToID: publishReplyToID,
                    spoilerText: isContentWarningActive ? contentWarning : "",
                    sensitive: warningIsUnchanged ? status.displayStatus.sensitive : (isSensitive ?? false),
                    quotingID: publishQuotingID,
                    language: publishLanguageCode,
                    poll: nil
                )
                result = .posted(updatedStatus)
            } else {
                publishAttempt = try ComposePublishAttempt.resolving(payload, previous: publishAttempt)
                result = try await apiClient.publishStatus(
                    text: payload.status, visibility: payload.visibility, mediaIDs: payload.mediaIDs,
                    inReplyToID: payload.inReplyToID, spoilerText: payload.spoilerText,
                    sensitive: payload.sensitive, quotingID: payload.quoteID,
                    quoteApprovalPolicy: payload.quoteApprovalPolicy, language: payload.language,
                    scheduledAt: publishDate, poll: payload.poll,
                    idempotencyKey: publishAttempt?.idempotencyKey
                )
            }

            completedPublishResult = result
            hasPublished = true
            AppSettings.shared.recordRecentPostLanguage(payload.language)

            if case .posted(let status) = result {
                if case .edit = context {
                    feedCoordinator.publishUpdate(.post(status))
                } else {
                    feedCoordinator.publishUpdate(.createdPost(status))
                }
            }

            return result
        } catch {
            publishError = error
            throw error
        }
    }
    
    // MARK: - Validation

    var publishBlocker: PublishBlocker? {
        if !isEditingSourceReady {
            return .editSourceUnavailable
        }
        if isPublishing || hasPublished {
            return .publishing
        }

        if hasUploadingMedia {
            return .mediaUploading
        }

        if hasFailedMedia {
            return .mediaUploadFailed
        }

        if hasPendingSharedMedia {
            return .sharedImportIncomplete
        }

        if characterCount > maxCharacters {
            return .characterLimitExceeded
        }

        if isPollActive && !mediaAttachments.isEmpty {
            return .pollCannotIncludeMedia
        }

        if let scheduledPublishDate, scheduledPublishDate < minimumScheduledDate {
            return .scheduledDateTooSoon
        }

        if isPollActive && normalizedPollOptions.count < 2 {
            return .pollNeedsMoreOptions
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPollActive
            && mediaAttachments.isEmpty
        {
            return .emptyContent
        }

        return nil
    }

    var publishDisabledReason: String? {
        switch publishBlocker {
        case .editSourceUnavailable:
            return nil // The editor itself presents loading or retry UI.
        case .emptyContent, .publishing, .characterLimitExceeded, .pollNeedsMoreOptions, .none:
            return nil
        case .mediaUploading:
            return MoroL10n.Compose.validationMediaUploading
        case .mediaUploadFailed:
            return MoroL10n.Compose.validationMediaUploadFailed
        case .sharedImportIncomplete:
            return MoroL10n.ShareImport.unfinished
        case .pollCannotIncludeMedia:
            return MoroL10n.Compose.validationPollCannotIncludeMedia
        case .scheduledDateTooSoon:
            return MoroL10n.Compose.errorInvalidScheduledDate
        }
    }

    var normalizedPollOptions: [String] {
        pollOptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasUploadingMedia: Bool {
        mediaAttachments.contains {
            if case .uploading = $0.uploadState {
                return true
            }
            return false
        }
    }

    var hasFailedMedia: Bool {
        mediaAttachments.contains {
            if case .failed = $0.uploadState {
                return true
            }
            return false
        }
    }

    var draftPersistenceBlocker: String? {
        if !isEditingSourceReady {
            return MoroL10n.Compose.editSourceFailed
        }
        if hasUploadingMedia {
            return MoroL10n.Compose.validationMediaUploading
        }
        for attachment in mediaAttachments where attachment.sharedImportItemID == nil {
            if case .failed = attachment.uploadState {
                return MoroL10n.Compose.validationMediaUploadFailed
            }
        }
        return nil
    }
    
    var canPublish: Bool {
        publishBlocker == nil
    }

    // MARK: - Draft Support

    var hasDraftableContent: Bool {
        guard isEditingSourceReady, !hasPublished else { return false }
        let hasTextContent = !draftableTextContent.isEmpty
        let hasPollContent = isPollActive && pollOptions.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasTextContent
            || !mediaAttachments.isEmpty
            || hasPollContent
    }

    private var draftableTextContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if case .reply = context, Self.isMentionOnlyText(trimmed) {
            return ""
        }

        return trimmed
    }

    private static func isMentionOnlyText(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy(isMentionToken)
    }

    private static func isMentionToken(_ token: Substring) -> Bool {
        guard token.hasPrefix("@"), token.count > 1 else { return false }

        let body = token.dropFirst()
        guard let first = body.unicodeScalars.first,
              CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "_"))
                .contains(first) else {
            return false
        }

        let allowedScalars = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-@"))
        return body.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }

    func makeDraft(category: ComposeDraftCategory) -> ComposeDraft {
        let target: ComposeDraftTarget
        switch context {
        case .newPost:
            target = ComposeDraftTarget(kind: .newPost)
        case .reply(let status):
            target = ComposeDraftTarget(
                kind: .reply,
                referenceStatus: status,
                inReplyToID: publishReplyToID ?? status?.displayStatus.id
            )
        case .quote(let original):
            target = ComposeDraftTarget(
                kind: .quote,
                referenceStatus: original,
                quotingID: publishQuotingID ?? original?.displayStatus.id
            )
        case .edit:
            target = ComposeDraftTarget(kind: .newPost)
        }

        let payload = ComposeDraftPayload(
            content: content,
            contentWarning: contentWarning,
            isContentWarningActive: isContentWarningActive,
            visibility: visibility,
            mediaAttachments: mediaAttachments
                .filter { $0.uploadState.isUploaded }
                .map { ComposeDraftAttachment($0) },
            isPollActive: isPollActive,
            pollOptions: pollOptions,
            pollMultiple: pollMultiple,
            pollExpiresIn: pollExpiresIn,
            isSchedulingEnabled: isScheduledPublishingActive,
            scheduledAt: isScheduledPublishingActive ? scheduledAt : nil,
            selectedLanguageCode: selectedLanguageCode,
            quotePolicyRawValue: quotePolicy.rawValue
        )

        let now = Date()
        let resolvedID = activeDraftID ?? UUID().uuidString
        let resolvedCreatedAt = activeDraftCreatedAt ?? now
        let resolvedCategory: ComposeDraftCategory = activeDraftCategory == .manual ? .manual : category

        activeDraftID = resolvedID
        activeDraftCreatedAt = resolvedCreatedAt
        activeDraftCategory = resolvedCategory

        var draft = ComposeDraft(
            id: resolvedID,
            accountID: currentUserID,
            category: resolvedCategory,
            target: target,
            payload: payload,
            createdAt: resolvedCreatedAt,
            updatedAt: now,
            publishAttempt: publishAttempt
        )
        draft.sharedImportItemIDs = activeSharedImportItemIDs.isEmpty ? nil : activeSharedImportItemIDs.sorted()
        return draft
    }

    func clearActiveDraftReference() {
        activeDraftID = nil
        activeDraftCreatedAt = nil
        activeDraftCategory = nil
        activeSharedImportItemIDs.removeAll()
        stagedSharedMediaPending = false
        sharedStagingUnreadable = false
    }
}

// MARK: - Supporting Types

struct MediaAttachment: Identifiable {
    let id: String
    let url: URL
    let previewURL: URL?
    let type: String
    var description: String?
    var focus: String? // Format: "x,y" where x and y are between -1.0 and 1.0
    var originalDescription: String? = nil
    var originalFocus: String? = nil
    
    // Upload state
    enum UploadState {
        case uploading(progress: Double) // 0.0 to 1.0
        case uploaded
        case failed(error: Error?)

        var isUploaded: Bool {
            if case .uploaded = self { return true }
            return false
        }
    }
    var uploadState: UploadState = .uploading(progress: 0.0)
    
    // Prepared off-main once, so SwiftUI rendering never decodes the same bytes repeatedly.
    var previewImage: UIImage? = nil

    // Keep original upload payload for retry when upload fails.
    var sourceUploadData: Data? = nil
    var sourceMimeType: String? = nil
    var sharedImportItemID: String? = nil
    var sharedImportAttachmentID: String? = nil

    private static func normalizedMetadata(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    var requiresMetadataSync: Bool {
        Self.normalizedMetadata(description) != Self.normalizedMetadata(originalDescription)
            || Self.normalizedMetadata(focus) != Self.normalizedMetadata(originalFocus)
    }
}

enum ComposeError: LocalizedError {
    case editSourceUnavailable
    case emptyContent
    case alreadyPublishing
    case mediaUploading
    case uploadFailed
    case sharedImportIncomplete
    case characterLimitExceeded
    case invalidPoll
    case pollCannotIncludeMedia
    case invalidScheduledDate
    
    var errorDescription: String? {
        switch self {
        case .editSourceUnavailable:
            return MoroL10n.Compose.editSourceFailed
        case .emptyContent:
            return MoroL10n.Compose.errorEmptyContent
        case .alreadyPublishing:
            return MoroL10n.Compose.errorAlreadyPublishing
        case .mediaUploading:
            return MoroL10n.Compose.errorMediaUploading
        case .uploadFailed:
            return MoroL10n.Compose.errorUploadFailed
        case .sharedImportIncomplete:
            return MoroL10n.ShareImport.unfinished
        case .characterLimitExceeded:
            return MoroL10n.Compose.errorCharacterLimitExceeded
        case .invalidPoll:
            return MoroL10n.Compose.errorInvalidPoll
        case .pollCannotIncludeMedia:
            return MoroL10n.Compose.errorPollCannotIncludeMedia
        case .invalidScheduledDate:
            return MoroL10n.Compose.errorInvalidScheduledDate
        }
    }
}
