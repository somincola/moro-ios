//
//  SearchCoreViewController+Discovery.swift
//  moro
//
//  Discovery loading, pagination, merging, and cancellation.
//

#if os(iOS)
import UIKit

@MainActor
extension SearchCoreViewController {
    func loadDiscoveryIfNeeded(forceRefresh: Bool = false) {
        guard trimmedQuery.isEmpty else {
            endRefreshingIfNeeded()
            return
        }

        if forceRefresh {
            loadDiscovery(resetAccounts: true, forceRefresh: true)
            return
        }

        if discovery.hasLoaded || discovery.isLoading || discovery.isLoadingMoreAccounts {
            endRefreshingIfNeeded()
            refreshViewState()
            return
        }

        loadDiscovery(resetAccounts: true, forceRefresh: false)
    }

    func loadDiscovery(resetAccounts: Bool, forceRefresh: Bool = false) {
        guard trimmedQuery.isEmpty else { return }

        if resetAccounts {
            guard !discovery.isLoading else { return }
        } else {
            guard discovery.hasMoreAccounts else { return }
            guard !discovery.isLoading, !discovery.isLoadingMoreAccounts else { return }
        }

        cancelInFlightSearchRequests()

        if resetAccounts {
            discovery.isLoading = true
            discovery.errorMessage = nil
        } else {
            discovery.isLoadingMoreAccounts = true
        }

        if forceRefresh {
            refreshControl.beginRefreshing()
        }
        refreshViewState()

        cancelDiscoveryRequests(resetActiveRequestID: false)
        let requestID = UUID()
        discoveryRequestID = requestID
        let directoryLimit = resetAccounts ? initialPageSize : paginationPageSize
        let directoryOffset = resetAccounts ? 0 : discovery.nextAccountOffset

        discoveryTask = Task { [weak self] in
            await self?.performDiscoveryRequest(
                directoryLimit: directoryLimit,
                directoryOffset: directoryOffset,
                resetAccounts: resetAccounts,
                requestID: requestID
            )
        }
    }

    private func performDiscoveryRequest(
        directoryLimit: Int,
        directoryOffset: Int,
        resetAccounts: Bool,
        requestID: UUID
    ) async {
        do {
            let fetchedStatuses: [Status]
            let fetchedTags: [SearchTag]
            let fetchedAccounts: [Account]

            if resetAccounts {
                async let tagsRequest = apiClient.fetchTrendingTags(limit: 10)
                async let statusesRequest = apiClient.fetchTrendingStatuses(limit: 10)
                async let accountsRequest = apiClient.fetchDirectoryAccounts(
                    limit: directoryLimit,
                    offset: 0,
                    order: .active,
                    local: nil
                )
                (fetchedTags, fetchedStatuses, fetchedAccounts) = try await (
                    tagsRequest,
                    statusesRequest,
                    accountsRequest
                )
            } else {
                fetchedTags = discovery.hashtags
                fetchedStatuses = discovery.statuses
                fetchedAccounts = try await apiClient.fetchDirectoryAccounts(
                    limit: directoryLimit,
                    offset: directoryOffset,
                    order: .active,
                    local: nil
                )
            }

            SearchStatusPreviewCache.shared.prewarm(statuses: fetchedStatuses)
            guard !Task.isCancelled, requestID == discoveryRequestID else { return }

            if resetAccounts {
                discovery.statuses = mergeStatuses([], fetchedStatuses)
                discovery.hashtags = mergeTags([], fetchedTags)
            }

            let existingAccountCount = resetAccounts ? 0 : discovery.accounts.count
            let mergedAccounts = resetAccounts
                ? mergeAccounts([], fetchedAccounts)
                : mergeAccounts(discovery.accounts, fetchedAccounts)
            let appendedAccountCount = max(mergedAccounts.count - existingAccountCount, 0)

            discovery.accounts = mergedAccounts
            discovery.nextAccountOffset = mergedAccounts.count
            discovery.hasMoreAccounts = fetchedAccounts.count >= directoryLimit && appendedAccountCount > 0
            discovery.errorMessage = nil
            discovery.hasLoaded = true
        } catch {
            guard !Task.isCancelled, requestID == discoveryRequestID else { return }
            if resetAccounts && !hasAnyDiscoveryContent {
                discovery.errorMessage = error.localizedDescription
            }
            discovery.hasLoaded = true
        }

        if resetAccounts {
            discovery.isLoading = false
        } else {
            discovery.isLoadingMoreAccounts = false
        }

        endRefreshingIfNeeded()
        refreshViewState()
    }

    private func mergeAccounts(_ existing: [Account], _ incoming: [Account]) -> [Account] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for account in incoming where !seen.contains(account.id) {
            merged.append(account)
            seen.insert(account.id)
        }
        return merged
    }

    private func mergeStatuses(_ existing: [Status], _ incoming: [Status]) -> [Status] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for status in incoming where !seen.contains(status.id) {
            merged.append(status)
            seen.insert(status.id)
        }
        return merged
    }

    private func mergeTags(_ existing: [SearchTag], _ incoming: [SearchTag]) -> [SearchTag] {
        var seen = Set(existing.map { $0.name.lowercased() })
        var merged = existing
        for tag in incoming {
            let key = tag.name.lowercased()
            guard !seen.contains(key) else { continue }
            merged.append(tag)
            seen.insert(key)
        }
        return merged
    }
    func cancelDiscoveryRequests(resetActiveRequestID: Bool = true) {
        discoveryTask?.cancel()
        if resetActiveRequestID {
            discoveryRequestID = UUID()
            discovery.isLoading = false
            discovery.isLoadingMoreAccounts = false
        }
    }
}
#endif
