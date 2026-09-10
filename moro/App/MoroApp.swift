//
//  MoroApp.swift
//  moro
//
//  Created by Noah on 11/24/25.
//

import SwiftUI
import UIKit

@main
struct MoroApp: App {
    @UIApplicationDelegateAdaptor(MoroAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var settings = AppSettings.shared

    init() {
        StorageManagementStore.configureImageCache()
        let appState = AppState()
        let interceptor = AuthInterceptor(tokenProvider: appState)
        let client = MastodonClient(authInterceptor: interceptor)
        _coordinator = StateObject(wrappedValue: AppCoordinator(appState: appState, apiClient: client))
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("UITEST_DISABLE_ANIMATIONS")
            || processInfo.environment["UITEST_DISABLE_ANIMATIONS"] == "1"
        {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldUsePublishingHarness {
                    publishingHarness.preferredColorScheme(colorScheme)
                } else if shouldUsePushHarness {
                    pushHarness.preferredColorScheme(colorScheme)
                } else if shouldUseSettingsSheetHarness {
                    SettingsSheetHarnessView()
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseAccountDeletionHarness {
                    AccountDeletionHarnessView()
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseComposeMediaHarness {
                    ComposeMediaGridHarnessView()
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseTimelineLiveHarness {
                    timelineLiveHarness.preferredColorScheme(colorScheme)
                } else if shouldUseListCacheHarness {
                    listCacheHarness.preferredColorScheme(colorScheme)
                } else if shouldUseBookmarksHarness {
                    bookmarksHarness.preferredColorScheme(colorScheme)
                } else if shouldUseThreadReadingHarness {
                    threadReadingHarness.preferredColorScheme(colorScheme)
                } else if shouldUseComposeReadingHarness {
                    composeReadingHarness.preferredColorScheme(colorScheme)
                } else if shouldUseComposeReplyHarness {
                    composeReplyHarness.preferredColorScheme(colorScheme)
                } else if shouldUseTopicsHarness {
                    topicsHarness.preferredColorScheme(colorScheme)
                } else if shouldUseProfileExperienceHarness {
                    profileExperienceHarness.preferredColorScheme(colorScheme)
                } else if shouldUseSearchFlowHarness {
                    searchFlowHarness
                        .preferredColorScheme(colorScheme)
                } else if shouldUseDirectMessagesHarness {
                    directMessagesHarness.preferredColorScheme(colorScheme)
                } else if shouldUseEditSourceHarness {
                    editSourceHarness
                        .preferredColorScheme(colorScheme)
                } else if shouldUseComposeCounterHarness {
                    ComposeCounterHarnessView()
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseNotificationTapHarness {
                    NotificationRowTapHarnessView()
                        .moroTheme(
                            MoroTheme(
                                accent: .monochrome
                            )
                        )
                        .preferredColorScheme(colorScheme)
                } else {
                    AppCoordinatorView(coordinator: coordinator)
                        .environmentObject(coordinator.appState)
                        .preferredColorScheme(colorScheme)
                        .task {
                            await coordinator.start()
                        }
                        .task { await AppUpdateStore.shared.check() }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .background {
                                Task { await CacheManager.shared.timelineCache.flushPendingWrites() }
                            }
                            guard newPhase == .active else { return }
                            Task { await AppUpdateStore.shared.check() }
                            Task {
                                await coordinator.refreshCurrentAccountIfNeeded()
                            }
                        }
                }
            }
            .environment(
                \.dynamicTypeSize,
                uiTestDynamicTypeSizeOverride ?? systemDynamicTypeSize
            )
            .privacyProtectedWhenInactive()
        }
    }

    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var shouldUsePushHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_PUSH_OPEN")
        #else
        false
        #endif
    }

    private var shouldUsePublishingHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_PUBLISHING")
        #else
        false
        #endif
    }

    @ViewBuilder private var publishingHarness: some View {
        #if DEBUG
        ComposePublishingHarnessView().moroTheme(MoroTheme(accent: .monochrome))
        #endif
    }

    @ViewBuilder private var pushHarness: some View {
        #if DEBUG
        PushNotificationHarnessView()
            .moroTheme(MoroTheme(accent: .monochrome))
        #endif
    }

    private var launchEnvironment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    private var isRunningUITests: Bool {
        launchEnvironment["XCTestConfigurationFilePath"] != nil
    }

    private var allowsUITestOverrides: Bool {
        isRunningUITests || launchEnvironment["UITEST_USE_FULL_APP"] == "1"
    }

    private var isNotificationTapHarnessMode: Bool {
        launchArguments.contains("UITEST_NOTIFICATION_ROW_TAPS")
            || launchEnvironment["UITEST_NOTIFICATION_ROW_TAPS"] == "1"
    }

    private var shouldUseNotificationTapHarness: Bool {
        if isNotificationTapHarnessMode { return true }
        if isRunningUITests && launchEnvironment["UITEST_USE_FULL_APP"] != "1" {
            return true
        }
        return false
    }

    private var shouldUseComposeCounterHarness: Bool {
        launchArguments.contains("UITEST_COMPOSE_COUNTER")
            || launchEnvironment["UITEST_COMPOSE_COUNTER"] == "1"
    }

    private var shouldUseTimelineLiveHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_TIMELINE_LIVE")
        #else
        false
        #endif
    }

    @ViewBuilder private var timelineLiveHarness: some View {
        #if DEBUG
        TimelineLiveHarnessView()
        #endif
    }

    private var shouldUseListCacheHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_LIST_CACHE")
        #else
        false
        #endif
    }

    @ViewBuilder private var listCacheHarness: some View {
        #if DEBUG
        ListCacheHarnessView()
        #endif
    }

    private var shouldUseBookmarksHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_BOOKMARK_READING")
        #else
        false
        #endif
    }

    @ViewBuilder private var bookmarksHarness: some View {
        #if DEBUG
        BookmarksHarnessView()
        #endif
    }

    private var shouldUseThreadReadingHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_THREAD_READING")
        #else
        false
        #endif
    }

    @ViewBuilder private var threadReadingHarness: some View {
        #if DEBUG
        ThreadReadingHarnessView()
        #endif
    }

    private var shouldUseComposeReadingHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_COMPOSE_READING")
        #else
        false
        #endif
    }

    @ViewBuilder private var composeReadingHarness: some View {
        #if DEBUG
        ComposeReadingHarnessView()
        #endif
    }

    private var shouldUseComposeReplyHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_COMPOSE_REPLY")
        #else
        false
        #endif
    }

    @ViewBuilder private var composeReplyHarness: some View {
        #if DEBUG
        ComposeReplyHarnessView()
        #endif
    }

    private var shouldUseTopicsHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_TOPICS")
        #else
        false
        #endif
    }

    @ViewBuilder private var topicsHarness: some View {
        #if DEBUG
        TopicsHarnessView()
        #endif
    }

    private var shouldUseProfileExperienceHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_PROFILE_EXPERIENCE")
        #else
        false
        #endif
    }

    @ViewBuilder private var profileExperienceHarness: some View {
        #if DEBUG
        ProfileExperienceHarnessView()
        #endif
    }

    private var shouldUseSearchFlowHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_SEARCH_FLOW")
        #else
        false
        #endif
    }

    private var shouldUseDirectMessagesHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_DIRECT_MESSAGES")
        #else
        false
        #endif
    }

    @ViewBuilder
    private var directMessagesHarness: some View {
        #if DEBUG
        DirectMessagesHarnessView()
        #endif
    }

    @ViewBuilder
    private var searchFlowHarness: some View {
        #if DEBUG
        SearchFlowHarnessView()
        #endif
    }

    private var shouldUseEditSourceHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_EDIT_SOURCE")
            || launchEnvironment["UITEST_EDIT_SOURCE"] == "1"
        #else
        false
        #endif
    }

    @ViewBuilder
    private var editSourceHarness: some View {
        #if DEBUG
        ComposeEditSourceHarnessView()
        #endif
    }

    private var shouldUseComposeMediaHarness: Bool {
        launchArguments.contains("UITEST_COMPOSE_MEDIA")
            || launchEnvironment["UITEST_COMPOSE_MEDIA"] == "1"
    }

    private var shouldUseAccountDeletionHarness: Bool {
        launchArguments.contains("UITEST_ACCOUNT_DELETION")
            || launchEnvironment["UITEST_ACCOUNT_DELETION"] == "1"
    }

    private var shouldUseSettingsSheetHarness: Bool {
        launchArguments.contains("UITEST_SETTINGS_SHEET")
            || launchEnvironment["UITEST_SETTINGS_SHEET"] == "1"
    }

    /// Get the color scheme based on settings
    private var colorScheme: ColorScheme? {
        if allowsUITestOverrides {
            switch launchEnvironment["UITEST_COLOR_SCHEME"] {
            case "light": return .light
            case "dark": return .dark
            default: break
            }
        }

        switch settings.appearance {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil // Use system default
        }
    }

    private var uiTestDynamicTypeSizeOverride: DynamicTypeSize? {
        guard allowsUITestOverrides else { return nil }
        switch launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] {
        case "accessibilityXXXL": return .accessibility5
        default: return nil
        }
    }
}
