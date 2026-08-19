//
//  FiltersSettingsViewModel.swift
//  moro
//
//  ViewModel for server-side content filters management.
//

import Combine
import Foundation

@MainActor
final class FiltersSettingsViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    @Published private(set) var filters: [ServerFilter] = []
    @Published private(set) var domainBlocks: [String] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?

    private let apiClient: MastodonAPI

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        await load(showLoading: true)
    }

    func refresh() async {
        await load(showLoading: filters.isEmpty)
    }

    func createFilter(
        title: String,
        keyword: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async -> Bool {
        do {
            let validContexts = contexts.filter { $0 != .unknown }
            let created = try await apiClient.createFilter(
                title: title,
                keyword: keyword,
                contexts: validContexts,
                action: action
            )
            filters.insert(created, at: 0)
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastCreated)
            return true
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastCreateFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastCreateFailedShort)
            return false
        }
    }

    func addKeyword(
        filterID: String,
        keyword: String,
        wholeWord: Bool
    ) async -> ServerFilter.Keyword? {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return nil }

        do {
            let created = try await apiClient.addFilterKeyword(
                filterID: filterID,
                keyword: trimmedKeyword,
                wholeWord: wholeWord
            )
            if let filterIndex = filters.firstIndex(where: { $0.id == filterID }) {
                let filter = filters[filterIndex]
                let updatedKeywords = filter.keywords + [created]
                filters[filterIndex] = filter.with(keywords: updatedKeywords)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastKeywordAdded)
            return created
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastKeywordAddFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastKeywordAddFailedShort)
            return nil
        }
    }

    func updateKeyword(
        filterID: String,
        keywordID: String,
        keyword: String,
        wholeWord: Bool
    ) async -> ServerFilter.Keyword? {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return nil }

        do {
            let updated = try await apiClient.updateFilterKeyword(
                keywordID: keywordID,
                keyword: trimmedKeyword,
                wholeWord: wholeWord
            )

            if let filterIndex = filters.firstIndex(where: { $0.id == filterID }) {
                var updatedKeywords = filters[filterIndex].keywords
                if let keywordIndex = updatedKeywords.firstIndex(where: { $0.id == keywordID }) {
                    updatedKeywords[keywordIndex] = updated
                }
                filters[filterIndex] = filters[filterIndex].with(keywords: updatedKeywords)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastKeywordUpdated)
            return updated
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastKeywordUpdateFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastKeywordUpdateFailedShort)
            return nil
        }
    }

    func deleteKeyword(
        filterID: String,
        keywordID: String
    ) async -> Bool {
        do {
            try await apiClient.deleteFilterKeyword(keywordID: keywordID)
            if let filterIndex = filters.firstIndex(where: { $0.id == filterID }) {
                let filter = filters[filterIndex]
                let updatedKeywords = filter.keywords.filter { $0.id != keywordID }
                filters[filterIndex] = filter.with(keywords: updatedKeywords)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastKeywordDeleted)
            return true
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastKeywordDeleteFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastKeywordDeleteFailedShort)
            return false
        }
    }

    func updateFilter(
        id: String,
        title: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async -> Bool {
        do {
            let validContexts = contexts.filter { $0 != .unknown }
            let updated = try await apiClient.updateFilter(
                id: id,
                title: title,
                contexts: validContexts,
                action: action
            )
            if let index = filters.firstIndex(where: { $0.id == id }) {
                filters[index] = updated
            } else {
                filters.insert(updated, at: 0)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastUpdated)
            return true
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastUpdateFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastUpdateFailedShort)
            return false
        }
    }

    func deleteFilter(_ filter: ServerFilter) async {
        do {
            try await apiClient.deleteFilter(id: filter.id)
            filters.removeAll { $0.id == filter.id }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastDeleted)
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastDeleteFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastDeleteFailedShort)
        }
    }

    func blockDomain(_ domain: String) async -> Bool {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return false }

        do {
            try await apiClient.blockDomain(normalized)
            if !domainBlocks.contains(normalized) {
                domainBlocks.insert(normalized, at: 0)
            }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastDomainBlocked)
            return true
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastDomainBlockFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastDomainBlockFailedShort)
            return false
        }
    }

    func unblockDomain(_ domain: String) async {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return }

        do {
            try await apiClient.unblockDomain(normalized)
            domainBlocks.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.Filters.toastDomainUnblocked)
        } catch {
            transientErrorMessage = MoroL10n.Filters.toastDomainUnblockFailed
            AppFeedbackCenter.shared.showError(MoroL10n.Filters.toastDomainUnblockFailedShort)
        }
    }

    private func load(showLoading: Bool) async {
        if showLoading {
            loadingState = .loading
        }

        do {
            async let fetchedFilters = apiClient.fetchFilters()
            async let fetchedDomainBlocks = apiClient.fetchDomainBlocks(
                maxID: nil,
                sinceID: nil,
                limit: 200
            )
            filters = try await fetchedFilters
            domainBlocks = try await fetchedDomainBlocks.sorted()
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            if filters.isEmpty {
                loadingState = .error(error)
            } else {
                loadingState = .loaded
            }
            transientErrorMessage = MoroL10n.Filters.toastLoadFailed
        }
    }

    private func normalizeDomain(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .lowercased()
    }
}

private extension ServerFilter {
    func with(keywords: [Keyword]) -> ServerFilter {
        ServerFilter(
            id: id,
            title: title,
            context: context,
            expiresAt: expiresAt,
            filterAction: filterAction,
            keywords: keywords
        )
    }
}
