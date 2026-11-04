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
    static let contentHorizontalInset: CGFloat = MoroLayoutMetrics.contentHorizontalInset
    /// UISearchBar(.minimal) keeps an internal side inset around searchTextField.
    /// Widen the hosting search bar so the visible field aligns with content.
    static let searchBarInternalFieldInset: CGFloat = 8
    static let searchBarOuterHorizontalInset: CGFloat =
        contentHorizontalInset - searchBarInternalFieldInset
    static let searchFieldHeight: CGFloat = 36
    static let searchFieldVerticalInset: CGFloat = 4
    static let searchFieldCornerRadius: CGFloat = 10
    static let maximumSearchFieldPointSize: CGFloat = 22
    static let maximumScopePointSize: CGFloat = 20
    static let searchGlyphPointSize: CGFloat = 16
    static let clearGlyphPointSize: CGFloat = 14
}

struct SearchView: View {
    @Environment(\.activeAccountKey) private var accountKey
    let apiClient: MastodonAPI
    var initialQuery: String? = nil
    var initialScope: SearchViewModel.Scope = .accounts
    var onEntryStateChanged: ((Bool) -> Void)? = nil

    var body: some View {
        SearchContentView(apiClient: apiClient, initialQuery: initialQuery, initialScope: initialScope,
                          onEntryStateChanged: onEntryStateChanged)
            .id(accountKey)
    }
}

/// Keep the controller and all post action services in the same account lifetime.
struct SearchContentView: View {
    @Environment(\.appRouter) var router
    @Environment(\.activeAccountKey) var accountKey
    @Environment(\.moroTheme) var theme
    @Environment(\.cacheManager) var cacheManager
    @Environment(\.openURL) var openURL
    @Environment(\.moroMediaPrefs) var mediaPreferences
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) var playAnimatedImages
    @Environment(\.moroSceneDescriptor) var sceneDescriptor
    @Environment(\.tabReselection) var tabReselection
    @Environment(\.tabActivation) var tabActivation
    @EnvironmentObject var appState: AppState
    @StateObject var interactionService: PostInteractionService
    @StateObject var actionSurface = PostActionSurfaceCenter()
    @StateObject var postMenuActionCenter: PostMenuActionCenter
    let apiClient: MastodonAPI
    let initialQuery: String?
    let initialScope: SearchViewModel.Scope
    let onEntryStateChanged: ((Bool) -> Void)?

    init(apiClient: MastodonAPI, initialQuery: String?, initialScope: SearchViewModel.Scope,
         onEntryStateChanged: ((Bool) -> Void)? = nil) {
        self.apiClient = apiClient
        self.initialQuery = initialQuery
        self.initialScope = initialScope
        self.onEntryStateChanged = onEntryStateChanged
        _interactionService = StateObject(wrappedValue: PostInteractionService(apiClient: apiClient))
        _postMenuActionCenter = StateObject(wrappedValue: PostMenuActionCenter(apiClient: apiClient))
    }

    var body: some View {
        searchWithPostActionSurfaces
    }

    var searchContent: some View {
        SearchCoreControllerHost(
            apiClient: apiClient, initialQuery: initialQuery, initialScope: initialScope,
            accountKey: accountKey, theme: theme, tabReselection: tabReselection,
            tabActivation: tabActivation,
            systemAllowsAnimatedAvatars: !reduceMotion && playAnimatedImages,
            makeAccountView: { hostedSearchContent(SearchAccountRowContentView(account: $0)) },
            makeStatusView: { status, onPollVote in
                hostedSearchContent(
                    VStack(spacing: 0) {
                        TimelinePostRow(
                            status: status, threadContext: .none,
                            translationAPIClient: apiClient,
                            accountCache: cacheManager.accountCache,
                            actions: handlers.buildPostActions(for: status, onPollVote: onPollVote)
                        )
                        MoroDivider()
                    }
                    .id(status.id)
                )
            },
            onOpenProfile: { router.navigate(to: .userProfile($0)) },
            onOpenStatus: { router.navigate(to: .statusDetail($0.displayStatus)) },
            onOpenHashtag: { router.navigate(to: .hashtag($0)) },
            onEntryStateChanged: onEntryStateChanged
        )
        // Extend the UIKit list behind the native tab bar, like the timeline.
        // Its scroll view still uses UIKit's automatic safe-area content insets.
        .ignoresSafeArea(.container, edges: .bottom)
        .background((sceneDescriptor?.canvas ?? .content).backgroundColor(in: theme))
    }

    private func hostedSearchContent(_ content: some View) -> AnyView {
        AnyView(content
            .environment(\.appRouter, router)
            .environment(\.openURL, openURL)
            .environment(\.moroMediaPrefs, mediaPreferences)
            .environment(\.activeAccountKey, accountKey)
            .environment(\.scenePhase, scenePhase)
            .environment(\.colorScheme, theme.colorScheme)
            .environment(\.dynamicTypeSize, theme.dynamicTypeSize)
            .moroTheme(theme))
    }
}

#if os(iOS)
private struct SearchCoreControllerHost: UIViewControllerRepresentable {
    let apiClient: MastodonAPI
    let initialQuery: String?
    let initialScope: SearchViewModel.Scope
    let accountKey: String
    let theme: MoroTheme
    let tabReselection: TabReselection?
    let tabActivation: TabActivation?
    let systemAllowsAnimatedAvatars: Bool
    let makeAccountView: (Account) -> AnyView
    let makeStatusView: (Status, @escaping SearchCoreViewController.PollVoteHandler) -> AnyView
    let onOpenProfile: (Account) -> Void
    let onOpenStatus: (Status) -> Void
    let onOpenHashtag: (String) -> Void
    let onEntryStateChanged: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> SearchCoreViewController {
        let controller = SearchCoreViewController(
            apiClient: apiClient, initialQuery: initialQuery, theme: theme,
            accountKey: accountKey, initialScope: initialScope
        )
        updateCallbacks(controller)
        controller.markTabReselectionSeen(tabReselection)
        controller.markTabActivationSeen(tabActivation)
        return controller
    }

    func updateUIViewController(_ controller: SearchCoreViewController, context: Context) {
        updateCallbacks(controller)
        controller.apply(theme: theme)
        controller.handleTabReselection(tabReselection)
        controller.handleTabActivation(tabActivation)
    }

    private func updateCallbacks(_ controller: SearchCoreViewController) {
        // Assigning an observable during a view update invalidates its readers mid-update;
        // only write a real change.
        if controller.playbackScope.systemAllowsAnimatedAvatars != systemAllowsAnimatedAvatars {
            controller.playbackScope.systemAllowsAnimatedAvatars = systemAllowsAnimatedAvatars
        }
        controller.makeAccountView = makeAccountView
        controller.makeStatusView = makeStatusView
        controller.onOpenProfile = onOpenProfile
        controller.onOpenStatus = onOpenStatus
        controller.onOpenHashtag = onOpenHashtag
        controller.onEntryStateChanged = onEntryStateChanged
    }

    static func dismantleUIViewController(_ controller: SearchCoreViewController, coordinator: ()) {
        controller.stopMediaPlayback()
        controller.cancelInFlightSearchRequests()
        controller.cancelDiscoveryRequests()
        controller.onEntryStateChanged?(false)
    }
}
#endif
