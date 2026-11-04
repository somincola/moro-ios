import Testing
import UIKit
import SwiftUI
@testable import moro

@Suite(.serialized)
@MainActor
struct SearchControllerTests {
    @Test func avatarPlaybackStopsForSearchEntryNavigationAndResumesForTheVisibleList() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelDiscoveryRequests() }
        controller.loadViewIfNeeded()
        #expect(!controller.playbackScope.isActive)
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        try await waitForDiscovery(controller)
        #expect(controller.playbackScope.allowsAnimatedAvatars)
        #expect(controller.playbackScope.isActive)

        controller.beginSearchEntry()
        #expect(!controller.playbackScope.isActive)
        controller.cancelSearchEntry()
        #expect(controller.playbackScope.isActive)
        controller.scrollViewWillBeginDragging(controller.tableView)
        #expect(controller.playbackScope.isScrolling)
        controller.scrollViewDidEndDragging(controller.tableView, willDecelerate: true)
        #expect(controller.playbackScope.isScrolling)
        controller.scrollViewDidEndDecelerating(controller.tableView)
        #expect(!controller.playbackScope.isScrolling)
        controller.setListContentOffset(controller.tableView.contentOffset, animated: true)
        #expect(!controller.playbackScope.isScrolling, "A no-op tab re-tap must not wait for an animation callback")
        controller.playbackScope.isScrolling = true
        controller.setListContentOffset(controller.tableView.contentOffset, animated: false)
        #expect(!controller.playbackScope.isScrolling, "Restoring an offset also cancels a previous animation")

        controller.prepareForNavigation()
        #expect(!controller.playbackScope.isActive)
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        #expect(controller.playbackScope.isActive)
        controller.stopMediaPlayback()
        #expect(!controller.playbackScope.isActive)
    }

    @Test func focusTypingClearAndKeyboardDismissDoNotSubmit() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelDiscoveryRequests() }
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        try await waitForDiscovery(controller)
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

    @Test func clearThenCancelReturnsToDiscoveryAndCancelsTheSubmittedRequest() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelDiscoveryRequests() }
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        try await waitForDiscovery(controller)
        let accounts = controller.discovery.accounts.map(\.id)
        controller.submitQuery("slow", scope: .accounts)
        _ = controller.searchBarShouldBeginEditing(controller.searchBar)
        controller.searchBar.text = ""
        controller.searchBar(controller.searchBar, textDidChange: "")
        controller.searchBarCancelButtonClicked(controller.searchBar)
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.searchBar.text == "")
        #expect(controller.interaction.page == .discovery)
        #expect(controller.searchState.results.accounts.isEmpty)
        #expect(controller.discovery.accounts.map(\.id) == accounts)
        #expect(!controller.tableView.isHidden)
        #expect(controller.cancelEntryButton.isHidden)
    }

    @Test func defaultAndLegacyAllUseAccountsAndSingleCharacterScopesSubmitImmediately() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        #expect(controller.selectedScope == .accounts)
        #expect(controller.scopeControl.numberOfSegments == 3)
        controller.submitQuery("中", scope: .all)
        try await waitFor { controller.searchState.hasSearchedCurrentQuery }
        #expect(controller.interaction.submittedScope == .accounts)
        #expect(controller.searchState.scope == .accounts)
        SearchFixtureProtocol.resetRequests()
        controller.scopeControl.selectedSegmentIndex = SearchViewModel.Scope.statuses.segmentIndex
        controller.scopeControl.sendActions(for: .valueChanged)
        try await waitFor { !controller.searchState.isLoading && !searchRequests.isEmpty }
        let request = try #require(searchRequests.last)
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "q" })?.value == "中")
        #expect(items?.first(where: { $0.name == "type" })?.value == "statuses")
        #expect(controller.interaction.submittedScope == .statuses)
        #expect(controller.library.recent.count == 1)
    }

    @Test func navigationFocusRestorationDoesNotReplaceTheSourcePage() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        try await waitForDiscovery(controller)
        for page in [SearchInteractionState.Page.discovery, .results] {
            if page == .results {
                controller.submitQuery("Swift", scope: .accounts)
                try await waitFor { controller.searchState.hasSearchedCurrentQuery }
            }
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            var openedAccount = false
            controller.onOpenProfile = { _ in openedAccount = true }
            controller.tableView(controller.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
            #expect(openedAccount)
            #expect(!controller.searchBarShouldBeginEditing(controller.searchBar))
            controller.beginAppearanceTransition(false, animated: false)
            controller.endAppearanceTransition()
            controller.beginAppearanceTransition(true, animated: false)
            #expect(!controller.searchBarShouldBeginEditing(controller.searchBar))
            controller.endAppearanceTransition()
            #expect(controller.interaction.page == page)
            #expect(!controller.tableView.isHidden)
            #expect(controller.searchBarShouldBeginEditing(controller.searchBar))
            #expect(controller.interaction.page == .entry)
            controller.cancelSearchEntry()
        }
    }

    @Test func newSubmissionRejectsLateResultsAndEntryNeverDisplaysTheirList() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
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
        try await waitForDiscovery(controller)
        #expect(controller.interaction.page == .discovery)
        #expect(!controller.discovery.isLoading)
    }

    @Test func postsUseTimelineHostingAndDoNotAlsoSelectTheTableRow() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelDiscoveryRequests() }
        controller.loadViewIfNeeded()
        try await waitForDiscovery(controller)
        controller.scopeControl.selectedSegmentIndex = SearchViewModel.Scope.statuses.segmentIndex
        controller.scopeControl.sendActions(for: .valueChanged)
        let index = IndexPath(row: 0, section: 0)
        #expect(controller.isStatusRow(at: index))
        let cell = controller.tableView(controller.tableView, cellForRowAt: index)
        #expect(cell.reuseIdentifier == "SearchTimelinePostCell")
        #expect(!(cell is SearchResultLineCell))
        #expect(cell.contentConfiguration != nil)
        #expect(!controller.tableView(controller.tableView, shouldHighlightRowAt: index))
        #expect(controller.tableView(controller.tableView, willSelectRowAt: index) == nil)
    }

    @Test func postUpdatesAndDeletionReachDiscoveryResultsAndCachedSearches() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        try await waitForDiscovery(controller)
        controller.submitQuery("Swift", scope: .statuses)
        try await waitFor { controller.searchState.hasSearchedCurrentQuery }
        let status = try #require(controller.searchState.results.statuses.first)
        FeedCoordinator.shared.publishUpdate(.post(status.updating(favouritesCount: 7, bookmarked: true, favourited: true)))
        #expect(controller.discovery.statuses.first?.favouritesCount == 7)
        #expect(controller.searchState.results.statuses.first?.bookmarked == true)
        controller.showDiscovery()
        controller.submitQuery("Swift", scope: .statuses)
        #expect(controller.searchState.results.statuses.first?.favourited == true)
        controller.cancelInFlightSearchRequests()
        FeedCoordinator.shared.publishUpdate(.deletedPost(status.id))
        #expect(controller.discovery.statuses.isEmpty)
        #expect(controller.searchState.results.statuses.isEmpty)
        #expect(controller.sections.isEmpty)
        controller.showDiscovery()
        controller.submitQuery("Swift", scope: .statuses)
        #expect(controller.searchState.results.statuses.isEmpty)
    }

    @Test func pollResponsePreservesAReactionCompletedWhileVoting() async throws {
        let (controller, defaults, suite) = makeController()
        defer { defaults.removePersistentDomain(forName: suite); controller.cancelInFlightSearchRequests() }
        controller.loadViewIfNeeded()
        controller.submitQuery("poll", scope: .statuses)
        try await waitFor { controller.searchState.hasSearchedCurrentQuery }
        let status = try #require(controller.searchState.results.statuses.first)
        let voting = Task { await controller.votePoll(pollID: "fixture-poll", choices: [0]) }
        try await waitFor { SearchFixtureProtocol.requests.contains { $0.url?.path.hasSuffix("/votes") == true } }
        FeedCoordinator.shared.publishUpdate(.post(status.updating(favouritesCount: 8, favourited: true)))
        #expect(await voting.value)
        #expect(controller.searchState.results.statuses.first?.poll?.voted == true)
        #expect(controller.searchState.results.statuses.first?.favourited == true)
        #expect(controller.searchState.results.statuses.first?.favouritesCount == 8)
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

    private func waitForDiscovery(_ controller: SearchCoreViewController) async throws {
        // Cold CI runners can spend several seconds initializing UIKit while other
        // suites share the main actor. Await the request instead of timing setup.
        let task = try #require(controller.discoveryTask)
        await task.value
        try #require(controller.discovery.hasLoaded)
        try #require(controller.discovery.errorMessage == nil)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}
