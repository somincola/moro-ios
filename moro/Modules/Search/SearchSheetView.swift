//
//  SearchSheetView.swift
//  moro
//
//  Native large-sheet modal presentation for Search / Explore when Explore is not pinned
//  to the bottom TabBar. Hosts its own NavigationStack so results push cleanly inside the
//  sheet without disturbing the underlying timeline stack.
//

import SwiftUI

struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var systemOpenURL
    @StateObject private var router = AppRouter()

    let apiClient: MastodonAPI
    let autoFocusSearch: Bool
    let routeView: (Route, AppRouter) -> AnyView

    var body: some View {
        NavigationStack(path: $router.path) {
            SearchView(
                apiClient: apiClient,
                autoFocusOnAppear: autoFocusSearch
            )
            .navigationTitle(autoFocusSearch ? MoroL10n.Navigation.search : MoroL10n.Navigation.explore)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surfaceBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MoroNavigationControlButton(kind: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("search.sheet.close")
                }
            }
            .accessibilityAction(.escape) { dismiss() }
            .navigationDestination(for: Route.self) { route in
                routeView(route, router)
            }
        }
        .environmentObject(router)
        .environment(\.appRouter, router)
        .environment(
            \.openURL,
            OpenURLAction { url in
                URLHandler.shared.handleURL(
                    url,
                    router: router,
                    systemOpenURL: systemOpenURL
                )
                return .handled
            }
        )
        .tint(theme.colors.primary500)
    }
}
