//
//  MastodonAPIClientKey.swift
//  moro
//
//  Environment key carrying the active session's MastodonAPI client down the
//  view tree, so post-rendering surfaces (timeline, profile, hashtag,
//  favourites, lists, …) get a client for the translation control without
//  every call site having to thread `translationAPIClient` explicitly.
//
//  Injected at AppCoordinatorView (the authenticated root, recreated per
//  session via `.id`) AND re-injected on each of MainTabView's five tab-root
//  AnyViews — the shell hosts those in separate UIHostingControllers
//  (MainShellUIKit) that do NOT inherit the parent SwiftUI environment, the
//  same reason `\.activeAccountKey` and the AppState object are re-injected
//  there. On account switch the new `coordinator.apiClient` propagates through
//  both injection points.
//

import SwiftUI

private struct MastodonAPIClientKey: EnvironmentKey {
    static let defaultValue: MastodonAPI? = nil
}

extension EnvironmentValues {
    /// The active session's API client, or `nil` before sign-in.
    var mastodonAPIClient: MastodonAPI? {
        get { self[MastodonAPIClientKey.self] }
        set { self[MastodonAPIClientKey.self] = newValue }
    }
}
