//
//  ProfileViewModel.swift
//  moro
//
//  ViewModel for managing profile data and user posts.
//

import Foundation
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    
    enum Tab: String, CaseIterable, Hashable {
        case posts = "Posts"
        case replies = "Replies"
        case media = "Media"

        var localizedTitle: String {
            switch self {
            case .posts: MoroL10n.ProfileEditing.posts
            case .replies: MoroL10n.ProfileEditing.replies
            case .media: MoroL10n.ProfileEditing.media
            }
        }
    }

    enum TabLoadState: Equatable {
        case notLoaded
        case loading
        case loaded
        case error(String)
    }
    
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
        
        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
                return true
            case let (.error(l), .error(r)):
                return l == r
            default:
                return false
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published var account: Account? {
        didSet {
            if (oldValue?.showMediaReplies ?? false) != (account?.showMediaReplies ?? false) {
                mediaPreferenceRevision = UUID()
                media = []
                mediaMaxID = nil
                hasMoreMedia = true
                tabLoadStates[.media] = .notLoaded
                loadingMoreTabs.remove(.media)
                loadMoreFailedTabs.remove(.media)
            }
            if account?.showMedia == false && selectedTab == .media { selectedTab = .posts }
        }
    }
    @Published private(set) var mediaPreferenceRevision = UUID()
    var availableTabs: [Tab] { account?.showMedia == false ? [.posts, .replies] : Tab.allCases }

    @Published private(set) var selectedTab: Tab = .posts
    @Published var loadingState: LoadingState = .idle
    @Published private(set) var tabLoadStates: [Tab: TabLoadState] = Dictionary(
        uniqueKeysWithValues: Tab.allCases.map { ($0, .notLoaded) }
    )
    @Published private(set) var loadingMoreTabs: Set<Tab> = []
    @Published private(set) var loadMoreFailedTabs: Set<Tab> = []
    @Published var relationship: Relationship?
    @Published var isLoadingRelationship = false
    @Published var isUpdatingRelationship = false
    @Published var isUpdatingNotification = false
    
    // Statuses for each tab
    @Published var posts: [Status] = []
    @Published var replies: [Status] = []
    @Published var media: [Status] = []
    @Published var pinnedStatuses: [Status] = []
    @Published private(set) var featuredTags: [FeaturedTag] = []
    @Published private(set) var selectedFeaturedTag: String?
    @Published private(set) var featuredTagsEnabled = true
    private var queryGeneration = UUID()
    private var featuredTagsRequestID = UUID()
    private var pinnedRequestID = UUID()
    private var consecutiveEmptyPages: [Tab: Int] = [:]

    var showsFeaturedTags: Bool {
        ProfilePresentationPreferences.shouldShowTags(enabled: featuredTagsEnabled, tags: featuredTags)
    }

    func setFeaturedTagsEnabled(_ enabled: Bool) async {
        featuredTagsEnabled = enabled
        if !enabled, selectedFeaturedTag != nil { await selectFeaturedTag(nil) }
    }

    func loadFeaturedTags() async {
        let requestID = UUID()
        featuredTagsRequestID = requestID
        do {
            let tags = try await apiClient.fetchAccountFeaturedTags(accountID: resolvedAccountID)
            guard requestID == featuredTagsRequestID, !Task.isCancelled else { return }
            featuredTags = tags
            if let selectedFeaturedTag, !tags.contains(where: { $0.name == selectedFeaturedTag }) {
                await selectFeaturedTag(nil)
            }
        } catch {
            // Optional profile curation must not block reading the account's posts.
        }
    }

    func selectFeaturedTag(_ name: String?) async {
        let tag = featuredTagsEnabled ? name.flatMap { value in featuredTags.first(where: { $0.name == value })?.name } : nil
        guard tag != selectedFeaturedTag else { return }
        selectedFeaturedTag = tag
        queryGeneration = UUID()
        posts = []; replies = []; media = []; pinnedStatuses = []
        postsMaxID = nil; repliesMaxID = nil; mediaMaxID = nil
        hasMorePosts = true; hasMoreReplies = true; hasMoreMedia = true
        tabLoadStates = Dictionary(uniqueKeysWithValues: Tab.allCases.map { ($0, .notLoaded) })
        loadingMoreTabs = []; loadMoreFailedTabs = []
        consecutiveEmptyPages = [:]
        async let pins: Void = fetchPinnedStatuses()
        await loadTabIfNeeded(selectedTab)
        await pins
    }
    
    // MARK: - Private Properties
    
    private let apiClient: MastodonAPI
    private let accountID: String
    private let accountCache: AccountCache
    private let feedCoordinator: FeedCoordinator
    private var cancellables = Set<AnyCancellable>()
    var currentAccountID: String? // Allow updating from ProfileView
    
    // Pagination
    private var postsMaxID: String?
    private var repliesMaxID: String?
    private var mediaMaxID: String?
    
    private var hasMorePosts = true
    private var hasMoreReplies = true
    private var hasMoreMedia = true
    private let pageSize = 20
    
    // MARK: - Computed Properties
    
    var currentStatuses: [Status] {
        switch selectedTab {
        case .posts:
            let pinnedIDs = Set(pinnedStatuses.map(\.id))
            return posts.filter { !pinnedIDs.contains($0.id) }
        case .replies:
            return replies
        case .media:
            return media
        }
    }
    
    var hasMore: Bool {
        hasMore(for: selectedTab)
    }

    var paginationCursor: String? { maxID(for: selectedTab) }
    var shouldAutomaticallyContinueEmptyPage: Bool { (consecutiveEmptyPages[selectedTab] ?? 0) < 3 }

    func tabLoadState(for tab: Tab) -> TabLoadState {
        tabLoadStates[tab] ?? .notLoaded
    }

    func isLoadingMore(_ tab: Tab) -> Bool {
        loadingMoreTabs.contains(tab)
    }

    func didFailLoadMore(_ tab: Tab) -> Bool {
        loadMoreFailedTabs.contains(tab)
    }

    private func statuses(for tab: Tab) -> [Status] {
        switch tab {
        case .posts:
            return posts
        case .replies:
            return replies
        case .media:
            return media
        }
    }

    private func hasMore(for tab: Tab) -> Bool {
        switch tab {
        case .posts:
            return hasMorePosts
        case .replies:
            return hasMoreReplies
        case .media:
            return hasMoreMedia
        }
    }

    private var resolvedAccountID: String {
        if !accountID.isEmpty {
            return accountID
        }
        if let accountID = account?.id, !accountID.isEmpty {
            return accountID
        }
        return currentAccountID ?? ""
    }

    private var isCurrentUserProfile: Bool {
        guard let currentAccountID else { return false }
        if !accountID.isEmpty {
            return accountID == currentAccountID
        }
        if let accountID = account?.id, !accountID.isEmpty {
            return accountID == currentAccountID
        }
        // Fallback for "Me" tab before account is hydrated.
        return true
    }
    
    // MARK: - Initialization
    
    init(
        apiClient: MastodonAPI,
        accountID: String,
        currentAccountID: String? = nil,
        accountCache: AccountCache? = nil,
        feedCoordinator: FeedCoordinator? = nil
    ) {
        self.apiClient = apiClient
        self.accountID = accountID
        self.currentAccountID = currentAccountID
        self.accountCache = accountCache ?? CacheManager.shared.accountCache
        self.feedCoordinator = feedCoordinator ?? .shared
        
        // Listen to feed coordinator updates for real-time state sync
        self.feedCoordinator.$mostRecentUpdate
            .compactMap { $0 }
            .sink { [weak self] update in
                self?.incorporateUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func loadInitial() async {
        // Allow retrying from any error. The previous `== .error("")` comparison only
        // matched an empty-message error, so retry after a real failure was a no-op.
        switch loadingState {
        case .idle, .error:
            break
        default:
            return
        }

        loadingState = .loading
        
        do {
            // Load account details if not already set
            if account == nil {
                let fetchedAccount = try await fetchLatestProfileAccount()
                account = fetchedAccount
                accountCache.set(fetchedAccount)
            }
            
            // Load relationship if this is not the current user
            await loadRelationship()
            
            // Fetch pinned statuses
            await fetchPinnedStatuses()
            
            // Each tab owns its loading state. An empty successful response is still loaded.
            await loadTabIfNeeded(selectedTab)
            
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }
    }
    
    func refresh() async {
        var refreshedTab = selectedTab
        var mediaRevision = mediaPreferenceRevision
        let generation = queryGeneration
        let tag = selectedFeaturedTag
        loadingState = .loading
        do {
            let refreshedAccount = try await fetchLatestProfileAccount()
            guard generation == queryGeneration else { return }
            account = refreshedAccount
            accountCache.set(refreshedAccount)
            if !availableTabs.contains(refreshedTab) { refreshedTab = .posts }
            mediaRevision = mediaPreferenceRevision
            await loadRelationship()
            guard generation == queryGeneration else { return }
            await fetchPinnedStatuses()
            let page = try await fetchPage(for: refreshedTab, maxID: nil, tag: tag)
            guard generation == queryGeneration else { return }
            guard refreshedTab != .media || mediaRevision == mediaPreferenceRevision else { return }
            replaceContent(with: page, for: refreshedTab)
            tabLoadStates[refreshedTab] = .loaded
            loadMoreFailedTabs.remove(refreshedTab)
            loadingState = .loaded
            await loadFeaturedTags()
        } catch {
            guard acceptsResponse(generation: generation, tab: refreshedTab, mediaRevision: mediaRevision) else { return }
            if statuses(for: refreshedTab).isEmpty {
                tabLoadStates[refreshedTab] = .error(error.localizedDescription)
            }
            loadingState = .error(error.localizedDescription)
        }
    }

    func loadMore() async {
        let tab = selectedTab
        let mediaRevision = mediaPreferenceRevision
        let generation = queryGeneration
        let tag = selectedFeaturedTag
        guard tabLoadState(for: tab) == .loaded,
              hasMore(for: tab), !loadingMoreTabs.contains(tab) else { return }
        loadingMoreTabs.insert(tab)
        loadMoreFailedTabs.remove(tab)
        defer { if acceptsResponse(generation: generation, tab: tab, mediaRevision: mediaRevision) { loadingMoreTabs.remove(tab) } }
        do {
            let page = try await fetchPage(for: tab, maxID: maxID(for: tab), tag: tag)
            guard acceptsResponse(generation: generation, tab: tab, mediaRevision: mediaRevision) else { return }
            appendContent(from: page, for: tab)
        } catch {
            guard acceptsResponse(generation: generation, tab: tab, mediaRevision: mediaRevision) else { return }
            loadMoreFailedTabs.insert(tab)
        }
    }

    func selectTab(_ tab: Tab) {
        guard availableTabs.contains(tab) else { return }
        selectedTab = tab
    }

    func loadTabIfNeeded(_ tab: Tab) async {
        guard tabLoadState(for: tab) == .notLoaded else { return }
        let generation = queryGeneration
        let mediaRevision = mediaPreferenceRevision
        let tag = selectedFeaturedTag
        tabLoadStates[tab] = .loading
        do {
            let page = try await fetchPage(for: tab, maxID: nil, tag: tag)
            guard acceptsResponse(generation: generation, tab: tab, mediaRevision: mediaRevision) else { return }
            replaceContent(with: page, for: tab)
            tabLoadStates[tab] = .loaded
        } catch {
            guard acceptsResponse(generation: generation, tab: tab, mediaRevision: mediaRevision) else { return }
            tabLoadStates[tab] = .error(error.localizedDescription)
        }
    }

    func retryTab(_ tab: Tab) async {
        guard case .error = tabLoadState(for: tab) else { return }
        tabLoadStates[tab] = .notLoaded
        await loadTabIfNeeded(tab)
    }
    
    // MARK: - Private Methods

    private func acceptsResponse(generation: UUID, tab: Tab, mediaRevision: UUID) -> Bool {
        generation == queryGeneration && (tab != .media || mediaRevision == mediaPreferenceRevision)
    }

    private func fetchLatestProfileAccount() async throws -> Account {
        if isCurrentUserProfile {
            return try await apiClient.verifyCredentials()
        }

        let targetAccountID = resolvedAccountID
        guard !targetAccountID.isEmpty else {
            throw NSError(
                domain: "ProfileViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing profile account id"]
            )
        }
        return try await apiClient.fetchAccount(id: targetAccountID)
    }
    
    private struct TabPage {
        let displayedStatuses: [Status]
        let sourceStatuses: [Status]
    }

    private func fetchPage(for tab: Tab, maxID: String?, tag: String?) async throws -> TabPage {
        let sourceStatuses: [Status]
        switch tab {
        case .posts:
            sourceStatuses = try await apiClient.fetchAccountStatuses(
                id: resolvedAccountID,
                maxID: maxID,
                sinceID: nil,
                limit: pageSize,
                excludeReplies: true,
                excludeReblogs: false,
                onlyMedia: false,
                pinned: false,
                tagged: tag
            )
        case .replies:
            sourceStatuses = try await apiClient.fetchAccountStatuses(
                id: resolvedAccountID,
                maxID: maxID,
                sinceID: nil,
                limit: pageSize,
                excludeReplies: false,
                excludeReblogs: true,
                onlyMedia: false,
                pinned: false,
                tagged: tag
            )
        case .media:
            sourceStatuses = try await apiClient.fetchAccountStatuses(
                id: resolvedAccountID,
                maxID: maxID,
                sinceID: nil,
                limit: pageSize,
                excludeReplies: !(account?.showMediaReplies ?? false),
                excludeReblogs: true,
                onlyMedia: true,
                pinned: false,
                tagged: tag
            )
        }

        let displayedStatuses = tab == .replies
            ? sourceStatuses.filter { $0.inReplyToID != nil }
            : sourceStatuses
        return TabPage(
            displayedStatuses: displayedStatuses,
            sourceStatuses: sourceStatuses
        )
    }

    private func replaceContent(with page: TabPage, for tab: Tab) {
        consecutiveEmptyPages[tab] = page.displayedStatuses.isEmpty ? 1 : 0
        switch tab {
        case .posts:
            posts = page.displayedStatuses
            postsMaxID = page.sourceStatuses.last?.id
            hasMorePosts = page.sourceStatuses.count >= pageSize
        case .replies:
            replies = page.displayedStatuses
            repliesMaxID = page.sourceStatuses.last?.id
            hasMoreReplies = page.sourceStatuses.count >= pageSize
        case .media:
            media = page.displayedStatuses
            mediaMaxID = page.sourceStatuses.last?.id
            hasMoreMedia = page.sourceStatuses.count >= pageSize
        }
        accountCache.cacheFromStatuses(page.sourceStatuses)
    }

    private func appendContent(from page: TabPage, for tab: Tab) {
        consecutiveEmptyPages[tab] = page.displayedStatuses.isEmpty ? (consecutiveEmptyPages[tab] ?? 0) + 1 : 0
        switch tab {
        case .posts:
            posts = appendingUnique(page.displayedStatuses, to: posts)
            postsMaxID = page.sourceStatuses.last?.id ?? postsMaxID
            hasMorePosts = page.sourceStatuses.count >= pageSize
        case .replies:
            replies = appendingUnique(page.displayedStatuses, to: replies)
            repliesMaxID = page.sourceStatuses.last?.id ?? repliesMaxID
            hasMoreReplies = page.sourceStatuses.count >= pageSize
        case .media:
            media = appendingUnique(page.displayedStatuses, to: media)
            mediaMaxID = page.sourceStatuses.last?.id ?? mediaMaxID
            hasMoreMedia = page.sourceStatuses.count >= pageSize
        }
        accountCache.cacheFromStatuses(page.sourceStatuses)
    }

    private func appendingUnique(_ newStatuses: [Status], to existing: [Status]) -> [Status] {
        let existingIDs = Set(existing.map(\.id))
        return existing + newStatuses.filter { !existingIDs.contains($0.id) }
    }

    private func maxID(for tab: Tab) -> String? {
        switch tab {
        case .posts:
            return postsMaxID
        case .replies:
            return repliesMaxID
        case .media:
            return mediaMaxID
        }
    }
    
    // MARK: - Pinned Statuses
    
    /// Fetch pinned statuses for this account
    func fetchPinnedStatuses() async {
        let generation = queryGeneration
        let requestID = UUID()
        let tag = selectedFeaturedTag
        pinnedRequestID = requestID
        do {
            let statuses = try await apiClient.fetchAccountStatuses(
                id: resolvedAccountID, maxID: nil, sinceID: nil, limit: 20,
                excludeReplies: true, excludeReblogs: false, onlyMedia: false,
                pinned: true, tagged: tag
            )
            guard generation == queryGeneration, requestID == pinnedRequestID else { return }
            pinnedStatuses = statuses
            accountCache.cacheFromStatuses(statuses)
        } catch {
            // Keep the existing pinned section when refreshing fails.
        }
    }

    // MARK: - Poll Voting

    /// Vote on a poll
    func votePoll(pollID: String, choices: [Int]) async -> Bool {
        do {
            let updatedPoll = try await apiClient.votePoll(pollID: pollID, choices: choices)
            // The poll may live in the current tab OR in the pinned section above it; find
            // the owning status and apply the updated poll to every list it appears in.
            let allStatuses = posts + replies + media + pinnedStatuses
            guard let owner = allStatuses.first(where: { $0.displayStatus.poll?.id == pollID }) else {
                return false
            }
            let updatedStatus = owner.updating(poll: updatedPoll)
            replacePollOwningStatus(updatedStatus)
            return true
        } catch {
            AppLogger.error("Failed to vote on poll: \(error)")
            return false
        }
    }

    private func replacePollOwningStatus(_ status: Status) {
        if let i = posts.firstIndex(where: { $0.id == status.id }) { posts[i] = status }
        if let i = replies.firstIndex(where: { $0.id == status.id }) { replies[i] = status }
        if let i = media.firstIndex(where: { $0.id == status.id }) { media[i] = status }
        if let i = pinnedStatuses.firstIndex(where: { $0.id == status.id }) { pinnedStatuses[i] = status }
    }
    
    /// Remove a status from all tabs (e.g., after deletion)
    func removeStatus(id: String) {
        posts.removeAll { $0.id == id }
        replies.removeAll { $0.id == id }
        media.removeAll { $0.id == id }
    }
    
    // MARK: - Relationship Management
    
    func loadRelationship() async {
        let targetAccountID = resolvedAccountID

        // Only load relationship if this is not the current user
        guard let currentID = currentAccountID,
              targetAccountID != currentID else {
            relationship = nil
            return
        }
        guard !targetAccountID.isEmpty else {
            relationship = nil
            return
        }
        
        isLoadingRelationship = true
        defer { isLoadingRelationship = false }
        
        do {
            let relationships = try await apiClient.fetchRelationships(accountIDs: [targetAccountID])
            relationship = relationships.first
        } catch {
            AppLogger.error("Failed to load relationship: \(error)")
        }
    }
    
    func toggleFollow() async {
        guard !isUpdatingRelationship, !isUpdatingNotification else { return }
        let targetAccountID = resolvedAccountID
        guard !targetAccountID.isEmpty else { return }
        let wasFollowing = relationship?.following == true
        let shouldUnfollow = wasFollowing || relationship?.requested == true
        
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        
        do {
            let updatedRelationship: Relationship
            if shouldUnfollow {
                // The unfollow endpoint also cancels an outgoing follow request.
                updatedRelationship = try await apiClient.unfollowAccount(id: targetAccountID)
            } else {
                updatedRelationship = try await apiClient.followAccount(
                    id: targetAccountID,
                    reblogs: true,
                    notify: false
                )
            }
            relationship = updatedRelationship

            // A follow request is not a follower until it is approved.
            if let current = account, wasFollowing != updatedRelationship.following {
                let delta = updatedRelationship.following ? 1 : -1
                account = current.updating(followersCount: max(0, current.followersCount + delta))
            }
        } catch {
            AppLogger.error("Failed to toggle follow: \(error)")
        }
    }
    
    func toggleNotification() async {
        guard let relationship = relationship,
              relationship.following,
              !isUpdatingRelationship,
              !isUpdatingNotification else { return }
        let targetAccountID = resolvedAccountID
        guard !targetAccountID.isEmpty else { return }
        
        isUpdatingNotification = true
        defer { isUpdatingNotification = false }
        
        do {
            // Update notification setting by calling follow API again
            self.relationship = try await apiClient.followAccount(
                id: targetAccountID,
                reblogs: nil, // Keep existing setting
                notify: !relationship.notifying
            )
        } catch {
            AppLogger.error("Failed to toggle notification: \(error)")
        }
    }
    
    func toggleMute() async {
        guard !isUpdatingRelationship, !isUpdatingNotification else { return }
        let targetAccountID = resolvedAccountID
        guard !targetAccountID.isEmpty else { return }
        
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        
        do {
            if relationship?.muting == true {
                relationship = try await apiClient.unmuteAccount(id: targetAccountID)
            } else {
                relationship = try await apiClient.muteAccount(id: targetAccountID)
            }
        } catch {
            AppLogger.error("Failed to toggle mute: \(error)")
        }
    }
    
    func toggleBlock() async {
        guard !isUpdatingRelationship, !isUpdatingNotification else { return }
        let targetAccountID = resolvedAccountID
        guard !targetAccountID.isEmpty else { return }
        
        isUpdatingRelationship = true
        defer { isUpdatingRelationship = false }
        
        do {
            if relationship?.blocking == true {
                relationship = try await apiClient.unblockAccount(id: targetAccountID)
            } else {
                relationship = try await apiClient.blockAccount(id: targetAccountID)
            }
        } catch {
            AppLogger.error("Failed to toggle block: \(error)")
        }
    }
    
    // MARK: - FeedCoordinator Updates
    
    /// Incorporate status updates from FeedCoordinator (e.g., like/boost state changes, pin/unpin)
    private func incorporateUpdate(_ update: UpdatedElement) {
        switch update {
        case .createdPost(let status):
            guard status.account.id == resolvedAccountID, matchesSelectedTag(status) else { break }
            if status.inReplyToID == nil,
                !posts.contains(where: { $0.id == status.id })
            {
                posts.insert(status, at: 0)
            } else if status.inReplyToID != nil,
                !replies.contains(where: { $0.id == status.id })
            {
                replies.insert(status, at: 0)
            }
            if !status.mediaAttachments.isEmpty,
                status.inReplyToID == nil || account?.showMediaReplies == true,
                !media.contains(where: { $0.id == status.id })
            {
                media.insert(status, at: 0)
            }

        case .post(let updatedStatus):
            guard matchesSelectedTag(updatedStatus) else {
                if posts.contains(where: { $0.displayStatus.id == updatedStatus.id }) {
                    posts.removeAll { $0.displayStatus.id == updatedStatus.id }
                }
                if replies.contains(where: { $0.displayStatus.id == updatedStatus.id }) {
                    replies.removeAll { $0.displayStatus.id == updatedStatus.id }
                }
                if media.contains(where: { $0.displayStatus.id == updatedStatus.id }) {
                    media.removeAll { $0.displayStatus.id == updatedStatus.id }
                }
                if pinnedStatuses.contains(where: { $0.displayStatus.id == updatedStatus.id }) {
                    pinnedStatuses.removeAll { $0.displayStatus.id == updatedStatus.id }
                }
                break
            }
            // Update status in all tabs if it exists
            if let index = posts.firstIndex(where: { $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id }) {
                posts[index] = posts[index].incorporatingDisplayStatusUpdate(updatedStatus)
            }
            if let index = replies.firstIndex(where: { $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id }) {
                replies[index] = replies[index].incorporatingDisplayStatusUpdate(updatedStatus)
            }
            if let index = media.firstIndex(where: { $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id }) {
                media[index] = media[index].incorporatingDisplayStatusUpdate(updatedStatus)
            }
            
            // Handle pinned status changes
            let wasInPinned = pinnedStatuses.contains(where: {
                $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id
            })
            
            if wasInPinned && updatedStatus.pinned == false {
                // Only an explicit false is an unpin. Interaction responses commonly omit this
                // optional field, which must not make an existing profile pin disappear.
                pinnedStatuses.removeAll { $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id }
            } else if wasInPinned {
                if let index = pinnedStatuses.firstIndex(where: {
                    $0.id == updatedStatus.id || $0.displayStatus.id == updatedStatus.id
                }) {
                    pinnedStatuses[index] = pinnedStatuses[index].incorporatingDisplayStatusUpdate(updatedStatus)
                }
            } else if updatedStatus.pinned == true, updatedStatus.account.id == resolvedAccountID {
                // Newly pinned AND authored by THIS profile's account. The feed coordinator is
                // global, so without the ownership check a pin of ANY account's post was
                // inserted into every live profile's carousel (including hidden/covered ones) —
                // a cross-account leak, not just a redundant write.
                pinnedStatuses.insert(updatedStatus, at: 0)
            }
            
        case .deletedPost(let deletedID):
            // Guard each removal: `removeAll(where:)` fires @Published even when nothing
            // matches, so an un-guarded delete re-rendered hidden / pushed-over profiles on
            // every unrelated deletion. Only mutate the arrays this profile actually holds.
            if posts.contains(where: { $0.id == deletedID }) {
                posts.removeAll { $0.id == deletedID }
            }
            if replies.contains(where: { $0.id == deletedID }) {
                replies.removeAll { $0.id == deletedID }
            }
            if media.contains(where: { $0.id == deletedID }) {
                media.removeAll { $0.id == deletedID }
            }
            if pinnedStatuses.contains(where: { $0.id == deletedID }) {
                pinnedStatuses.removeAll { $0.id == deletedID }
            }
            
        case .hashtag, .relationship:
            // Not applicable for profile
            break
        }
    }

    private func matchesSelectedTag(_ status: Status) -> Bool {
        guard let selectedFeaturedTag else { return true }
        return status.displayStatus.tags?.contains {
            $0.name.localizedCaseInsensitiveCompare(selectedFeaturedTag) == .orderedSame
        } == true
    }
}
