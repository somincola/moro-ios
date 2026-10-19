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
                // Each part loads on its own: servers can switch off trends or the
                // profile directory, and one missing part shouldn't hide the rest.
                async let tagsRequest = capture { try await self.apiClient.fetchTrendingTags(limit: 10) }
                async let statusesRequest = capture { try await self.apiClient.fetchTrendingStatuses(limit: 10) }
                async let accountsRequest = loadDiscoveryAccounts(limit: directoryLimit)
                let (tags, statuses, accounts) = await (tagsRequest, statusesRequest, accountsRequest)
                guard !Task.isCancelled, requestID == discoveryRequestID else { return }

                let failures = [tags.error, statuses.error, accounts.result.error].compactMap { $0 }
                if failures.count == 3, let first = failures.first { throw first }
                fetchedTags = tags.value ?? []
                fetchedStatuses = statuses.value ?? []
                fetchedAccounts = accounts.result.value ?? []
                discovery.accountsArePaged = accounts.paged
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
            discovery.hasMoreAccounts = discovery.accountsArePaged
                && fetchedAccounts.count >= directoryLimit && appendedAccountCount > 0
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

    /// The profile directory, or — where a server has switched it off — the
    /// accounts it suggests following, which come as a single page.
    private func loadDiscoveryAccounts(limit: Int) async -> (result: DiscoveryResult<[Account]>, paged: Bool) {
        let directory = await capture {
            try await self.apiClient.fetchDirectoryAccounts(limit: limit, offset: 0, order: .active, local: nil)
        }
        guard directory.error != nil else { return (directory, true) }
        let suggested = await capture { try await self.apiClient.fetchSuggestedAccounts(limit: min(limit, 40)) }
        return (suggested.error == nil ? suggested : directory, false)
    }

    private func capture<T>(_ work: () async throws -> T) async -> DiscoveryResult<T> {
        do { return DiscoveryResult(value: try await work(), error: nil) }
        catch { return DiscoveryResult(value: nil, error: error) }
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
