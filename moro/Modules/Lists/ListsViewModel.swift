//
//  ListsViewModel.swift
//  moro
//
//  ViewModel for lists management and list timeline loading.
//

import Foundation
import Combine

@MainActor
final class ListsViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    @Published private(set) var lists: [MastodonList] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?
    @Published var isMutating: Bool = false

    private let apiClient: MastodonAPI

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading
        await refresh()
    }

    func refresh() async {
        do {
            lists = try await apiClient.fetchLists()
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            if lists.isEmpty {
                loadingState = .error(error)
            } else {
                loadingState = .loaded
            }
            transientErrorMessage = MoroL10n.ListsVM.loadFailed
        }
    }

    func createList(title: String, repliesPolicy: MastodonList.RepliesPolicy?) async -> Bool {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return false }
        guard !isMutating else { return false }

        isMutating = true
        defer { isMutating = false }

        do {
            let created = try await apiClient.createList(title: cleanedTitle, repliesPolicy: repliesPolicy)
            lists.insert(created, at: 0)
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ListsVM.created)
            return true
        } catch {
            transientErrorMessage = MoroL10n.ListsVM.createFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ListsVM.createFailedShort)
            return false
        }
    }

    func updateList(_ list: MastodonList, title: String, repliesPolicy: MastodonList.RepliesPolicy?) async -> Bool {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return false }
        guard !isMutating else { return false }

        isMutating = true
        defer { isMutating = false }

        do {
            let updated = try await apiClient.updateList(
                id: list.id,
                title: cleanedTitle,
                repliesPolicy: repliesPolicy
            )
            if let index = lists.firstIndex(where: { $0.id == list.id }) {
                lists[index] = updated
            } else {
                lists.insert(updated, at: 0)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ListsVM.updated)
            return true
        } catch {
            transientErrorMessage = MoroL10n.ListsVM.updateFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ListsVM.updateFailedShort)
            return false
        }
    }

    @discardableResult
    func deleteList(_ list: MastodonList) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }

        do {
            try await apiClient.deleteList(id: list.id)
            lists.removeAll { $0.id == list.id }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.ListsVM.deleted)
            return true
        } catch {
            transientErrorMessage = MoroL10n.ListsVM.deleteFailed
            AppFeedbackCenter.shared.showError(MoroL10n.ListsVM.deleteFailedShort)
            return false
        }
    }
}

@MainActor
final class ListTimelineViewModel: ObservableObject {
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
    private let listID: String
    private let pageSize: Int = 20
    private var currentMaxID: String?
    private var hasMore: Bool = true

    init(apiClient: MastodonAPI, listID: String) {
        self.apiClient = apiClient
        self.listID = listID
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
            let items = try await apiClient.fetchListTimeline(
                id: listID,
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

    private func load(reset: Bool) async {
        do {
            let items = try await apiClient.fetchListTimeline(
                id: listID,
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
            transientErrorMessage = MoroL10n.ListsVM.timelineLoadFailed
        }
    }

    private func appendUnique(_ newItems: [Status]) {
        let existingIDs = Set(statuses.map(\.id))
        let unique = newItems.filter { !existingIDs.contains($0.id) }
        statuses.append(contentsOf: unique)
    }
}
