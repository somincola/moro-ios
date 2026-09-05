//
//  AppRouter.swift
//  moro
//
//  Central navigation router managing all app navigation (Coordinator Pattern)
//

import Combine
import SwiftUI
import WebKit

/// Central navigation coordinator managing app-wide navigation
/// Inject via @EnvironmentObject to access from any view
@MainActor
protocol AppRouterNavigator: AnyObject {
    func navigate(to route: Route)
    func pop()
    func popToRoot()
    func replace(with route: Route)
}

@MainActor
final class AppRouter: ObservableObject {
    /// Navigation path for the current stack
    @Published var path = NavigationPath()
    weak var navigator: AppRouterNavigator?

    /// Navigate to a specific route by pushing it onto the navigation stack
    /// - Parameter route: The route to navigate to
    func navigate(to route: Route) {
        if let navigator {
            navigator.navigate(to: route)
            return
        }
        path.append(route)
    }

    /// Pop the current view from the navigation stack
    func pop() {
        if let navigator {
            navigator.pop()
            return
        }
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Pop to the root view (clear entire navigation stack)
    func popToRoot() {
        if let navigator {
            navigator.popToRoot()
            return
        }
        path.removeLast(path.count)
    }

    /// Replace the current navigation stack with a new route
    /// - Parameter route: The route to replace the stack with
    func replace(with route: Route) {
        if let navigator {
            navigator.replace(with: route)
            return
        }
        path.removeLast(path.count)
        path.append(route)
    }
}

@MainActor
struct AppRouteViewFactory {
    let apiClient: MastodonAPI
    let appState: AppState
    let cacheManager: CacheManager

    func view(for route: Route) -> AnyView {
        switch route {
        case .statusDetail(let status):
            return AnyView(
                StatusDetailRouteView(
                    status: status,
                    apiClient: apiClient,
                    threadCache: cacheManager.threadCache,
                    accountCache: cacheManager.accountCache,
                    prefetchCoordinator: .shared
                )
                .id(status.id)
                .toolbar(.hidden, for: .tabBar)
            )

        case .hashtag(let tag):
            return AnyView(
                HashtagRouteView(hashtag: tag, apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .search(let query, let scope):
            return AnyView(
                SearchView(apiClient: apiClient, initialQuery: query, initialScope: SearchViewModel.Scope(rawValue: scope) ?? .all)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .followedTopics:
            return AnyView(FollowedTopicsRouteView(apiClient: apiClient).toolbar(.hidden, for: .tabBar))

        case .savedSearches:
            return AnyView(SavedSearchesRouteView().toolbar(.hidden, for: .tabBar))

        case .accountLookup(let acct):
            return AnyView(
                AccountLookupRouteView(acct: acct, apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .announcements:
            return AnyView(
                AnnouncementsView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .announcementDetail(let announcement):
            return AnyView(
                AnnouncementDetailView(announcement: announcement, apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .mentionUser(let mention):
            return AnyView(
                ProfileView(
                    account: nil,
                    accountID: mention.id,
                    onLogout: {},
                    apiClient: apiClient
                )
                .toolbar(.hidden, for: .tabBar)
            )

        case .userProfile(let account):
            return AnyView(
                ProfileView(
                    account: account,
                    accountID: account.id,
                    onLogout: {},
                    apiClient: apiClient
                )
                .toolbar(.hidden, for: .tabBar)
            )

        case .profileConnections(let accountID, let kind):
            return AnyView(
                ProfileConnectionsView(
                    accountID: accountID,
                    kind: kind,
                    apiClient: apiClient
                )
                .toolbar(.hidden, for: .tabBar)
            )

        case .mediaPreview(let url):
            return AnyView(
                RouteMediaPreviewView(url: url)
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .webPreview(let url):
            return AnyView(
                RouteWebPreviewView(url: url)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .mediaGallery(let items, let initialIndex):
            return AnyView(
                RouteMediaGalleryView(items: items, initialIndex: initialIndex)
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .conversationDetail(let conversation):
            return AnyView(
                ConversationDetailView(
                    conversation: conversation,
                    apiClient: apiClient
                )
                .toolbar(.hidden, for: .tabBar)
            )

        case .bookmarks:
            return AnyView(
                BookmarksRouteView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .favourites:
            return AnyView(
                FavouritesView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .lists:
            return AnyView(
                ListsView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .scheduledStatuses:
            return AnyView(
                ScheduledStatusesView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .instanceDetails:
            return AnyView(
                InstanceDetailsView(apiClient: apiClient)
                    .toolbar(.hidden, for: .tabBar)
            )

        case .editProfile:
            return AnyView(
                EditProfileView(apiClient: apiClient, currentAccount: appState.currentAccount)
                    .toolbar(.hidden, for: .tabBar)
            )
        }
    }
}

// MARK: - Environment Key

private struct AppRouterKey: EnvironmentKey {
    static let defaultValue = AppRouter()
}

extension EnvironmentValues {
    var appRouter: AppRouter {
        get { self[AppRouterKey.self] }
        set { self[AppRouterKey.self] = newValue }
    }
}

// MARK: - View Modifier

@MainActor
struct RouterModifier: ViewModifier {
    @StateObject private var router = AppRouter()

    let apiClient: MastodonAPI
    let isAtRoot: Binding<Bool>?

    func body(content: Content) -> some View {
        RouterNavigationContainer(
            router: router,
            apiClient: apiClient,
            isAtRoot: isAtRoot,
            content: content
        )
    }
}

@MainActor
struct InjectedRouterModifier: ViewModifier {
    @ObservedObject var router: AppRouter

    let apiClient: MastodonAPI
    let isAtRoot: Binding<Bool>?

    func body(content: Content) -> some View {
        RouterNavigationContainer(
            router: router,
            apiClient: apiClient,
            isAtRoot: isAtRoot,
            content: content
        )
    }
}

@MainActor
private struct RouterNavigationContainer<Content: View>: View {
    @ObservedObject var router: AppRouter
    @Environment(\.cacheManager) private var cacheManager
    @Environment(\.openURL) private var systemOpenURL
    @EnvironmentObject private var appState: AppState

    let apiClient: MastodonAPI
    let isAtRoot: Binding<Bool>?
    let content: Content

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationDestination(for: Route.self) { route in
                    destinationView(for: route)
                }
        }
        .onAppear {
            isAtRoot?.wrappedValue = router.path.isEmpty
        }
        .onChange(of: router.path.count) { _, count in
            isAtRoot?.wrappedValue = count == 0
        }
        .moroInteractivePopGestureEnabled()
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
    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        AppRouteViewFactory(
            apiClient: apiClient,
            appState: appState,
            cacheManager: cacheManager
        )
        .view(for: route)
    }
}

extension View {
    /// Apply router navigation to this view
    /// Creates a NavigationStack and handles all route destinations
    func withRouter(apiClient: MastodonAPI, isAtRoot: Binding<Bool>? = nil) -> some View {
        modifier(RouterModifier(apiClient: apiClient, isAtRoot: isAtRoot))
    }

    /// Apply router navigation with an injected router instance.
    /// Useful when a parent view needs to trigger navigation directly.
    func withRouter(
        apiClient: MastodonAPI,
        router: AppRouter,
        isAtRoot: Binding<Bool>? = nil
    ) -> some View {
        modifier(InjectedRouterModifier(router: router, apiClient: apiClient, isAtRoot: isAtRoot))
    }
}

@MainActor
private struct AccountLookupRouteView: View {
    let acct: String
    let apiClient: MastodonAPI

    @State private var resolvedAccount: Account?
    @State private var lookupFailed = false

    var body: some View {
        Group {
            if let resolvedAccount {
                ProfileView(
                    account: resolvedAccount,
                    accountID: resolvedAccount.id,
                    onLogout: {},
                    apiClient: apiClient
                )
            } else if lookupFailed {
                SearchView(apiClient: apiClient, initialQuery: displayAcct)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(displayAcct)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: acct) {
            guard resolvedAccount == nil, !lookupFailed else { return }
            do {
                resolvedAccount = try await apiClient.lookupAccount(acct: normalizedAcct)
            } catch {
                lookupFailed = true
            }
        }
    }

    private var normalizedAcct: String {
        acct.hasPrefix("@") ? String(acct.dropFirst()) : acct
    }

    private var displayAcct: String {
        normalizedAcct.hasPrefix("@") ? normalizedAcct : "@\(normalizedAcct)"
    }
}

@MainActor
private struct StatusDetailRouteView: View {
    let status: Status
    let apiClient: MastodonAPI
    let threadCache: ThreadCache
    let accountCache: AccountCache
    let prefetchCoordinator: StatusDetailPrefetchCoordinator

    var body: some View {
        StatusDetailView(
            status: status,
            apiClient: apiClient,
            threadCache: threadCache,
            accountCache: accountCache
        )
        .id(status.id)
        .task(id: status.id) {
            await prefetchCoordinator.prefetchStatusAndQuoteIfNeeded(
                for: status.displayStatus,
                apiClient: apiClient,
                threadCache: threadCache,
                accountCache: accountCache
            )
        }
    }
}

private struct RouteMediaGalleryView: View {
    let items: [RouteMediaGalleryItem]
    let initialIndex: Int

    private var normalizedInitialIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(initialIndex, 0), items.count - 1)
    }

    var body: some View {
        if items.isEmpty {
            Color.black.ignoresSafeArea()
        } else {
            ImagePreviewView(
                attachments: items.map {
                    Status.Attachment(
                        id: $0.id,
                        type: "image",
                        url: $0.url,
                        description: $0.altText
                    )
                },
                initialIndex: normalizedInitialIndex
            )
        }
    }
}

private struct RouteMediaPreviewView: View {
    let url: URL

    var body: some View {
        if isVideoURL {
            VideoFullscreenView(
                attachment: Status.Attachment(
                    id: url.absoluteString,
                    type: "video",
                    url: url
                )
            )
        } else {
            ImagePreviewView(
                attachments: [
                    Status.Attachment(
                        id: url.absoluteString,
                        type: "image",
                        url: url
                    )
                ],
                initialIndex: 0
            )
        }
    }

    private var isVideoURL: Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "avi", "gif", "gifv"].contains(ext)
    }
}

@MainActor
private struct RouteWebPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
