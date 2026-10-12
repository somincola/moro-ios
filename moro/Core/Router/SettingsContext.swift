//
//  SettingsContext.swift
//  moro
//
//  Environment-injected dependencies and presentation action for Settings.
//

import SwiftUI

struct SettingsContext {
    var onLogout: () -> Void = {}
    var accountSessions: [StoredAccountSession] = []
    var activeSessionID: String? = nil
    var onSwitchAccount: (String) -> Void = { _ in }
    var onAddAccount: () -> Void = {}
    var onRemoveAccount: (String) -> Void = { _ in }
    /// Closes Settings and opens an account (`user@domain`) in the app's own profile view.
    /// Nil outside the main shell; callers fall back to the web profile.
    var onOpenAccount: ((String) -> Void)? = nil
}

private struct SettingsContextKey: EnvironmentKey {
    static let defaultValue = SettingsContext()
}

extension EnvironmentValues {
    var settingsContext: SettingsContext {
        get { self[SettingsContextKey.self] }
        set { self[SettingsContextKey.self] = newValue }
    }
}

private struct SettingsPresentationActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var settingsPresentationAction: () -> Void {
        get { self[SettingsPresentationActionKey.self] }
        set { self[SettingsPresentationActionKey.self] = newValue }
    }
}

// MARK: - Active account key

/// Stable per-account key (`activeSessionID`, or "no-active-session" before login),
/// injected into each tab's hosted tree so router-pushed pages (e.g. Lists) can read
/// and write per-account settings — like pinned timelines — without threading
/// the session ID through every init. Matches TimelineHomeView's `cacheClientID`.
private struct ActiveAccountKeyEnvironmentKey: EnvironmentKey {
    static let defaultValue = "no-active-session"
}

extension EnvironmentValues {
    var activeAccountKey: String {
        get { self[ActiveAccountKeyEnvironmentKey.self] }
        set { self[ActiveAccountKeyEnvironmentKey.self] = newValue }
    }
}
