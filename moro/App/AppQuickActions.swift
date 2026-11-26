//
//  AppQuickActions.swift
//  moro
//
//  Home Screen app icon long-press Quick Actions (UIApplicationShortcutItem)
//  and unified destination handoff across Quick Actions, Widgets, and deep links.
//

import Combine
import Foundation
import MoroLocalization
import UIKit

enum AppQuickAction: String, CaseIterable, Hashable, Sendable {
    case compose
    case search
    case inbox
    case profile

    static let shortcutTypePrefix = "com.somincola.moro.quickaction."

    var shortcutType: String {
        Self.shortcutTypePrefix + rawValue
    }

    var destination: MoroWidgetDestination {
        switch self {
        case .compose: return .compose
        case .search: return .search
        case .inbox: return .inbox
        case .profile: return .profile
        }
    }

    func systemImageName(unreadCount: Int) -> String {
        switch self {
        case .compose:
            return "square.and.pencil"
        case .search:
            return "magnifyingglass"
        case .inbox:
            return unreadCount > 0 ? "bell.badge" : "bell"
        case .profile:
            return "person.crop.circle"
        }
    }

    init?(shortcutType: String) {
        guard shortcutType.hasPrefix(Self.shortcutTypePrefix) else { return nil }
        let suffix = String(shortcutType.dropFirst(Self.shortcutTypePrefix.count))
        self.init(rawValue: suffix)
    }
}

enum AppQuickActionCatalog {
    /// Builds up to 4 dynamic Home Screen quick actions for the active account.
    /// Returns an empty list when signed out so unauthenticated launches stay clean.
    static func shortcutItems(
        account: Account?,
        unreadCount: Int
    ) -> [UIApplicationShortcutItem] {
        guard let account else { return [] }
        let normalizedUnread = max(0, unreadCount)
        let handle = formattedHandle(for: account)

        return [
            UIApplicationShortcutItem(
                type: AppQuickAction.compose.shortcutType,
                localizedTitle: MoroL10n.QuickAction.composeTitle,
                localizedSubtitle: handle,
                icon: UIApplicationShortcutIcon(
                    systemImageName: AppQuickAction.compose.systemImageName(unreadCount: normalizedUnread)
                )
            ),
            UIApplicationShortcutItem(
                type: AppQuickAction.search.shortcutType,
                localizedTitle: MoroL10n.QuickAction.searchTitle,
                localizedSubtitle: MoroL10n.QuickAction.searchSubtitle,
                icon: UIApplicationShortcutIcon(
                    systemImageName: AppQuickAction.search.systemImageName(unreadCount: normalizedUnread)
                )
            ),
            UIApplicationShortcutItem(
                type: AppQuickAction.inbox.shortcutType,
                localizedTitle: MoroL10n.QuickAction.inboxTitle,
                localizedSubtitle: normalizedUnread > 0
                    ? MoroL10n.QuickAction.inboxSubtitleUnread(normalizedUnread)
                    : MoroL10n.QuickAction.inboxSubtitleEmpty,
                icon: UIApplicationShortcutIcon(
                    systemImageName: AppQuickAction.inbox.systemImageName(unreadCount: normalizedUnread)
                )
            ),
            UIApplicationShortcutItem(
                type: AppQuickAction.profile.shortcutType,
                localizedTitle: MoroL10n.QuickAction.profileTitle,
                localizedSubtitle: handle,
                icon: UIApplicationShortcutIcon(
                    systemImageName: AppQuickAction.profile.systemImageName(unreadCount: normalizedUnread)
                )
            ),
        ]
    }

    static func formattedHandle(for account: Account) -> String {
        let trimmed = account.acct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "@\(account.username)"
        }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }
}

@MainActor
final class AppQuickActionCenter: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = AppQuickActionCenter()
    static let didReceiveDestination = Notification.Name("com.somincola.moro.quickAction.didReceiveDestination")

    private struct ShortcutSignature: Equatable {
        let accountID: String?
        let handle: String?
        let unreadCount: Int
        let localeIdentifier: String
    }

    @Published private(set) var pendingDestination: MoroWidgetDestination?

    private let notificationCenter: NotificationCenter
    private var lastSyncedSignature: ShortcutSignature?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func enqueue(_ destination: MoroWidgetDestination) {
        pendingDestination = destination
        notificationCenter.post(name: Self.didReceiveDestination, object: nil)
    }

    @discardableResult
    func handleShortcutItem(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = AppQuickAction(shortcutType: item.type) else {
            return false
        }
        enqueue(action.destination)
        return true
    }

    @discardableResult
    func receive(url: URL) -> Bool {
        guard let destination = MoroWidgetDestination(deepLinkURL: url) else {
            return false
        }
        enqueue(destination)
        return true
    }

    func consumePendingDestination(
        handoffDefaults: UserDefaults? = MoroWidgetSharedStore.sharedUserDefaults(),
        now: Date = Date()
    ) -> MoroWidgetDestination? {
        if let pendingDestination {
            self.pendingDestination = nil
            // Drain any stale App Group handoff written alongside a deep-link launch.
            _ = MoroWidgetHandoffStore.consume(from: handoffDefaults, now: now)
            return pendingDestination
        }
        return MoroWidgetHandoffStore.consume(from: handoffDefaults, now: now)?.destination
    }

    func syncShortcutItems(
        account: Account?,
        unreadCount: Int,
        application: UIApplication? = nil
    ) {
        let normalizedUnread = max(0, unreadCount)
        let signature = ShortcutSignature(
            accountID: account?.id,
            handle: account.map(AppQuickActionCatalog.formattedHandle(for:)),
            unreadCount: normalizedUnread,
            localeIdentifier: MoroL10n.preferredLocale.identifier
        )
        guard signature != lastSyncedSignature else { return }
        lastSyncedSignature = signature
        (application ?? .shared).shortcutItems = AppQuickActionCatalog.shortcutItems(
            account: account,
            unreadCount: normalizedUnread
        )
    }
}
