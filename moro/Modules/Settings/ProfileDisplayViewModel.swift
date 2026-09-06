import Foundation
import Combine

@MainActor
final class ProfileDisplayViewModel: ObservableObject {
    @Published var showTags: Bool
    @Published var showMedia = true
    @Published var showMediaReplies = false
    @Published var showFeatured = true
    @Published var showConnections = true
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    private var original: EditableProfile?
    private var originalShowTags: Bool
    private let apiClient: MastodonAPI
    private let accountKey: String
    private let preferences: ProfilePresentationPreferences

    init(apiClient: MastodonAPI, accountKey: String, preferences: ProfilePresentationPreferences = .shared) {
        self.apiClient = apiClient
        self.accountKey = accountKey
        self.preferences = preferences
        originalShowTags = preferences.showsFeaturedTags(accountKey: accountKey)
        showTags = originalShowTags
    }

    var supportsMedia: Bool { original?.showMedia != nil }
    var supportsMediaReplies: Bool { original?.showMediaReplies != nil }
    var supportsFeatured: Bool { original?.showFeatured != nil }
    var hasChanges: Bool { showTags != originalShowTags || serverUpdate != nil }

    var serverUpdate: ProfileDisplayUpdate? {
        guard let original else { return nil }
        let media = original.showMedia.flatMap { $0 != showMedia ? showMedia : nil }
        let replies = original.showMediaReplies.flatMap { $0 != showMediaReplies ? showMediaReplies : nil }
        let featured = original.showFeatured.flatMap { $0 != showFeatured ? showFeatured : nil }
        let connections: Bool? = (original.hideCollections ?? false) != !showConnections ? !showConnections : nil
        guard media != nil || replies != nil || featured != nil || connections != nil else { return nil }
        return ProfileDisplayUpdate(showMedia: media, showMediaReplies: replies,
            showFeatured: featured, hideCollections: connections)
    }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let profile = try await apiClient.fetchEditableProfile()
            try Task.checkCancellation()
            original = profile
            showMedia = profile.showMedia ?? true
            showMediaReplies = profile.showMediaReplies ?? false
            showFeatured = profile.showFeatured ?? true
            showConnections = !(profile.hideCollections ?? false)
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save(to appState: AppState) async -> Bool {
        guard hasChanges, !isLoading, !isSaving else { return false }
        isSaving = true
        error = nil
        let activeToken = appState.authToken
        let activeAccountID = appState.currentAccount?.id
        defer { isSaving = false }
        do {
            if let update = serverUpdate {
                if let activeAccountID, activeAccountID != original?.id { throw APIError.authenticationRequired }
                let updatedAccount: Account
                if supportsMedia || supportsMediaReplies || supportsFeatured {
                    _ = try await apiClient.updateProfileDisplay(update)
                    updatedAccount = try await apiClient.verifyCredentials()
                } else {
                    updatedAccount = try await apiClient.updateAccountCredentials(
                        discoverable: nil, locked: nil, indexable: nil,
                        hideCollections: update.hideCollections, privacy: nil)
                }
                guard appState.authToken == activeToken, appState.currentAccount?.id == activeAccountID else { return false }
                appState.currentAccount = updatedAccount
                CacheManager.shared.accountCache.set(updatedAccount)
            }
            preferences.setShowsFeaturedTags(showTags, accountKey: accountKey)
            originalShowTags = showTags
            if let old = original {
                original = EditableProfile(id: old.id, displayName: old.displayName, note: old.note, fields: old.fields,
                    showMedia: supportsMedia ? showMedia : nil,
                    showMediaReplies: supportsMediaReplies ? showMediaReplies : nil,
                    showFeatured: supportsFeatured ? showFeatured : nil,
                    hideCollections: !showConnections)
            }
            AppFeedbackCenter.shared.showSuccess(MoroL10n.EditProfile.toastUpdated)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
