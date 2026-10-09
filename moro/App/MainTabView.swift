//
//  MainTabView.swift
//  moro
//
//  App-level navigation shell with bottom tabs.
//

import Combine
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Injects a `MoroTheme` derived from the *live* system color scheme + the user's selected accent
/// into a UIKit-hosted tab root, so a dark/light or accent change updates the hosted SwiftUI in
/// place — the shell no longer re-roots every tab just to push a fresh theme in. Mirrors the
/// app-root `AppCoordinatorView.effectiveTheme`; keep the two in sync.
private struct SystemColorSchemeMoroTheme: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content
            .moroTheme(
                MoroTheme(
                    colorScheme: colorScheme,
                    accent: settings.accentStyle,
                    themeColor: settings.themeColor,
                    customThemeColor: settings.customThemeColor,
                    colorSchemeContrast: colorSchemeContrast,
                    fontScale: settings.typographyFontScale.factor,
                    dynamicTypeSize: dynamicTypeSize
                )
            )
            .environment(
                \.moroMediaPrefs,
                MoroMediaPreferences(
                    autoplayGIFs: settings.autoplayGIFs
                )
            )
    }
}

struct MainTabView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.cacheManager) private var cacheManager
    @Environment(\.openURL) private var systemOpenURL
    @EnvironmentObject private var appState: AppState

    let apiClient: MastodonAPI
    let onLogout: () -> Void
    let accountSessions: [StoredAccountSession]
    let activeSessionID: String?
    let onSwitchAccount: (String) -> Void
    let onRemoveAccount: (String) -> Void
    let onAccountAuthenticated: (String, Account, URL) -> Void

    @StateObject private var coordinator = RootTabCoordinator()
    @ObservedObject private var notificationUnreadStore = NotificationUnreadStore.shared
    @ObservedObject private var inboxUnreadStore = InboxUnreadStore.shared
    private let sharedComposeImportCoordinator = SharedComposeImportCoordinator()

    private struct NotificationOpenTaskID: Equatable {
        let requestID: UUID?
        let sessionID: String?
        let isActive: Bool
        let isUnobstructed: Bool
    }

    private var notificationOpenTaskID: NotificationOpenTaskID {
        NotificationOpenTaskID(
            requestID: notificationUnreadStore.pendingOpenRequest?.id,
            sessionID: activeSessionID,
            isActive: scenePhase == .active,
            isUnobstructed: coordinator.presentedSheet == nil
                && coordinator.composeContext == nil && !coordinator.showAddAccountLogin
        )
    }

    private var activeAccountIDForSharedImport: String? {
        appState.currentAccount?.id
            ?? accountSessions.first(where: { $0.id == activeSessionID })?.account.id
    }

    /// Identity of the *content* the shell hosts — decides when the tab hosting controllers
    /// get re-rooted. Now just the account: the tab roots derive their theme from the live
    /// system color scheme (`SystemColorSchemeMoroTheme`), so dark/light updates in place
    /// without a re-root; accent is fixed to `.monochrome`; and the bottom tab bar re-reads
    /// its icon theme itself on every `apply`. (Account changes recreate MainTabView via
    /// `.id`, so this is effectively constant per instance — kept as a safety net.)
    private var contentVersion: String {
        activeSessionID ?? "no-active-session"
    }

    private var currentTabAvatarURL: URL? {
        appState.currentAccount?.avatarURL
            ?? accountSessions.first(where: { $0.id == activeSessionID })?.account.avatarURL
            ?? accountSessions.first?.account.avatarURL
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MainShellContainerRepresentable(
                coordinator: coordinator,
                theme: theme,
                unreadInboxCount: inboxUnreadStore.totalUnreadCount,
                currentUserAvatarURL: currentTabAvatarURL,
                contentVersion: contentVersion,
                homeView: homeRootView,
                exploreView: exploreRootView,
                inboxView: inboxRootView,
                meView: meRootView,
                routeView: routeView(for:router:)
            )

        }
        // UIKit owns both system bars and their safe-area backgrounds. Give the shell the
        // full window so pushed scenes can carry their canvas through the bottom inset.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .fullScreenCover(item: $coordinator.composeContext) { wrapper in
            ComposeView(
                context: wrapper.context,
                apiClient: apiClient,
                currentUserID: appState.currentAccount?.id,
                initialDraft: wrapper.draft,
                sharedImport: wrapper.sharedImport,
                onDismiss: { coordinator.composeContext = nil }
            ) { _ in }
            .environmentObject(appState)
        }
        .sheet(item: $coordinator.presentedSheet) { destination in
            switch destination {
            case .settings:
                SettingsSheetView(apiClient: apiClient)
                    .environment(\.settingsContext, settingsContext)
                    .environment(\.activeAccountKey, activeSessionID ?? "no-active-session")
                    .moroSheetSurface(detents: [.large], cornerRadius: 20)
            }
        }
        .fullScreenCover(isPresented: $coordinator.showAddAccountLogin) {
            AddAccountLoginContainer {
                coordinator.showAddAccountLogin = false
            } onAuthSuccess: { token, account, instanceURL in
                coordinator.showAddAccountLogin = false
                onAccountAuthenticated(token, account, instanceURL)
            }
        }
        .onAppear {
            consumePendingWidgetHandoffIfNeeded()
            consumePendingSharedDraftIfNeeded()
            ensureInboxStreamSubscription()
            updateNotificationListVisibility()
        }
        .task(id: activeSessionID) {
            async let instanceMetadataLoad: Void = refreshInstanceMetadataIfNeeded()
            ensureInboxStreamSubscription()
            await notificationUnreadStore.activate(
                sessionID: activeSessionID,
                availableSessionIDs: accountSessions.map(\.id),
                apiClient: apiClient
            )
            await inboxUnreadStore.activate(
                sessionID: activeSessionID,
                availableSessionIDs: accountSessions.map(\.id),
                apiClient: apiClient
            )
            updateNotificationListVisibility()
            await instanceMetadataLoad
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            consumePendingWidgetHandoffIfNeeded()
            consumePendingSharedDraftIfNeeded()
            ensureInboxStreamSubscription()
            Task {
                async let instanceMetadataRefresh: Void = refreshInstanceMetadataIfNeeded()
                async let notificationRefresh: Void = notificationUnreadStore.reconcileActiveCount()
                async let inboxRefresh: Void = inboxUnreadStore.reconcileActiveCount()
                _ = await (
                    instanceMetadataRefresh,
                    notificationRefresh,
                    inboxRefresh
                )
            }
        }
        .onChange(of: activeSessionID) { _, _ in
            consumePendingWidgetHandoffIfNeeded()
            consumePendingSharedDraftIfNeeded()
        }
        .onChange(of: appState.currentAccount?.id) { _, _ in
            consumePendingWidgetHandoffIfNeeded()
            consumePendingSharedDraftIfNeeded()
        }
        .onChange(of: coordinator.selectedTab) { _, _ in
            updateNotificationListVisibility()
        }
        .onChange(of: coordinator.inboxFilter) { _, _ in
            updateNotificationListVisibility()
        }
        .onChange(of: coordinator.isAtRoot(.inbox)) { _, _ in
            updateNotificationListVisibility()
        }
        .task(id: notificationOpenTaskID) {
            await handlePendingNotificationOpenIfNeeded()
        }
    }

    private func refreshInstanceMetadataIfNeeded() async {
        _ = try? await InstanceMetadataStore.shared.load(apiClient: apiClient)
    }

    private var settingsContext: SettingsContext {
        SettingsContext(
            onLogout: {
                coordinator.dismissPresentedSheet()
                onLogout()
            },
            accountSessions: accountSessions,
            activeSessionID: activeSessionID,
            onSwitchAccount: { sessionID in
                coordinator.dismissPresentedSheet()
                coordinator.popAllToRoot()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onSwitchAccount(sessionID)
                }
            },
            onAddAccount: {
                coordinator.dismissPresentedSheet()
                coordinator.popAllToRoot()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    coordinator.showAddAccountLogin = true
                }
            },
            onRemoveAccount: { sessionID in
                onRemoveAccount(sessionID)
            }
        )
    }

    private var homeRootView: AnyView {
        routedView(
            AnyView(
                HomeTabRootView(
                    coordinator: coordinator,
                    apiClient: apiClient,
                    cacheClientID: activeSessionID ?? "no-active-session"
                )
            ),
            router: coordinator.homeRouter
        )
    }

    private var exploreRootView: AnyView {
        routedView(
            AnyView(ExploreTabRootView(coordinator: coordinator, apiClient: apiClient)),
            router: coordinator.exploreRouter
        )
    }

    private var inboxRootView: AnyView {
        routedView(
            AnyView(InboxView(coordinator: coordinator, apiClient: apiClient, sessionID: activeSessionID)),
            router: coordinator.inboxRouter
        )
    }

    private var meRootView: AnyView {
        routedView(
            AnyView(
                MeTabRootView(
                    apiClient: apiClient,
                    accountSessions: accountSessions,
                    activeSessionID: activeSessionID
                )
            ),
            router: coordinator.meRouter
        )
    }

    private func routeView(for route: Route, router: AppRouter) -> AnyView {
        routedView(
            AppRouteViewFactory(
                apiClient: apiClient,
                appState: appState,
                cacheManager: cacheManager
            )
            .view(for: route),
            router: router
        )
    }

    private func routedView(_ content: AnyView, router: AppRouter) -> AnyView {
        AnyView(
            content
                .modifier(SystemColorSchemeMoroTheme())
                .environment(\.activeAccountKey, activeSessionID ?? "no-active-session")
                .environment(\.mastodonAPIClient, apiClient)
                .environment(\.settingsContext, settingsContext)
                .environment(\.settingsPresentationAction) {
                    coordinator.presentSettings()
                }
                .environmentObject(appState)
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
        )
    }

    private func consumePendingSharedDraftIfNeeded() {
        guard coordinator.composeContext == nil else { return }

        guard let resolution = sharedComposeImportCoordinator.consumeNextImportableDraft(
            activeAccountID: activeAccountIDForSharedImport
        ) else {
            return
        }

        coordinator.composeContext = ComposeContextWrapper(
            context: resolution.draft.target.composeContext,
            draft: resolution.draft,
            sharedImport: resolution.sharedImport
        )

        if resolution.sharedImport == nil {
            AppFeedbackCenter.shared.showInfo(MoroL10n.MainTab.sharedContent)
        } else {
            AppFeedbackCenter.shared.showInfo(MoroL10n.MainTab.sharedContentAttachments)
        }
    }

    private func consumePendingWidgetHandoffIfNeeded() {
        guard coordinator.composeContext == nil,
            let handoff = MoroWidgetHandoffStore.consume()
        else {
            return
        }

        switch handoff.destination {
        case .home:
            coordinator.selectTab(.home)
        case .compose:
            coordinator.openCompose()
        case .search:
            coordinator.selectTab(.explore)
        case .inbox:
            coordinator.openInbox(.all)
            updateNotificationListVisibility()
        case .profile:
            coordinator.selectTab(.me)
        }
    }

    private func updateNotificationListVisibility() {
        notificationUnreadStore.setNotificationListVisible(
            coordinator.selectedTab == .inbox
                && coordinator.isAtRoot(.inbox)
        )
    }

    private func handlePendingNotificationOpenIfNeeded() async {
        guard notificationOpenTaskID.isActive, notificationOpenTaskID.isUnobstructed,
            let activeSessionID, let request = notificationUnreadStore.pendingOpenRequest,
            !Task.isCancelled
        else {
            return
        }

        // Show a usable fallback before either account switching or target lookup.
        coordinator.openPushNotification(.notifications)
        updateNotificationListVisibility()

        if let requestedSessionID = request.sessionID, requestedSessionID != activeSessionID {
            if accountSessions.contains(where: { $0.id == requestedSessionID }) {
                onSwitchAccount(requestedSessionID)
            } else {
                // A removed account's server IDs must never be resolved on another account.
                notificationUnreadStore.consumePendingNotificationOpen(id: request.id)
            }
            return
        }

        let destination = await PushNotificationResolver.resolve(request.payload, apiClient: apiClient)
        guard !Task.isCancelled, self.activeSessionID == activeSessionID,
            notificationUnreadStore.pendingOpenRequest?.id == request.id
        else { return }

        notificationUnreadStore.consumePendingNotificationOpen(id: request.id)
        // Do not pull the user away if they started navigating while resolution ran.
        guard notificationOpenTaskID.isUnobstructed, coordinator.selectedTab == .inbox,
            coordinator.inboxFilter == .all, coordinator.inboxRouter.path.isEmpty
        else { return }
        coordinator.openPushNotification(destination)
        updateNotificationListVisibility()
    }

    private func ensureInboxStreamSubscription() {
        guard let token = appState.authToken else { return }
        let streamWatcher = StreamWatcher.shared
        streamWatcher.configure(baseURL: AppEnvironment.apiBaseURL, accessToken: token)
        streamWatcher.addStream(.user)
        streamWatcher.addStream(.direct)
    }

}

private struct HomeTabRootView: View {
    @ObservedObject var coordinator: RootTabCoordinator
    @EnvironmentObject private var appState: AppState
    @Environment(\.moroTheme) private var theme

    let apiClient: MastodonAPI
    let cacheClientID: String

    private let composeButtonSize: CGFloat = 52
    private let composeButtonTabBarSpacing: CGFloat = 10

    var body: some View {
        TimelineHomeView(
            apiClient: apiClient,
            cacheClientID: cacheClientID,
            selectedTimeline: Binding(
                get: { coordinator.timelineSelection },
                set: {
                    guard coordinator.timelineSelection != $0 else { return }
                    coordinator.timelineSelection = $0
                }
            ),
            onAvatarTap: {
                coordinator.presentSettings()
            },
            onTimelineSelectionChange: { timeline in
                guard coordinator.timelineSelection != timeline else { return }
                coordinator.timelineSelection = timeline
            },
            onChromeFraction: nil,
            isActive: coordinator.selectedTab == .home && coordinator.isAtRoot(.home)
                && coordinator.presentedSheet == nil && coordinator.composeContext == nil
                && !coordinator.showAddAccountLogin,
            bottomContentInset: coordinator.tabBarHeight + composeButtonClearance
        )
        .environment(\.selectedTabScrollToTop, coordinator.selectedTabScrollToTop)
        .overlay(alignment: .bottomTrailing) {
            composeButton
                .padding(.trailing, theme.spacing.l)
                .padding(.bottom, composeButtonTabBarSpacing)
        }
    }

    private var composeButtonClearance: CGFloat {
        composeButtonSize + theme.spacing.xl
    }

    private var composeButton: some View {
        Button {
            coordinator.openCompose()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.colors.primaryForeground)
                .frame(width: composeButtonSize, height: composeButtonSize)
                .background(theme.colors.primary500, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(
            color: Color.black.opacity(theme.colorScheme == .dark ? 0.30 : 0.18),
            radius: 9,
            y: 4
        )
        .accessibilityLabel(MoroL10n.Navigation.compose)
        .accessibilityIdentifier("home.composeButton")
    }
}

private struct ExploreTabRootView: View {
    @ObservedObject var coordinator: RootTabCoordinator
    let apiClient: MastodonAPI

    var body: some View {
        SearchView(apiClient: apiClient, onEntryStateChanged: coordinator.setExploreSearchEntryActive)
            .environment(\.selectedTabScrollToTop, coordinator.selectedTabScrollToTop)
    }
}

private struct MeTabRootView: View {
    @EnvironmentObject private var appState: AppState

    let apiClient: MastodonAPI
    let accountSessions: [StoredAccountSession]
    let activeSessionID: String?

    private var currentAccount: Account? {
        appState.currentAccount
            ?? accountSessions.first(where: { $0.id == activeSessionID })?.account
            ?? accountSessions.first?.account
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let account = currentAccount {
                ProfileView(
                    account: account,
                    accountID: account.id,
                    onLogout: {},
                    apiClient: apiClient
                )
            } else {
                EmptyStateView(
                    spec: EmptyStateSpec(
                        icon: "person.crop.circle",
                        title: MoroL10n.Feedback.notLoggedIn,
                        message: MoroL10n.Timeline.emptyHomeMessage
                    )
                )
            }
        }
    }
}

private struct AddAccountLoginContainer: View {
    let onCancel: () -> Void
    let onAuthSuccess: (String, Account, URL) -> Void

    var body: some View {
        NavigationStack {
            LoginView(authService: AuthService(), onAuthSuccess: onAuthSuccess)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(MoroL10n.Common.cancel) {
                            onCancel()
                        }
                    }
                }
        }
    }
}

#Preview {
    MainTabView(
        apiClient: MastodonClient(authInterceptor: AuthInterceptor(tokenProvider: AppState())),
        onLogout: {},
        accountSessions: [],
        activeSessionID: nil,
        onSwitchAccount: { _ in },
        onRemoveAccount: { _ in },
        onAccountAuthenticated: { _, _, _ in }
    )
    .environmentObject(AppState())
    .moroTheme(MoroTheme())
}
