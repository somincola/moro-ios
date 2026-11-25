//
//  NavigationAccessPolicy.swift
//  moro
//
//  Single source of truth coordinating bottom TabBar customization,
//  Moro's leading navigation drawer, and per-page top-bar controls so
//  every destination stays reachable without duplicating pinned tabs.
//

import Foundation

struct NavigationAccessPolicy: Equatable, Sendable {
    enum HomeTrailingAction: Equatable, Sendable {
        case announcements(unreadCount: Int)
        case search
        case none
    }

    /// Canonical order for optional destinations that appear in the drawer
    /// whenever they are not pinned to the bottom TabBar.
    static let drawerOverflowOrder: [MainTab] = [
        .me, .explore, .inbox, .lists, .bookmarks, .favourites,
    ]

    let tabLayout: NavigationTabLayout
    let unreadInboxCount: Int
    let unreadAnnouncementsCount: Int

    init(
        tabLayout: NavigationTabLayout,
        unreadInboxCount: Int = 0,
        unreadAnnouncementsCount: Int = 0
    ) {
        self.tabLayout = tabLayout
        self.unreadInboxCount = max(0, unreadInboxCount)
        self.unreadAnnouncementsCount = max(0, unreadAnnouncementsCount)
    }

    func isPinned(_ tab: MainTab) -> Bool {
        tabLayout.tabs.contains(tab)
    }

    /// Configurable destinations currently absent from the bottom TabBar.
    /// Home is always pinned; Settings has its own dedicated footer slot.
    var drawerOverflowTabs: [MainTab] {
        Self.drawerOverflowOrder.filter { !isPinned($0) }
    }

    /// Drawer footer Settings entry: always visible in the drawer regardless of bottom TabBar layout.
    var showsDrawerSettingsFooter: Bool {
        true
    }

    /// Own Profile top-bar Settings gear: shown only while Settings is not a bottom tab.
    var showsProfileSettingsButton: Bool {
        !isPinned(.settings)
    }

    /// Home TimelineSwitcher "Lists" shortcut: shown only while Lists is not a bottom tab.
    var showsTimelineSwitcherListsShortcut: Bool {
        !isPinned(.lists)
    }

    /// Smart trailing slot on the Home header:
    /// 1) Unread instance announcements take priority when present.
    /// 2) Otherwise, if Explore is hidden from the TabBar, offer 1-tap Search.
    /// 3) Otherwise remain clean whitespace.
    var homeTrailingAction: HomeTrailingAction {
        if unreadAnnouncementsCount > 0 {
            return .announcements(unreadCount: unreadAnnouncementsCount)
        }
        if !isPinned(.explore) {
            return .search
        }
        return .none
    }

    /// Subtle unread dot on the Home leading drawer avatar when unread notifications
    /// live inside the drawer (because Inbox is not pinned to the TabBar).
    var showsDrawerAvatarBadge: Bool {
        !isPinned(.inbox) && unreadInboxCount > 0
    }
}
