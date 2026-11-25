//
//  RootTabCoordinatorTests.swift
//  moroTests
//


import SwiftUI
import XCTest

@testable import moro

@MainActor
final class RootTabCoordinatorTests: XCTestCase {
    func testTabsOwnIndependentRouters() async {
        let coordinator = RootTabCoordinator()

        XCTAssertEqual(coordinator.tabLayout.tabs, [.home, .explore, .inbox, .me])
        XCTAssertTrue(coordinator.router(for: .home) === coordinator.homeRouter)
        XCTAssertTrue(coordinator.router(for: .explore) === coordinator.exploreRouter)
        XCTAssertTrue(coordinator.router(for: .inbox) === coordinator.inboxRouter)
        XCTAssertTrue(coordinator.router(for: .me) === coordinator.meRouter)
    }

    func testTabLayoutKeepsRequiredTabsAndAppendsReaddedTabs() {
        let coordinator = RootTabCoordinator()
        coordinator.toggleTab(.bookmarks)
        coordinator.toggleTab(.favourites)
        for tab in NavigationTabLayout.requiredTabs { coordinator.toggleTab(tab) }
        XCTAssertEqual(coordinator.tabLayout.tabs, [.home, .explore, .inbox, .me, .bookmarks])

        coordinator.toggleTab(.explore)
        coordinator.toggleTab(.explore)
        coordinator.moveTab(.me, to: 0)
        XCTAssertEqual(coordinator.tabLayout.tabs, [.me, .home, .inbox, .bookmarks, .explore])
        coordinator.restoreDefaultTabLayout()
        XCTAssertEqual(coordinator.tabLayout.tabs, NavigationTabLayout.defaultTabs)
    }

    func testTabLayoutRepairsIncompleteOrOversizedSavedOrder() {
        let layout = NavigationTabLayout(tabs: [.favourites, .favourites, .lists, .explore, .inbox, .settings])
        XCTAssertEqual(layout.tabs, [.favourites, .lists, .explore, .inbox, .home])
        XCTAssertEqual(NavigationTabLayout(tabs: [.home, .home]).tabs, [.home, .explore])
        XCTAssertEqual(NavigationTabLayout(tabs: [.lists]).tabs, [.lists, .home])
        XCTAssertEqual(NavigationTabLayout(tabs: []).tabs, NavigationTabLayout.defaultTabs)
    }

    func testInboxAndProfileCanBeRemovedDownToTwoTabsAndReaddedAtTheEnd() {
        let coordinator = RootTabCoordinator(selectedTab: .me)
        coordinator.toggleTab(.me)
        XCTAssertEqual(coordinator.selectedTab, .home)
        coordinator.toggleTab(.inbox)
        XCTAssertFalse(coordinator.tabLayout.canToggle(.explore))
        coordinator.toggleTab(.explore)
        coordinator.toggleTab(.home)
        XCTAssertEqual(coordinator.tabLayout.tabs, [.home, .explore])
        coordinator.toggleTab(.lists)
        coordinator.toggleTab(.explore)
        coordinator.toggleTab(.me)
        coordinator.toggleTab(.inbox)
        XCTAssertEqual(coordinator.tabLayout.tabs, [.home, .lists, .me, .inbox])
    }

    func testDeepLinksToHiddenProfileAndInboxUseHomeWithoutChangingTheLayout() {
        let coordinator = RootTabCoordinator(selectedTab: .explore)
        coordinator.toggleTab(.inbox)
        coordinator.toggleTab(.me)
        let account = Account(id: "viewer", username: "viewer", acct: "viewer", displayName: "Viewer",
                              note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
                              followersCount: 0, followingCount: 0, statusesCount: 0)
        coordinator.openProfile(account)
        var expected = NavigationPath([Route.userProfile(account)])
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(coordinator.homeRouter.path, expected)

        coordinator.openPushNotification(.notifications)
        expected.append(Route.inbox)
        XCTAssertTrue(coordinator.isInboxVisible)
        XCTAssertEqual(coordinator.homeRouter.path, expected)
        coordinator.openPushNotification(.profile(account))
        expected.append(Route.userProfile(account))
        XCTAssertFalse(coordinator.isInboxVisible)
        XCTAssertEqual(coordinator.homeRouter.path, expected)
        XCTAssertTrue(coordinator.inboxRouter.path.isEmpty)
        XCTAssertEqual(coordinator.tabLayout.tabs, [.home, .explore])
    }

    func testRemovingActiveTabKeepsItsRouterAndLeavesEditorOpen() {
        let coordinator = RootTabCoordinator()
        coordinator.toggleTab(.settings)
        coordinator.selectTab(.settings)
        let router = coordinator.router(for: .settings)
        router.navigate(to: .bookmarks)
        coordinator.presentNavigationCustomization()

        coordinator.toggleTab(.settings)
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(coordinator.presentedSheet, .navigationCustomization)
        coordinator.selectTab(.settings)
        XCTAssertEqual(coordinator.selectedTab, .home)

        coordinator.toggleTab(.settings)
        XCTAssertTrue(coordinator.router(for: .settings) === router)
        XCTAssertEqual(router.path.count, 1)
    }

    func testWidgetSearchPresentsSheetWithoutDisturbingStacksWhenExploreIsHidden() {
        let coordinator = RootTabCoordinator(selectedTab: .me)
        coordinator.homeRouter.navigate(to: .bookmarks)
        coordinator.toggleTab(.explore)

        coordinator.openExplore()

        XCTAssertEqual(coordinator.selectedTab, .me)
        XCTAssertEqual(coordinator.homeRouter.path.count, 1)
        XCTAssertEqual(coordinator.presentedSheet, .search(autoFocus: false))
        XCTAssertTrue(coordinator.exploreRouter.path.isEmpty)
    }

    func testSearchEntryHidesOnlyTheExploreTabBar() {
        let coordinator = RootTabCoordinator(selectedTab: .explore)
        XCTAssertFalse(coordinator.isTabBarHidden)
        coordinator.setExploreSearchEntryActive(true)
        XCTAssertTrue(coordinator.isTabBarHidden)

        for tab in [MainTab.home, .inbox, .me] {
            coordinator.selectTab(tab)
            XCTAssertFalse(coordinator.isTabBarHidden)
        }
        coordinator.selectTab(.explore)
        XCTAssertTrue(coordinator.isTabBarHidden)
        coordinator.setExploreSearchEntryActive(false)
        XCTAssertFalse(coordinator.isTabBarHidden)
    }

    func testLeavingSearchEntryDoesNotRevealTabBarOnDetailRoutes() {
        let coordinator = RootTabCoordinator(selectedTab: .explore)
        coordinator.setExploreSearchEntryActive(true)
        coordinator.setIsAtRoot(false, for: .explore)
        coordinator.setExploreSearchEntryActive(false)
        XCTAssertTrue(coordinator.isTabBarHidden)
        coordinator.setIsAtRoot(true, for: .explore)
        XCTAssertFalse(coordinator.isTabBarHidden)
    }

    func testComposePresentationKeepsOriginTabSelected() async {
        let coordinator = RootTabCoordinator(selectedTab: .explore)

        coordinator.openCompose()

        XCTAssertEqual(coordinator.selectedTab, .explore)
        XCTAssertNotNil(coordinator.composeContext)
    }

    func testSettingsSheetPreservesSourceTabAndRouteStack() async {
        let coordinator = RootTabCoordinator(selectedTab: .me)
        coordinator.meRouter.navigate(to: .bookmarks)

        coordinator.presentSettings()

        XCTAssertEqual(coordinator.presentedSheet, .settings)
        XCTAssertEqual(coordinator.selectedTab, .me)
        XCTAssertEqual(coordinator.meRouter.path.count, 1)
    }

    func testOpeningComposeDismissesSettingsSheet() async {
        let coordinator = RootTabCoordinator(presentedSheet: .settings)

        coordinator.openCompose()

        XCTAssertNil(coordinator.presentedSheet)
        XCTAssertNotNil(coordinator.composeContext)
    }

    func testSwitchingTabsPreservesIndependentRoutePaths() async {
        let coordinator = RootTabCoordinator()
        coordinator.homeRouter.navigate(to: .bookmarks)
        coordinator.setIsAtRoot(false, for: .home)

        coordinator.selectTab(.explore)
        coordinator.exploreRouter.navigate(to: .search(query: "moro"))
        coordinator.setIsAtRoot(false, for: .explore)

        XCTAssertEqual(coordinator.homeRouter.path.count, 1)
        XCTAssertEqual(coordinator.exploreRouter.path.count, 1)
        XCTAssertEqual(coordinator.selectedTab, .explore)
    }

    func testRetappingPushedTabPopsOnlyThatTabToRoot() async {
        let coordinator = RootTabCoordinator(selectedTab: .inbox)
        coordinator.inboxRouter.navigate(to: .favourites)
        coordinator.homeRouter.navigate(to: .bookmarks)
        coordinator.setIsAtRoot(false, for: .inbox)
        coordinator.setIsAtRoot(false, for: .home)

        coordinator.selectTab(.inbox)

        XCTAssertTrue(coordinator.inboxRouter.path.isEmpty)
        XCTAssertEqual(coordinator.homeRouter.path.count, 1)
    }

    func testInboxSelectionPersistsAcrossTabSwitches() async {
        let coordinator = RootTabCoordinator()

        coordinator.openInbox(.mentions)
        coordinator.selectTab(.me)
        coordinator.selectTab(.inbox)

        XCTAssertEqual(coordinator.inboxFilter, .mentions)
        XCTAssertEqual(coordinator.selectedTab, .inbox)
    }

    func testExternalConversationOpenReturnsToMentionsAndReplacesInboxPath() async {
        let coordinator = RootTabCoordinator(selectedTab: .home)
        let conversation = Conversation(
            id: "conversation-1",
            unread: true,
            accounts: [],
            lastStatus: nil
        )
        coordinator.inboxRouter.navigate(to: .scheduledStatuses)

        coordinator.openConversation(conversation)
        coordinator.openConversation(conversation)

        XCTAssertEqual(coordinator.selectedTab, .inbox)
        XCTAssertEqual(coordinator.inboxFilter, .mentions)
        XCTAssertEqual(coordinator.inboxRouter.path.count, 1)
        XCTAssertTrue(coordinator.homeRouter.path.isEmpty)
    }

    func testMessagePushFallbackOpensMentionsWithoutTheRemovedMessagesSection() {
        let coordinator = RootTabCoordinator()
        coordinator.inboxRouter.navigate(to: .bookmarks)

        coordinator.openPushNotification(.messages)

        XCTAssertEqual(coordinator.selectedTab, .inbox)
        XCTAssertEqual(coordinator.inboxFilter, .mentions)
        XCTAssertTrue(coordinator.inboxRouter.path.isEmpty)
    }
}
