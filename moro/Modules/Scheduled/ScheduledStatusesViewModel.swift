//
//  ScheduledStatusesViewModel.swift
//  moro
//
//  ViewModel for scheduled statuses list and cancellation.
//

import Combine
import Foundation

@MainActor
final class ScheduledStatusesViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case loadingMore
        case loaded
        case error(Error)
    }

    @Published var items: [ScheduledStatus] = []
    @Published var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false
    @Published private(set) var cancellingIDs: Set<String> = []

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
            let page = try await apiClient.fetchScheduledStatuses(
                maxID: currentMaxID,
                sinceID: nil,
                limit: pageSize
            )
            appendUnique(page)
            currentMaxID = page.last?.id
            hasMore = page.count >= pageSize
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            loadingState = .loaded
            loadMoreFailed = true
        }
    }

    func cancel(_ item: ScheduledStatus) async {
        guard !cancellingIDs.contains(item.id) else { return }
        cancellingIDs.insert(item.id)
        defer { cancellingIDs.remove(item.id) }

        do {
            try await apiClient.cancelScheduledStatus(id: item.id)
            items.removeAll { $0.id == item.id }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ScheduledVM.cancelled)
        } catch {
            transientErrorMessage = MoroL10n.ScheduledVM.cancelFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ScheduledVM.cancelFailedShort)
        }
    }

    func isCancelling(_ id: String) -> Bool {
        cancellingIDs.contains(id)
    }

    private func load(reset: Bool) async {
        do {
            let page = try await apiClient.fetchScheduledStatuses(
                maxID: nil,
                sinceID: nil,
                limit: pageSize
            )
            if reset {
                items = page
            } else {
                appendUnique(page)
            }
            currentMaxID = page.last?.id
            hasMore = page.count >= pageSize
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            loadingState = .error(error)
            transientErrorMessage = MoroL10n.ScheduledVM.loadFailed
        }
    }

    private func appendUnique(_ newItems: [ScheduledStatus]) {
        let existingIDs = Set(items.map(\.id))
        let unique = newItems.filter { !existingIDs.contains($0.id) }
        items.append(contentsOf: unique)
    }
}
