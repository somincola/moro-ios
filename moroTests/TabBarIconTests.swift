//
//  TabBarIconTests.swift
//  moroTests
//


import SwiftUI
import UIKit
import XCTest

@testable import moro

final class TabBarIconTests: XCTestCase {
    @MainActor
    func testTabItemsHaveNoVisibleTitleAndKeepAccessibleNamesOnBothIcons() throws {
        let coordinator = RootTabCoordinator()
        coordinator.toggleTab(.bookmarks)
        let empty = AnyView(EmptyView())
        let shell = MainShellViewController(
            coordinator: coordinator, theme: MoroTheme(), unreadInboxCount: 2,
            currentUserAvatarURL: nil, contentVersion: "tab-icons",
            homeView: empty, exploreView: empty, inboxView: empty, meView: empty,
            routeView: { _, _ in empty }
        )
        shell.loadViewIfNeeded()
        let items = try XCTUnwrap((shell.children.first as? UITabBarController)?.tabBar.items)
        XCTAssertEqual(items.count, coordinator.tabLayout.tabs.count)
        for (tab, item) in zip(coordinator.tabLayout.tabs, items) {
            let expectedLabel = tab == .inbox ? MoroL10n.Navigation.inboxUnread(2) : tab.title
            XCTAssertTrue(item.title?.isEmpty ?? true, tab.rawValue)
            XCTAssertEqual(item.accessibilityLabel, expectedLabel, tab.rawValue)
            XCTAssertEqual(item.image?.accessibilityLabel, expectedLabel, tab.rawValue)
            XCTAssertEqual(item.selectedImage?.accessibilityLabel, expectedLabel, tab.rawValue)
        }
    }

    func testDefaultTabBarUsesFlatSymbols() {
        let expected: [MainTab: (regular: String, selected: String)] = [
            .home: ("house", "house.fill"),
            .explore: ("magnifyingglass", "magnifyingglass"),
            .inbox: ("bell", "bell.fill"),
            .me: ("person", "person.fill"),
            .lists: ("list.bullet", "list.bullet"),
            .bookmarks: ("bookmark", "bookmark.fill"),
            .favourites: ("heart", "heart.fill"),
            .settings: ("gearshape", "gearshape.fill"),
        ]

        XCTAssertEqual(Set(expected.keys), Set(MainTab.allCases))

        for tab in MainTab.allCases {
            let symbols = expected[tab]
            XCTAssertEqual(tab.defaultIcon, symbols?.regular, tab.rawValue)
            XCTAssertEqual(tab.defaultFilledIcon, symbols?.selected, tab.rawValue)
            XCTAssertFalse(tab.defaultIcon.contains("circle"), tab.rawValue)
            XCTAssertFalse(tab.defaultIcon.contains("square"), tab.rawValue)
            XCTAssertFalse(tab.defaultFilledIcon.contains("circle"), tab.rawValue)
            XCTAssertFalse(tab.defaultFilledIcon.contains("square"), tab.rawValue)
        }
    }

    func testFlatTabBarSymbolsExistInUIKit() {
        for tab in MainTab.allCases {
            XCTAssertNotNil(UIImage(systemName: tab.defaultIcon), tab.defaultIcon)
            XCTAssertNotNil(UIImage(systemName: tab.defaultFilledIcon), tab.defaultFilledIcon)
        }
        // The unread inbox swaps in the bell's badged variants.
        XCTAssertNotNil(UIImage(systemName: "bell.badge"))
        XCTAssertNotNil(UIImage(systemName: "bell.badge.fill"))
    }
}
