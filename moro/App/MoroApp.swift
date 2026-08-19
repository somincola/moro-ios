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
                if shouldUseSettingsSheetHarness {
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
                        .onChange(of: scenePhase) { _, newPhase in
                            guard newPhase == .active else { return }
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
