import SwiftUI
import PhotosUI
import Combine

@MainActor
final class EditProfileViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum Scope { case basic, fields, all }
    let scope: Scope
    static let maxFieldCount = 4
    static let bioCharacterLimit = 500

    struct FieldPair: Equatable {
        let name: String
        let value: String
    }

    struct EditableField: Identifiable, Hashable {
        let id: UUID
        var name: String
        var value: String

        init(id: UUID = UUID(), name: String = "", value: String = "") {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    @Published private(set) var limits = ProfileLimits()
    @Published private(set) var hasLoadedSource = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    private var loadedProfileID: String?
    private var originalFieldValues: [UUID: FieldPair] = [:]

    @Published var displayName: String
    @Published var note: String
    @Published var fields: [EditableField]
    @Published var avatarPreviewImage: UIImage?
    @Published var headerPreviewImage: UIImage?
    @Published private(set) var isAvatarRemoved = false
    @Published private(set) var isHeaderRemoved = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var account: Account?

    private let apiClient: MastodonAPI
    private var avatarUpload: AccountProfileImageUpload?
    private var headerUpload: AccountProfileImageUpload?

    private var originalDisplayName: String
    private var originalNote: String
    private var originalFields: [FieldPair]

    init(apiClient: MastodonAPI, initialAccount: Account?, scope: Scope = .all) {
        self.scope = scope
        self.apiClient = apiClient
        self.account = initialAccount

        let loadedDisplayName = initialAccount?.displayName ?? ""
        let loadedNote = initialAccount?.source?.note ?? ""
        let loadedFields = (initialAccount?.source?.fields ?? []).map {
            EditableField(name: $0.name, value: $0.value)
        }
        displayName = loadedDisplayName
        note = loadedNote
        fields = loadedFields
        originalDisplayName = loadedDisplayName
        originalNote = loadedNote
        originalFields = loadedFields.map { FieldPair(name: $0.name, value: $0.value) }
        originalFieldValues = Dictionary(uniqueKeysWithValues: loadedFields.map {
            ($0.id, FieldPair(name: $0.name, value: $0.value))
        })
    }

    func load() async {
        guard !hasLoadedSource, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let source = try await apiClient.fetchEditableProfile()
            guard account == nil || source.id == account?.id else { throw APIError.authenticationRequired }
            loadedProfileID = source.id
            let metadata = try? await InstanceMetadataStore.shared.load(apiClient: apiClient)
            try Task.checkCancellation()
            if let configuredLimits = metadata?.configuration?.accounts { limits = configuredLimits }
            displayName = source.displayName
            note = source.note
            fields = source.fields.map { EditableField(name: $0.name, value: $0.value) }
            originalDisplayName = displayName
            originalNote = note
            originalFields = fields.map { FieldPair(name: $0.name, value: $0.value) }
            originalFieldValues = Dictionary(uniqueKeysWithValues: fields.map {
                ($0.id, FieldPair(name: $0.name, value: $0.value))
            })
            hasLoadedSource = true
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    func moveFields(from offsets: IndexSet, to destination: Int) {
        fields.move(fromOffsets: offsets, toOffset: destination)
    }

    var isBusy: Bool {
        isSaving
    }

    var hasUnsavedChanges: Bool {
        hasAnyChanges
    }

    var canSave: Bool {
        hasLoadedSource && hasAnyChanges && !isBusy
    }

    var canRemoveAvatar: Bool {
        !isAvatarRemoved && (avatarPreviewImage != nil || hasExistingAvatar)
    }

    var canRemoveHeader: Bool {
        !isHeaderRemoved && (headerPreviewImage != nil || hasExistingHeader)
    }

    /// Half-filled fields. A row left completely blank is an unused slot, not an error.
    var invalidFieldIDs: Set<UUID> {
        Set(
            fields.compactMap { field in
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty != value.isEmpty ? field.id : nil
            }
        )
    }

    /// Fields whose edited part is over the server's limit. Text the server already
    /// accepted stays valid even if the instance has since lowered its limits.
    var overLimitFieldIDs: Set<UUID> {
        Set(fields.compactMap { field in
            let original = originalFieldValues[field.id]
            let nameOver = field.name != original?.name && field.name.count > limits.fieldNameLength
            let valueOver = field.value != original?.value && field.value.count > limits.fieldValueLength
            return nameOver || valueOver ? field.id : nil
        })
    }

    var hasPendingAvatarChange: Bool { avatarUpload != nil || isAvatarRemoved }
    var hasPendingHeaderChange: Bool { headerUpload != nil || isHeaderRemoved }

    /// Back to what the server has: drops a picked image and cancels a removal.
    func revertAvatar() {
        guard !isBusy else { return }
        avatarUpload = nil
        avatarPreviewImage = nil
        isAvatarRemoved = false
    }

    func revertHeader() {
        guard !isBusy else { return }
        headerUpload = nil
        headerPreviewImage = nil
        isHeaderRemoved = false
    }

    func moveField(id: UUID, by offset: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }),
              fields.indices.contains(index + offset) else { return }
        fields.swapAt(index, index + offset)
    }

    @discardableResult
    func addField() -> UUID? {
        guard fields.count < limits.fieldCount else { return nil }
        let field = EditableField()
        fields.append(field)
        return field.id
    }

    func resetPendingChanges() {
        guard !isBusy else { return }

        displayName = originalDisplayName
        note = originalNote
        fields = originalFields.map { field in
            EditableField(name: field.name, value: field.value)
        }

        originalFieldValues = Dictionary(uniqueKeysWithValues: fields.map {
            ($0.id, FieldPair(name: $0.name, value: $0.value))
        })
        avatarUpload = nil
        headerUpload = nil
        avatarPreviewImage = nil
        headerPreviewImage = nil
        isAvatarRemoved = false
        isHeaderRemoved = false
    }

    func removeField(id: UUID) {
        fields.removeAll { $0.id == id }
    }

    func updateNote(_ value: String) {
        note = String(value.prefix(max(limits.noteLength, originalNote.count)))
    }

    func selectAvatar(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastAvatarLoadFailed)
            return
        }
        guard
            let prepared = Self.prepareImageUpload(
                data: data,
                maxDimension: 1024,
                fileNamePrefix: "avatar"
            )
        else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastAvatarProcessFailed)
            return
        }

        avatarPreviewImage = prepared.previewImage
        avatarUpload = prepared.upload
        isAvatarRemoved = false
    }

    func selectHeader(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastHeaderLoadFailed)
            return
        }
        guard
            let prepared = Self.prepareImageUpload(
                data: data,
                maxDimension: 2048,
                fileNamePrefix: "header"
            )
        else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastHeaderProcessFailed)
            return
        }

        headerPreviewImage = prepared.previewImage
        headerUpload = prepared.upload
        isHeaderRemoved = false
    }

    func markAvatarRemoved() {
        guard !isBusy else { return }
        avatarUpload = nil
        avatarPreviewImage = nil
        isAvatarRemoved = hasExistingAvatar
    }

    func restoreAvatar() {
        guard !isBusy else { return }
        isAvatarRemoved = false
    }

    func markHeaderRemoved() {
        guard !isBusy else { return }
        headerUpload = nil
        headerPreviewImage = nil
        isHeaderRemoved = hasExistingHeader
    }

    func restoreHeader() {
        guard !isBusy else { return }
        isHeaderRemoved = false
    }

    func save(to appState: AppState) async -> Bool {
        guard !isBusy, hasLoadedSource else { return false }
        if let activeID = appState.currentAccount?.id, activeID != loadedProfileID { return false }

        let normalizedName = displayName == originalDisplayName
            ? displayName : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note

        guard let normalizedFields = scope == .basic ? [] : normalizedFieldsForSubmit() else {
            AppFeedbackCenter.shared.showError(MoroL10n.EditProfile.toastFieldsIncomplete)
            return false
        }

        guard hasAnyChanges else {
            AppFeedbackCenter.shared.showInfo(MoroL10n.EditProfile.toastNoChanges)
            return false
        }

        let changesName = scope != .fields && normalizedName != originalDisplayName
        let changesNote = scope != .fields && normalizedNote != originalNote
        if (changesName && normalizedName.count > limits.displayNameLength)
            || (changesNote && normalizedNote.count > limits.noteLength) {
            AppFeedbackCenter.shared.showError(MoroL10n.ProfileEditing.limitsExceeded)
            return false
        }
        let changesFields = scope != .basic && normalizedFieldsForComparison() != originalFields
        let activeToken = appState.authToken
        let activeAccountID = appState.currentAccount?.id
        isSaving = true
        defer { isSaving = false }

        do {
            // The API replaces the whole collection. Detect edits made on another client
            // before overwriting untouched entries (the server has no conditional-write API).
            if changesFields {
                let latest = try await apiClient.fetchEditableProfile()
                guard latest.id == loadedProfileID else { throw APIError.authenticationRequired }
                guard latest.fields.map({ FieldPair(name: $0.name, value: $0.value) }) == originalFields else {
                    throw ProfileEditingError.fieldsChangedElsewhere
                }
            }
            let previousAccount = account ?? appState.currentAccount
            let requestedAvatarReplacement = avatarUpload != nil
            let requestedHeaderReplacement = headerUpload != nil
            let requestedAvatarRemoval = isAvatarRemoved && avatarUpload == nil
            let requestedHeaderRemoval = isHeaderRemoved && headerUpload == nil

            let serverReturnedAccount = try await apiClient.updateAccountProfile(
                displayName: changesName ? normalizedName : nil,
                note: changesNote ? normalizedNote : nil,
                avatar: avatarUpload,
                header: headerUpload,
                removeAvatar: requestedAvatarRemoval,
                removeHeader: requestedHeaderRemoval,
                fields: changesFields ? normalizedFields : nil
            )

            let updatedAccount = await resolveLatestAccountAfterProfileUpdate(
                fallback: serverReturnedAccount,
                previous: previousAccount,
                requestedAvatarRemoval: requestedAvatarRemoval,
                requestedHeaderRemoval: requestedHeaderRemoval,
                requestedAvatarReplacement: requestedAvatarReplacement,
                requestedHeaderReplacement: requestedHeaderReplacement
            )

            guard appState.authToken == activeToken, appState.currentAccount?.id == activeAccountID else { return false }
            applyUpdatedAccount(
                updatedAccount,
                to: appState,
                bustAvatarURL: requestedAvatarReplacement || requestedAvatarRemoval,
                bustHeaderURL: requestedHeaderReplacement || requestedHeaderRemoval
            )

            avatarUpload = nil
            headerUpload = nil
            avatarPreviewImage = nil
            headerPreviewImage = nil
            isAvatarRemoved = false
            isHeaderRemoved = false

            originalDisplayName = changesName ? normalizedName : originalDisplayName
            originalNote = changesNote ? normalizedNote : originalNote
            if changesFields {
                originalFields = normalizedFields.map { FieldPair(name: $0.name, value: $0.value) }
                fields = normalizedFields.map { EditableField(name: $0.name, value: $0.value) }
                originalFieldValues = Dictionary(uniqueKeysWithValues: fields.map {
                    ($0.id, FieldPair(name: $0.name, value: $0.value))
                })
            }

            AppFeedbackCenter.shared.showSuccess(MoroL10n.EditProfile.toastUpdated)
            return true
        } catch {
            AppFeedbackCenter.shared.showError(error.localizedDescription)
            return false
        }
    }

    private func applyUpdatedAccount(
        _ updatedAccount: Account,
        to appState: AppState,
        bustAvatarURL: Bool = false,
        bustHeaderURL: Bool = false
    ) {
        let appliedAccount = updatedAccount.withCacheBustedMedia(
            avatar: bustAvatarURL,
            header: bustHeaderURL
        )

        account = appliedAccount
        appState.currentAccount = appliedAccount
        CacheManager.shared.accountCache.set(appliedAccount)
        invalidateImageCachesForProfileUpdate()
    }

    private func resolveLatestAccountAfterProfileUpdate(
        fallback: Account,
        previous: Account?,
        requestedAvatarRemoval: Bool,
        requestedHeaderRemoval: Bool,
        requestedAvatarReplacement: Bool,
        requestedHeaderReplacement: Bool
    ) async -> Account {
        var latest = fallback

        // Some instances may return stale media URLs immediately after profile update.
        // Re-verify credentials with short retries to converge on authoritative account state.
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            guard let verified = try? await apiClient.verifyCredentials() else { continue }
            latest = verified

            let needsRetry = shouldRetryAccountRefresh(
                previous: previous,
                latest: verified,
                requestedAvatarRemoval: requestedAvatarRemoval,
                requestedHeaderRemoval: requestedHeaderRemoval,
                requestedAvatarReplacement: requestedAvatarReplacement,
                requestedHeaderReplacement: requestedHeaderReplacement
            )

            if !needsRetry {
                break
            }
        }

        return latest
    }

    private func shouldRetryAccountRefresh(
        previous: Account?,
        latest: Account,
        requestedAvatarRemoval: Bool,
        requestedHeaderRemoval: Bool,
        requestedAvatarReplacement: Bool,
        requestedHeaderReplacement: Bool
    ) -> Bool {
        guard let previous else { return false }

        let avatarChangeRequested = requestedAvatarRemoval || requestedAvatarReplacement
        let headerChangeRequested = requestedHeaderRemoval || requestedHeaderReplacement

        let avatarUnchanged =
            previous.avatar == latest.avatar
            && previous.avatarStatic == latest.avatarStatic
        let headerUnchanged =
            previous.header == latest.header
            && previous.headerStatic == latest.headerStatic

        return (avatarChangeRequested && avatarUnchanged)
            || (headerChangeRequested && headerUnchanged)
    }

    private func invalidateImageCachesForProfileUpdate() {
        URLCache.shared.removeAllCachedResponses()
        ImageCache.shared.clearMemoryCache()
    }

    private var hasAnyChanges: Bool {
        let basicChanged = displayName != originalDisplayName
            || note != originalNote || avatarUpload != nil || headerUpload != nil || isAvatarRemoved || isHeaderRemoved
        let fieldsChanged = normalizedFieldsForComparison() != originalFields
        switch scope {
        case .basic: return basicChanged
        case .fields: return fieldsChanged
        case .all: return basicChanged || fieldsChanged
        }
    }

    private var hasExistingAvatar: Bool {
        account?.profileAvatarURL != nil
    }

    private var hasExistingHeader: Bool {
        account?.profileHeaderURL != nil
    }

    /// Fields with both parts blank are ignored: adding a row and leaving it empty
    /// is not a change, and saving simply drops it.
    private var meaningfulFields: [EditableField] {
        fields.filter {
            !($0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func normalizedFieldsForComparison() -> [FieldPair] {
        meaningfulFields.map { field in
            let original = originalFieldValues[field.id]
            return FieldPair(
                name: field.name == original?.name ? field.name : field.name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: field.value == original?.value ? field.value : field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func normalizedFieldsForSubmit() -> [AccountField]? {
        let kept = meaningfulFields
        let pairs = normalizedFieldsForComparison()
        // Keep previously accepted fields even if the instance later lowers its limit.
        guard kept.count <= max(limits.fieldCount, originalFields.count) else { return nil }
        for (field, pair) in zip(kept, pairs) {
            let original = originalFieldValues[field.id]
            if pair.name != original?.name && (pair.name.isEmpty || pair.name.count > limits.fieldNameLength) { return nil }
            if pair.value != original?.value && (pair.value.isEmpty || pair.value.count > limits.fieldValueLength) { return nil }
        }
        return pairs.map { AccountField(name: $0.name, value: $0.value) }
    }

    private static func prepareImageUpload(
        data: Data,
        maxDimension: CGFloat,
        fileNamePrefix: String
    ) -> (previewImage: UIImage, upload: AccountProfileImageUpload)? {
        guard let originalImage = UIImage(data: data) else { return nil }
        let processedImage = resizeIfNeeded(originalImage, maxDimension: maxDimension)
        guard let jpegData = processedImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        let upload = AccountProfileImageUpload(
            data: jpegData,
            fileName: "\(fileNamePrefix)-\(UUID().uuidString).jpg",
            mimeType: "image/jpeg"
        )
        return (processedImage, upload)
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        guard width > maxDimension || height > maxDimension else { return image }

        let scale = min(maxDimension / width, maxDimension / height)
        let newSize = CGSize(width: width * scale, height: height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
}
