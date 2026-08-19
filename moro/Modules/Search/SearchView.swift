//
//  SearchView.swift
//  moro
//
//  High-performance core search page (UIKit-backed) focused on smooth input and accurate results.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum SearchLayoutMetrics {
    static let contentHorizontalInset: CGFloat = 16
    /// UISearchBar(.minimal) keeps an internal side inset around searchTextField.
    /// Widen the hosting search bar so the visible field aligns with content.
    static let searchBarInternalFieldInset: CGFloat = 8
    static let searchBarOuterHorizontalInset: CGFloat =
        contentHorizontalInset - searchBarInternalFieldInset
    static let maximumSearchFieldPointSize: CGFloat = 22
    static let maximumScopePointSize: CGFloat = 20
    static let searchGlyphPointSize: CGFloat = 16
    static let clearGlyphPointSize: CGFloat = 14
}

struct SearchView: View {
    @Environment(\.appRouter) private var router
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    private let apiClient: MastodonAPI
    private let initialQuery: String?

    init(apiClient: MastodonAPI, initialQuery: String? = nil) {
        self.apiClient = apiClient
        self.initialQuery = initialQuery
    }

    var body: some View {
        SearchCoreControllerHost(
            apiClient: apiClient,
            initialQuery: initialQuery,
            theme: theme,
            onOpenProfile: { account in
                router.navigate(to: .userProfile(account))
            },
            onOpenStatus: { status in
                router.navigate(to: .statusDetail(status.displayStatus))
            },
            onOpenHashtag: { tag in
                router.navigate(to: .hashtag(tag))
            }
        )
        .background(sceneCanvasColor)
    }

    private var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .content).backgroundColor(in: theme)
    }
}

#if os(iOS)
private struct SearchCoreControllerHost: UIViewControllerRepresentable {
    let apiClient: MastodonAPI
    let initialQuery: String?
    let theme: MoroTheme
    let onOpenProfile: (Account) -> Void
    let onOpenStatus: (Status) -> Void
    let onOpenHashtag: (String) -> Void

    func makeUIViewController(context: Context) -> SearchCoreViewController {
        let controller = SearchCoreViewController(
            apiClient: apiClient,
            initialQuery: initialQuery,
            theme: theme
        )
        controller.onOpenProfile = onOpenProfile
        controller.onOpenStatus = onOpenStatus
        controller.onOpenHashtag = onOpenHashtag
        return controller
    }

    func updateUIViewController(_ uiViewController: SearchCoreViewController, context: Context) {
        uiViewController.onOpenProfile = onOpenProfile
        uiViewController.onOpenStatus = onOpenStatus
        uiViewController.onOpenHashtag = onOpenHashtag
        uiViewController.apply(theme: theme)
    }
}

#endif
