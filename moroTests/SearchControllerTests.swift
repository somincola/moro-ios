import Testing
import UIKit
@testable import moro

@Suite(.serialized)
@MainActor
struct SearchControllerTests {
    @Test func focusTypingClearAndKeyboardDismissDoNotSubmit() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelDiscoveryRequests() }
        controller.loadViewIfNeeded()
        try await waitFor { controller.discovery.hasLoaded }
        SearchFixtureProtocol.resetRequests()

        _ = controller.searchBarShouldBeginEditing(controller.searchBar)
        controller.searchBar.text = "Swift"
        controller.searchBar(controller.searchBar, textDidChange: "Swift")
        try await Task.sleep(for: .milliseconds(350))
        #expect(searchRequests.isEmpty)
        #expect(controller.interaction.page == .entry)
        #expect(controller.tableView.isHidden)
        #expect(controller.scopeControl.isHidden)
        #expect(controller.library.recent.isEmpty)

        controller.searchBar.text = ""
        controller.searchBar(controller.searchBar, textDidChange: "")
        controller.searchBarTextDidEndEditing(controller.searchBar)
        #expect(controller.cancelEntryButton.isEnabled)
        #expect(!controller.cancelEntryButton.isHidden)
        #expect(controller.interaction.page == .entry)
        controller.searchBarCancelButtonClicked(controller.searchBar)
        #expect(controller.interaction.page == .discovery)
        #expect(!controller.tableView.isHidden)
        #expect(searchRequests.isEmpty)
    }

    @Test func cancelRestoresResultsAndSingleCharacterScopesSubmitImmediately() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        controller.submitQuery("中", scope: .all)
        try await waitFor { controller.searchState.hasSearchedCurrentQuery }
        let accounts = controller.searchState.results.accounts.map(\.id)
        SearchFixtureProtocol.resetRequests()

        _ = controller.searchBarShouldBeginEditing(controller.searchBar)
        controller.searchBar.text = "different"
        controller.searchBar(controller.searchBar, textDidChange: "different")
        controller.searchBarCancelButtonClicked(controller.searchBar)
        #expect(controller.searchBar.text == "中")
        #expect(controller.interaction.page == .results)
        #expect(controller.searchState.results.accounts.map(\.id) == accounts)
        #expect(searchRequests.isEmpty)

        controller.scopeControl.selectedSegmentIndex = SearchViewModel.Scope.statuses.rawValue
        controller.scopeControl.sendActions(for: .valueChanged)
        try await waitFor { !controller.searchState.isLoading && !searchRequests.isEmpty }
        let request = try #require(searchRequests.last)
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "q" })?.value == "中")
        #expect(items?.first(where: { $0.name == "type" })?.value == "statuses")
        #expect(controller.interaction.submittedScope == .statuses)
        #expect(controller.library.recent.count == 1)
    }

    @Test func newSubmissionRejectsLateResultsAndEntryNeverDisplaysTheirList() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        controller.submitQuery("slow", scope: .accounts)
        _ = controller.searchBarShouldBeginEditing(controller.searchBar)
        controller.searchBar(controller.searchBar, textDidChange: "fast")
        #expect(controller.tableView.isHidden)
        controller.submitQuery("fast", scope: .accounts)
        try await waitFor { !controller.searchState.isLoading }
        try await Task.sleep(for: .milliseconds(300))
        #expect(controller.searchState.results.accounts.first?.displayName == "Result fast")
        #expect(controller.interaction.submittedQuery == "fast")
        #expect(controller.library.recent.map(\.query) == ["fast", "slow"])
    }

    @Test func errorsAndEmptyResponsesRemainSubmittedResultsPages() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        controller.submitQuery("empty", scope: .all)
        try await waitFor { !controller.searchState.isLoading }
        #expect(controller.mode == .empty)
        #expect(controller.interaction.page == .results)
        controller.submitQuery("error", scope: .all)
        try await waitFor { !controller.searchState.isLoading }
        if case .error = controller.mode {} else { Issue.record("Expected search error page") }
        #expect(controller.interaction.page == .results)
        controller.showDiscovery()
        try await waitFor { controller.discovery.hasLoaded }
        #expect(controller.interaction.page == .discovery)
        #expect(!controller.discovery.isLoading)
    }

    private var searchRequests: [URLRequest] {
        SearchFixtureProtocol.requests.filter { $0.url?.path.hasSuffix("/search") == true }
    }

    private func makeController() -> (SearchCoreViewController, UserDefaults, String) {
        let suite = "search-controller-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let library = SearchLibraryStore(accountKey: "a", defaults: defaults)
        let controller = SearchCoreViewController(apiClient: SearchFixtureProtocol.makeClient(), initialQuery: nil, theme: MoroTheme(), library: library)
        return (controller, defaults, suite)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}
