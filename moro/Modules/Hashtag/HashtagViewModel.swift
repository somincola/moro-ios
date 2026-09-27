//
//  HashtagViewModel.swift
//  moro
//
//  Manages hashtag timeline state and data fetching.
//

import Foundation
import Combine

@MainActor
final class HashtagViewModel: ObservableObject, FeedCoordinatorUpdatable {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case refreshing
        case loadingMore
        case error(Error)
    }

    @Published var statuses: [Status] = []
    @Published var loadingState: LoadingState = .idle
    @Published var hasMore: Bool = true
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false

    private let apiClient: MastodonAPI
    private let hashtag: String
    private let feedCoordinator: FeedCoordinator
    private var currentMaxID: String?
    private var currentSinceID: String?
    private var cancellables = Set<AnyCancellable>()

    /// Shared account cache for user info lookup
    let accountCache: AccountCache

    init(
        apiClient: MastodonAPI,
        hashtag: String,
        accountCache: AccountCache? = nil,
        feedCoordinator: FeedCoordinator? = nil
    ) {
        self.apiClient = apiClient
        self.hashtag = hashtag
        self.feedCoordinator = feedCoordinator ?? .shared
        // Use provided cache or fall back to shared instance
        self.accountCache = accountCache ?? CacheManager.shared.accountCache

        self.feedCoordinator.updates
            .sink { [weak self] update in
                self?.incorporateUpdate(update)
            }
            .store(in: &cancellables)
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            let newStatuses = try await apiClient.fetchHashtagTimeline(tag: hashtag, maxID: nil, sinceID: nil, limit: 40)
            statuses = newStatuses
            currentMaxID = newStatuses.last?.id
            currentSinceID = newStatuses.first?.id
            loadingState = .idle
            hasMore = newStatuses.count >= 40

            // Cache accounts from loaded statuses
            accountCache.cacheFromStatuses(newStatuses)
        } catch {
            loadingState = .error(error)
        }
    }

    func refresh() async {
        guard case .idle = loadingState else { return }
        loadingState = .refreshing

        do {
            let newStatuses = try await apiClient.fetchHashtagTimeline(
                tag: hashtag,
                maxID: nil,
                sinceID: currentSinceID,
                limit: 40
            )
            if !newStatuses.isEmpty {
                statuses.insert(contentsOf: newStatuses, at: 0)
                currentSinceID = newStatuses.first?.id

                // Cache accounts from new statuses
                accountCache.cacheFromStatuses(newStatuses)
            }
            loadingState = .idle
        } catch {
            loadingState = .error(error)
        }
    }

    func loadMore() async {
        guard hasMore, case .idle = loadingState, let maxID = currentMaxID else { return }
        loadingState = .loadingMore
        loadMoreFailed = false

        do {
            let newStatuses = try await apiClient.fetchHashtagTimeline(
                tag: hashtag,
                maxID: maxID,
                sinceID: nil,
                limit: 40
            )
            if !newStatuses.isEmpty {
                statuses.append(contentsOf: newStatuses)
                currentMaxID = newStatuses.last?.id

                // Cache accounts from new statuses
                accountCache.cacheFromStatuses(newStatuses)
            }
            hasMore = newStatuses.count >= 40
            loadingState = .idle
        } catch {
            // Reset to the ready state (not .error, which is the full-screen initial-load
            // failure) so the inline retry footer's loadMore() can fire again.
            loadingState = .idle
            loadMoreFailed = true
        }
    }

    func votePoll(pollID: String, choices: [Int]) async -> Bool {
        do {
            let updatedPoll = try await apiClient.votePoll(pollID: pollID, choices: choices)

            guard let index = statuses.firstIndex(where: { $0.displayStatus.poll?.id == pollID }) else {
                return false
            }
            statuses[index] = statuses[index].updating(poll: updatedPoll)
            return true
        } catch {
            AppLogger.error("Failed to vote on poll: \(error)")
            return false
        }
    }

    func removeStatus(id: String) {
        statuses.removeAll { $0.id == id }
    }

    // MARK: - FeedCoordinatorUpdatable

    func incorporateUpdate(_ update: UpdatedElement) {
        switch update {
        case .post(let updatedStatus):
            let canonicalUpdate = updatedStatus.displayStatus
            var didUpdate = false
            let mergedStatuses = statuses.map { currentStatus in
                let representsUpdatedPost =
                    currentStatus.id == updatedStatus.id
                    || currentStatus.id == canonicalUpdate.id
                    || currentStatus.displayStatus.id == canonicalUpdate.id
                guard representsUpdatedPost else { return currentStatus }

                didUpdate = true
                return currentStatus.incorporatingDisplayStatusUpdate(canonicalUpdate)
            }

            if didUpdate {
                statuses = mergedStatuses
            }

        case .deletedPost(let deletedID):
            guard statuses.contains(where: {
                $0.id == deletedID || $0.displayStatus.id == deletedID
            }) else { return }
            statuses.removeAll {
                $0.id == deletedID || $0.displayStatus.id == deletedID
            }

        case .createdPost, .hashtag, .relationship:
            break
        }
    }
}
