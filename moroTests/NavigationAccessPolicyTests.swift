//
//  NavigationAccessPolicyTests.swift
//  moroTests
//
//  Verifies TabBar-synchronized deduplication and zero-orphan reachability across all layouts.
//

import Testing
@testable import moro

@Suite("NavigationAccessPolicyTests")
struct NavigationAccessPolicyTests {
    @Test func defaultFourTabLayoutDeduplicatesPinnedTabsAndLeavesHomeTrailingClean() {
        let policy = NavigationAccessPolicy(tabLayout: NavigationTabLayout())

        #expect(policy.drawerOverflowTabs == [.lists, .bookmarks, .favourites])
        #expect(policy.showsDrawerSettingsFooter == true)
        #expect(policy.showsProfileSettingsButton == true)
        #expect(policy.showsTimelineSwitcherListsShortcut == true)
        #expect(policy.homeTrailingAction == .none)
        #expect(policy.showsDrawerAvatarBadge == false)
    }

    @Test func pinningSettingsRemovesBothDrawerAndProfileSettingsEntries() {
        let layout = NavigationTabLayout(tabs: [.home, .explore, .inbox, .me, .settings])
        let policy = NavigationAccessPolicy(tabLayout: layout)

        #expect(policy.showsDrawerSettingsFooter == false)
        #expect(policy.showsProfileSettingsButton == false)
        #expect(!policy.drawerOverflowTabs.contains(.settings))
    }

    @Test func pinningListsBookmarksFavouritesRemovesThemFromDrawerAndSwitcher() {
        let layout = NavigationTabLayout(tabs: [.home, .lists, .bookmarks, .favourites, .settings])
        let policy = NavigationAccessPolicy(tabLayout: layout, unreadInboxCount: 3)

        #expect(policy.drawerOverflowTabs == [.me, .explore, .inbox])
        #expect(policy.showsTimelineSwitcherListsShortcut == false)
        #expect(policy.showsDrawerSettingsFooter == false)
        #expect(policy.showsProfileSettingsButton == false)
        #expect(policy.homeTrailingAction == .search)
        #expect(policy.showsDrawerAvatarBadge == true)
    }

    @Test func homeTrailingPrioritizesUnreadAnnouncementsOverHiddenExploreSearch() {
        let hiddenExplore = NavigationTabLayout(tabs: [.home, .inbox, .me])

        let noAnnouncements = NavigationAccessPolicy(
            tabLayout: hiddenExplore,
            unreadInboxCount: 0,
            unreadAnnouncementsCount: 0
        )
        #expect(noAnnouncements.homeTrailingAction == .search)

        let withAnnouncements = NavigationAccessPolicy(
            tabLayout: hiddenExplore,
            unreadInboxCount: 0,
            unreadAnnouncementsCount: 2
        )
        #expect(withAnnouncements.homeTrailingAction == .announcements(unreadCount: 2))
    }

    @Test func minimalTwoTabLayoutKeepsEveryDestinationReachableWithoutOrphans() {
        // Extreme 2-tab layout: only Home + Lists pinned.
        let layout = NavigationTabLayout(tabs: [.home, .lists])
        let policy = NavigationAccessPolicy(tabLayout: layout, unreadInboxCount: 5)

        let allReachable = Set(layout.tabs)
            .union(policy.drawerOverflowTabs)
            .union(policy.showsDrawerSettingsFooter ? [MainTab.settings] : [])

        #expect(allReachable == Set(MainTab.allCases))
        #expect(policy.showsDrawerAvatarBadge == true)
        #expect(policy.homeTrailingAction == .search)
    }

    @MainActor
    @Test func openExploreUsesSheetWithAutoFocusOptionWhenExploreIsHiddenFromTabBar() {
        let coordinator = RootTabCoordinator()
        coordinator.toggleTab(.explore)
        #expect(!coordinator.tabLayout.tabs.contains(.explore))

        coordinator.openDrawer()
        #expect(coordinator.isDrawerPresented == true)

        coordinator.openExplore(autoFocus: true)
        #expect(coordinator.isDrawerPresented == false)
        #expect(coordinator.presentedSheet == .search(autoFocus: true))

        coordinator.dismissPresentedSheet()
        coordinator.openExplore(autoFocus: false)
        #expect(coordinator.presentedSheet == .search(autoFocus: false))
    }
}
