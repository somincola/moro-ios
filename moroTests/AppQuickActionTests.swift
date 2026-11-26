//
//  AppQuickActionTests.swift
//  moroTests
//
//  Tests for Home Screen Quick Actions, deep-link routing, and RootTabCoordinator quick navigation.
//

import Foundation
import Testing
import UIKit

@testable import moro

@Suite("App Quick Actions & Unified Routing")
struct AppQuickActionTests {
    private func makeAccount(
        id: String = "account-1",
        username: String = "moro",
        acct: String = "moro@social.example"
    ) -> Account {
        Account(
            id: id,
            username: username,
            acct: acct,
            displayName: "Moro",
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 120,
            followingCount: 45,
            statusesCount: 18
        )
    }

    @Test func shortcutTypesRoundTripAndRejectUnknownTypes() {
        for action in AppQuickAction.allCases {
            #expect(AppQuickAction(shortcutType: action.shortcutType) == action)
        }

        #expect(AppQuickAction(shortcutType: "") == nil)
        #expect(AppQuickAction(shortcutType: "com.other.app.compose") == nil)
        #expect(AppQuickAction(shortcutType: "com.somincola.moro.quickaction.unknown") == nil)
    }

    @Test func inboxShortcutIconReflectsUnreadState() {
        #expect(AppQuickAction.inbox.systemImageName(unreadCount: 0) == "bell")
        #expect(AppQuickAction.inbox.systemImageName(unreadCount: 3) == "bell.badge")
        #expect(AppQuickAction.compose.systemImageName(unreadCount: 0) == "square.and.pencil")
        #expect(AppQuickAction.search.systemImageName(unreadCount: 0) == "magnifyingglass")
        #expect(AppQuickAction.profile.systemImageName(unreadCount: 0) == "person.crop.circle")
    }

    @Test func catalogReturnsEmptyShortcutsWhenSignedOut() {
        let items = AppQuickActionCatalog.shortcutItems(account: nil, unreadCount: 5)
        #expect(items.isEmpty)
    }

    @Test func catalogBuildsFourDynamicShortcutsForSignedInAccount() {
        let account = makeAccount(acct: "nagi@mastodon.social")

        let quietItems = AppQuickActionCatalog.shortcutItems(account: account, unreadCount: 0)
        #expect(quietItems.map(\.type) == [
            AppQuickAction.compose.shortcutType,
            AppQuickAction.search.shortcutType,
            AppQuickAction.inbox.shortcutType,
            AppQuickAction.profile.shortcutType,
        ])
        #expect(quietItems[0].localizedSubtitle == "@nagi@mastodon.social")
        #expect(quietItems[1].localizedSubtitle == MoroL10n.QuickAction.searchSubtitle)
        #expect(quietItems[2].localizedSubtitle == MoroL10n.QuickAction.inboxSubtitleEmpty)
        #expect(quietItems[3].localizedSubtitle == "@nagi@mastodon.social")

        let unreadItems = AppQuickActionCatalog.shortcutItems(account: account, unreadCount: 4)
        #expect(unreadItems[2].localizedSubtitle == MoroL10n.QuickAction.inboxSubtitleUnread(4))
    }

    @Test @MainActor func quickActionCenterHandlesShortcutsDeepLinksAndWidgetHandoff() throws {
        let suite = "AppQuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let notificationCenter = NotificationCenter()
        let center = AppQuickActionCenter(notificationCenter: notificationCenter)

        var notificationCount = 0
        let token = notificationCenter.addObserver(
            forName: AppQuickActionCenter.didReceiveDestination,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { notificationCenter.removeObserver(token) }

        let searchItem = UIApplicationShortcutItem(
            type: AppQuickAction.search.shortcutType,
            localizedTitle: "Search"
        )
        #expect(center.handleShortcutItem(searchItem) == true)
        #expect(notificationCount == 1)
        #expect(center.consumePendingDestination(handoffDefaults: defaults) == .search)
        #expect(center.consumePendingDestination(handoffDefaults: defaults) == nil)

        let unknownItem = UIApplicationShortcutItem(type: "com.example.unknown", localizedTitle: "Other")
        #expect(center.handleShortcutItem(unknownItem) == false)

        let composeURL = try #require(URL(string: "moro://open/compose"))
        #expect(center.receive(url: composeURL) == true)
        #expect(center.consumePendingDestination(handoffDefaults: defaults) == .compose)

        let invalidURL = try #require(URL(string: "moro://open/compose?extra=1"))
        #expect(center.receive(url: invalidURL) == false)

        // Fallback to App Group widget handoff when no in-memory quick action is queued.
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        MoroWidgetHandoffStore.write(
            destination: .inbox,
            now: now,
            to: defaults,
            notificationCenter: nil
        )
        #expect(center.consumePendingDestination(handoffDefaults: defaults, now: now) == .inbox)
        #expect(center.consumePendingDestination(handoffDefaults: defaults, now: now) == nil)
    }

    @Test @MainActor func rootTabCoordinatorQuickDestinationRoutesCleanly() {
        let account = makeAccount()
        let coordinator = RootTabCoordinator()

        // Search opens an auto-focused search sheet immediately and closes drawer/compose.
        coordinator.openDrawer()
        coordinator.openQuickDestination(.search, account: account)
        #expect(coordinator.isDrawerPresented == false)
        #expect(coordinator.presentedSheet == .search(autoFocus: true))
        #expect(coordinator.composeContext == nil)

        // Compose dismisses search sheet and opens compose; repeat compose keeps active session intact.
        coordinator.openQuickDestination(.compose, account: account)
        #expect(coordinator.presentedSheet == nil)
        let activeComposeID = coordinator.composeContext?.id
        #expect(activeComposeID != nil)
        coordinator.openQuickDestination(.compose, account: account)
        #expect(coordinator.composeContext?.id == activeComposeID)

        // Inbox dismisses compose and selects inbox with .all filter.
        coordinator.inboxFilter = .mentions
        coordinator.openQuickDestination(.inbox, account: account)
        #expect(coordinator.composeContext == nil)
        #expect(coordinator.selectedTab == .inbox)
        #expect(coordinator.inboxFilter == .all)

        // Profile selects Me tab when present.
        coordinator.openQuickDestination(.profile, account: account)
        #expect(coordinator.selectedTab == .me)

        // Home returns cleanly to Home tab.
        coordinator.openQuickDestination(.home, account: account)
        #expect(coordinator.selectedTab == .home)
    }
}
