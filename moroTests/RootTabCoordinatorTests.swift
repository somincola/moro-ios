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

        XCTAssertEqual(MainTab.allCases, [.home, .explore, .inbox, .me])
        XCTAssertTrue(coordinator.router(for: .home) === coordinator.homeRouter)
        XCTAssertTrue(coordinator.router(for: .explore) === coordinator.exploreRouter)
        XCTAssertTrue(coordinator.router(for: .inbox) === coordinator.inboxRouter)
        XCTAssertTrue(coordinator.router(for: .me) === coordinator.meRouter)
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

        coordinator.openInbox(.messages)
        coordinator.selectTab(.me)
        coordinator.selectTab(.inbox)

        XCTAssertEqual(coordinator.inboxSection, .messages)
        XCTAssertEqual(coordinator.selectedTab, .inbox)
    }

    func testExternalConversationOpenSelectsMessagesAndReplacesInboxPath() async {
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
        XCTAssertEqual(coordinator.inboxSection, .messages)
        XCTAssertEqual(coordinator.inboxRouter.path.count, 1)
        XCTAssertTrue(coordinator.homeRouter.path.isEmpty)
    }
}
