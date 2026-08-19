//
//  SettingsSheetHarnessView.swift
//  moro
//
//  Deterministic UI-test harness for the root Settings sheet contract.
//

import SwiftUI

struct SettingsSheetHarnessView: View {
    @StateObject private var appState = AppState()
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
            }
        }
        .task {
            presentedSheet = .settings
        }
    }
}
