//
//  FavouritesViewModel.swift
//  moro
//
//  ViewModel for favourites timeline page.
//

import Foundation
import Combine

@MainActor
final class FavouritesViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case loadingMore
        case loaded
        case error(Error)
    }

    @Published var statuses: [Status] = []
    @Published var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false

    private let apiClient: MastodonAPI
    private let pageSize: Int = 20
    private var currentMaxID: String?
    private var hasMore: Bool = true

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
    }

    func loadInitial() async {
        switch loadingState {
        case .loading, .loadingMore:
            return
        case .idle, .loaded, .error:
            break
        }
        loadingState = .loading
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func loadMore() async {
        guard hasMore, case .loaded = loadingState else { return }

        loadingState = .loadingMore
        loadMoreFailed = false
        do {
            let items = try await apiClient.fetchFavouritedStatuses(
                maxID: currentMaxID,
                sinceID: nil,
                limit: pageSize
            )
            appendUnique(items)
            currentMaxID = items.last?.id
            hasMore = items.count >= pageSize
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            loadingState = .loaded
            loadMoreFailed = true
        }
    }

    func removeFavourite(_ status: Status) async {
        do {
            _ = try await apiClient.unfavouriteStatus(id: status.displayStatus.id)
            statuses.removeAll { $0.id == status.id }
            AppFeedbackCenter.shared.showSuccess(MoroL10n.FavouritesVM.unfavourited)
            transientErrorMessage = nil
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.FavouritesVM.unfavouriteFailed)
            transientErrorMessage = MoroL10n.FavouritesVM.unfavouriteFailedDetail
        }
    }

    private func load(reset: Bool) async {
        do {
            let items = try await apiClient.fetchFavouritedStatuses(
                maxID: nil,
                sinceID: nil,
                limit: pageSize
            )

            if reset {
                statuses = items
            } else {
                appendUnique(items)
            }
            currentMaxID = items.last?.id
            hasMore = items.count >= pageSize
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            loadingState = .error(error)
            transientErrorMessage = MoroL10n.FavouritesVM.loadFailed
        }
    }

    private func appendUnique(_ newItems: [Status]) {
        let existingIDs = Set(statuses.map(\.id))
        let unique = newItems.filter { !existingIDs.contains($0.id) }
        statuses.append(contentsOf: unique)
    }
}
