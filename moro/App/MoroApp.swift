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
        #if DEBUG
        // First, before anything reads a setting.
        UITestDefaultsIsolation.applyIfRequested()
        #endif
        StorageManagementStore.configureImageCache()
        MoroTips.configure()
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
                if shouldUseAppStoreScreenshotHarness {
                    appStoreScreenshotHarness.preferredColorScheme(colorScheme)
                } else if shouldUseImagePreviewHarness {
                    imagePreviewHarness.preferredColorScheme(colorScheme)
                } else if shouldUsePublishingHarness {
                    publishingHarness.preferredColorScheme(colorScheme)
                } else if shouldUsePushHarness {
                    pushHarness.preferredColorScheme(colorScheme)
                } else if shouldUseSettingsSheetHarness {
                    settingsSheetHarness
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseAccountDeletionHarness {
                    accountDeletionHarness
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseComposeMediaHarness {
                    composeMediaHarness
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseTimelineMediaHarness {
                    timelineMediaHarness.preferredColorScheme(colorScheme)
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
                } else if shouldUseOnboardingPreview {
                    onboardingPreview.preferredColorScheme(colorScheme)
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
                    composeCounterHarness
                        .moroTheme(MoroTheme(accent: .monochrome))
                        .preferredColorScheme(colorScheme)
                } else if shouldUseNotificationTapHarness {
                    notificationTapHarness
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
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .background {
                                Task { await CacheManager.shared.timelineCache.flushPendingWrites() }
                            }
                            guard newPhase == .active else { return }
                            PushSubscriptionCoordinator.shared.resumeSettings(
                                apiClient: coordinator.apiClient, sessionKey: coordinator.activeSessionID)
                            Task {
                                await coordinator.refreshCurrentAccountIfNeeded()
                            }
                        }
                }
            }
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                guard newPhase == .active else { return }
                Task { @MainActor in
                    do {
                        settings.appIcon = try await AppIconManager.shared.reconcileSelection()
                    } catch {
                        // Keep the existing selection and retry on the next activation.
                        NSLog("[AppIcon] Failed to restore the primary icon: %@", error.localizedDescription)
                    }
                }
            }
            .environment(
                \.dynamicTypeSize,
                uiTestDynamicTypeSizeOverride ?? systemDynamicTypeSize
            )
        }
    }

    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var shouldUseAppStoreScreenshotHarness: Bool {
        #if DEBUG
        launchArguments.contains("APP_STORE_SCREENSHOTS")
        #else
        false
        #endif
    }

    @ViewBuilder private var appStoreScreenshotHarness: some View {
        #if DEBUG
        AppStoreScreenshotHarnessView()
        #endif
    }

    private var shouldUseImagePreviewHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_IMAGE_PREVIEW")
        #else
        false
        #endif
    }

    @ViewBuilder private var imagePreviewHarness: some View {
        #if DEBUG
        ImagePreviewHarnessView().moroTheme(MoroTheme(accent: .monochrome))
        #endif
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
        PushNotificationHarnessRoot()
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
        #if DEBUG
        if isNotificationTapHarnessMode { return true }
        if isRunningUITests && launchEnvironment["UITEST_USE_FULL_APP"] != "1" {
            return true
        }
        #endif
        return false
    }

    private var shouldUseComposeCounterHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_COMPOSE_COUNTER")
            || launchEnvironment["UITEST_COMPOSE_COUNTER"] == "1"
        #else
        false
        #endif
    }

    private var shouldUseTimelineLiveHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_TIMELINE_LIVE")
        #else
        false
        #endif
    }

    private var shouldUseTimelineMediaHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_TIMELINE_MEDIA")
        #else
        false
        #endif
    }

    @ViewBuilder private var timelineMediaHarness: some View {
        #if DEBUG
        TimelineMediaHarnessView()
        #endif
    }

    @ViewBuilder private var timelineLiveHarness: some View {
        #if DEBUG
        if launchArguments.contains("UITEST_TIMELINE_SWITCHING") {
            TimelineSwitchingHarnessView()
        } else {
            TimelineLiveHarnessView()
        }
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

    private var shouldUseOnboardingPreview: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_ONBOARDING_PREVIEW")
        #else
        false
        #endif
    }

    @ViewBuilder private var onboardingPreview: some View {
        #if DEBUG
        OnboardingPreviewHarness()
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
        #if DEBUG
        launchArguments.contains("UITEST_COMPOSE_MEDIA")
            || launchEnvironment["UITEST_COMPOSE_MEDIA"] == "1"
        #else
        false
        #endif
    }

    private var shouldUseAccountDeletionHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_ACCOUNT_DELETION")
            || launchEnvironment["UITEST_ACCOUNT_DELETION"] == "1"
        #else
        false
        #endif
    }

    private var shouldUseSettingsSheetHarness: Bool {
        #if DEBUG
        launchArguments.contains("UITEST_SETTINGS_SHEET")
            || launchEnvironment["UITEST_SETTINGS_SHEET"] == "1"
        #else
        false
        #endif
    }

    // Test-only harnesses are compiled into Debug builds only.
    @ViewBuilder private var settingsSheetHarness: some View {
        #if DEBUG
        SettingsSheetHarnessView()
        #endif
    }

    @ViewBuilder private var accountDeletionHarness: some View {
        #if DEBUG
        AccountDeletionHarnessView()
        #endif
    }

    @ViewBuilder private var composeMediaHarness: some View {
        #if DEBUG
        ComposeMediaGridHarnessView()
        #endif
    }

    @ViewBuilder private var composeCounterHarness: some View {
        #if DEBUG
        ComposeCounterHarnessView()
        #endif
    }

    @ViewBuilder private var notificationTapHarness: some View {
        #if DEBUG
        NotificationRowTapHarnessView()
        #endif
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
