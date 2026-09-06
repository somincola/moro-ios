import Foundation

/// Draft input never mutates the committed request or its results.
struct SearchInteractionState {
    enum Page: Equatable { case discovery, entry, results }

    private(set) var page: Page = .discovery
    private(set) var submittedQuery = ""
    private(set) var submittedScope: SearchViewModel.Scope = .accounts
    var draftQuery = ""

    mutating func beginEntry() {
        guard page != .entry else { return }
        draftQuery = submittedQuery
        page = .entry
    }

    mutating func cancelEntry() {
        guard page == .entry else { return }
        showDiscovery()
    }

    @discardableResult
    mutating func submit(_ query: String, scope: SearchViewModel.Scope) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        submittedQuery = trimmed
        submittedScope = scope.exploreScope
        draftQuery = trimmed
        page = .results
        return true
    }

    mutating func showDiscovery() {
        self = SearchInteractionState()
    }
}
