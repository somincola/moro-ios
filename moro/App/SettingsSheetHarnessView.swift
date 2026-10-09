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

    var body: some View {
        VStack(spacing: 16) {
            Text("Settings Sheet Harness")

            Button("Open Settings") {
                presentedSheet = .settings
            }
            .accessibilityIdentifier("settings.sheet.open")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(appState)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .settings:
                SettingsSheetView(apiClient: nil)
                    .environmentObject(appState)
                    .moroSheetSurface(detents: [.large], cornerRadius: 20)
                    .moroTheme(harnessTheme)
                    .dynamicTypeSize(harnessTheme.dynamicTypeSize)
                    .preferredColorScheme(harnessTheme.colorScheme)
            }
        }
        .task {
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
            colorSchemeContrast: colorSchemeContrast, dynamicTypeSize: size
        )
    }
}
