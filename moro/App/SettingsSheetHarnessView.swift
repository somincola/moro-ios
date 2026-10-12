//
//  SettingsSheetHarnessView.swift
//  moro
//
//  Deterministic UI-test harness for the root Settings sheet contract.
//

import SwiftUI

struct SettingsSheetHarnessView: View {
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedSheet: RootSheetDestination?
    @State private var serverPushMentions = "unknown"
    private let apiClient: MastodonAPI?
    private let session: StoredAccountSession?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SETTINGS_ACCOUNT"] == "1" {
            let account = ProfileFixtureProtocol.account()
            apiClient = ProfileFixtureProtocol.makeClient()
            session = StoredAccountSession(
                id: "ui-settings-account", account: account,
                instanceURLString: "https://profile-fixture.invalid",
                tokenStorageKey: "unused-ui-test-token", lastUsedAt: Date()
            )
        } else {
            apiClient = nil
            session = nil
        }
        #else
        apiClient = nil
        session = nil
        #endif
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Settings Sheet Harness")

            Button("Open Settings") {
                presentedSheet = .settings
            }
            .accessibilityIdentifier("settings.sheet.open")
            #if DEBUG
            if ProcessInfo.processInfo.environment["UITEST_SETTINGS_PUSH_SYNC"] == "1" {
                Button("Check Server Push Settings") {
                    Task {
                        let subscription = try? await apiClient?.fetchPushSubscription()
                        serverPushMentions = subscription.map { $0.alerts.mention ? "on" : "off" } ?? "failed"
                    }
                }
                .accessibilityIdentifier("settings.harness.checkPush")
                Text(serverPushMentions).accessibilityIdentifier("settings.harness.serverMentions")
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(appState)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .settings:
                SettingsSheetView(apiClient: apiClient)
                    .environmentObject(appState)
                    .environment(\.settingsContext, SettingsContext(
                        accountSessions: session.map { [$0] } ?? [], activeSessionID: session?.id
                    ))
                    .environment(\.activeAccountKey, session?.id ?? "no-active-session")
                    .moroSheetSurface(detents: [.large], cornerRadius: 20)
                    .moroTheme(harnessTheme)
                    .dynamicTypeSize(harnessTheme.dynamicTypeSize)
                    .preferredColorScheme(harnessTheme.colorScheme)
            }
        }
        .task {
            if let session, appState.currentAccount == nil {
                #if DEBUG
                if ProcessInfo.processInfo.environment["UITEST_SETTINGS_PUSH_SYNC"] == "1" {
                    PushSubscriptionCoordinator.shared.removeSettings(for: session.id)
                }
                #endif
                appState.currentAccount = session.account
                appState.authToken = "profile-fixture-token"
                appState.isAuthenticated = true
            }
            presentedSheet = .settings
        }
        .moroTheme(harnessTheme)
    }

    private var harnessTheme: MoroTheme {
        let environment = ProcessInfo.processInfo.environment
        let scheme: ColorScheme = switch environment["UITEST_COLOR_SCHEME"] {
        case "light": .light
        case "dark": .dark
        default: colorScheme
        }
        let size: DynamicTypeSize =
            environment["UITEST_DYNAMIC_TYPE_SIZE"] == "accessibilityXXXL" ? .accessibility5 : dynamicTypeSize
        return MoroTheme(
            colorScheme: scheme, themeColor: settings.themeColor,
            customThemeColor: settings.customThemeColor,
            postFontSize: settings.postFontSize,
            colorSchemeContrast: colorSchemeContrast, dynamicTypeSize: size
        )
    }
}
