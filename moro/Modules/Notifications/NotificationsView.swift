//
//  NotificationsView.swift
//  moro
//
//  Notifications list view with pull-to-refresh and infinite scroll.
//

import SwiftUI

enum NotificationsPresentation {
    case standalone
    case inbox
}

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all
    case mentions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return MoroL10n.Notifications.filterAll
        case .mentions:
            return MoroL10n.Notifications.filterMentions
        }
    }

    func matches(_ item: NotificationDisplayItem) -> Bool {
        switch self {
        case .all:
            return true
        case .mentions:
            return item.kind.descriptor.filterCategory == .mentions
        }
    }

    var serverScope: MastodonNotificationScope {
        switch self {
        case .all: return .everything
        case .mentions: return .mentions
        }
    }
}

struct NotificationsView: View {
    @StateObject private var models: NotificationFeedStore
    @State private var localSelectedFilter: NotificationFilter = .all
    private let presentation: NotificationsPresentation
    private let isActive: Bool
    private let selectedFilterOverride: Binding<NotificationFilter>?

    init(
        apiClient: MastodonAPI,
        sessionID: String? = nil,
        presentation: NotificationsPresentation = .standalone,
        isActive: Bool = true,
        selectedFilter: Binding<NotificationFilter>? = nil
    ) {
        self.presentation = presentation
        self.isActive = isActive
        self.selectedFilterOverride = selectedFilter
        _models = StateObject(wrappedValue: NotificationFeedStore(apiClient: apiClient, sessionID: sessionID))
    }

    var body: some View {
        NotificationFeedView(
            viewModel: models.model(for: selectedFilterBinding.wrappedValue.serverScope),
            selectedFilter: selectedFilterBinding,
            presentation: presentation,
            isActive: isActive
        )
        .id(selectedFilterBinding.wrappedValue.serverScope)
    }

    private var selectedFilterBinding: Binding<NotificationFilter> {
        selectedFilterOverride ?? $localSelectedFilter
    }
}

private struct NotificationFeedView: View {
    @ObservedObject var viewModel: NotificationsViewModel
    @Binding var selectedFilter: NotificationFilter
    let presentation: NotificationsPresentation
    let isActive: Bool

    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @ObservedObject private var notificationUnreadStore = NotificationUnreadStore.shared
    @State private var actorsSheet: NotificationActorsSheetState?
    @State private var scrollPositionID: String?
    @State private var paginationFooterVisible = false
    @State private var isScrolledToTop = true
    @State private var refreshBridge = ScrollViewRefreshBridge()
    @State private var isPullRefreshing = false

    private static let topAnchorID = "notifications.top"

    var body: some View {
        Group {
            if presentation == .inbox {
                notificationsContent
            } else {
                PageScaffold(
                    title: MoroL10n.Notifications.title,
                    titleSize: 24,
                    trailing: { notificationSettingsButton }
                ) {
                    notificationsContent
                }
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            await activateAndMarkRead()
        }
        .onChange(of: notificationUnreadStore.refreshVersion) { _, _ in
            guard isActive, notificationUnreadStore.isNotificationListVisible else { return }
            Task { await refreshAndMarkRead() }
        }
        .onChange(of: canResumePagination) { _, ready in
            if ready { loadMoreFromVisibleFooter() }
        }
        .sheet(item: $actorsSheet) { item in
            NotificationActorsSheet(
                title: item.title,
                accounts: item.accounts
            ) { account in
                router.navigate(to: .userProfile(account))
            }
            .moroSheetSurface(detents: [.medium, .large])
        }
    }

    private var notificationsContent: some View {
        ContentStateContainer(state: contentState) {
            notificationsList
        }
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.notifications.isEmpty {
            switch viewModel.loadingState {
            case .idle, .loading, .refreshing: return .loading(.list)
            default: break
            }
        }
        if viewModel.notifications.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Notifications.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Notifications.retryAction,
                    action: {
                        Task { await loadInitialAndMarkRead() }
                    }
                ))
        }
        // An empty local filter is not the end of the server's notification list.
        if filteredNotifications.isEmpty, viewModel.hasMore {
            return .loaded
        }
        if viewModel.notifications.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "bell.badge",
                    title: MoroL10n.Notifications.emptyTitle,
                    message: MoroL10n.Notifications.emptyMessage,
                    actionTitle: MoroL10n.Notifications.refreshAction,
                    action: {
                        Task { await refreshAndMarkRead() }
                    }
                ))
        }
        if filteredNotifications.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "line.3.horizontal.decrease.circle",
                    title: MoroL10n.Notifications.filteredEmptyTitle,
                    message: selectedFilter == .all
                        ? MoroL10n.Notifications.filteredEmptyNoContent
                        : MoroL10n.Notifications.filteredEmptyMessage,
                    actionTitle: selectedFilter == .all ? MoroL10n.Notifications.refreshAction : MoroL10n.Notifications.viewAll,
                    action: {
                        if selectedFilter == .all {
                            Task { await refreshAndMarkRead() }
                        } else {
                            selectedFilter = .all
                        }
                    }
                ))
        }
        return .loaded
    }

    private var filteredNotifications: [NotificationDisplayItem] {
        viewModel.notifications.filter { selectedFilter.matches($0) }
    }

    private var canResumePagination: Bool {
        guard case .loaded = viewModel.loadingState else { return false }
        return viewModel.hasMore && !viewModel.loadMoreFailed && !viewModel.refreshFailed
            && !filteredNotifications.isEmpty
    }

    private func loadMoreFromVisibleFooter() {
        guard isActive, paginationFooterVisible, canResumePagination else { return }
        Task { await viewModel.loadMore() }
    }

    @ViewBuilder
    private var notificationsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The top marker sits outside the scroll-target layout, so `scrollPositionID`
                // keeps tracking real rows (refresh still holds the reader's row in place).
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchorID)
                        .background(ScrollViewRefreshBridgeAnchor(bridge: refreshBridge))

                    LazyVStack(spacing: 0) {
                        if viewModel.refreshFailed {
                            HStack {
                                Label(MoroL10n.Notifications.loadFailed, systemImage: "wifi.exclamationmark")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                                Spacer()
                                Button(MoroL10n.Notifications.retryAction) {
                                    Task { await refreshAndMarkRead() }
                                }
                                .frame(minHeight: 44)
                            }
                            .padding(.horizontal, theme.spacing.m)
                            .accessibilityIdentifier("notifications.refreshRetry")
                        }

                        if filteredNotifications.isEmpty, viewModel.hasMore {
                            EmptyStateView(spec: EmptyStateSpec(
                                icon: "line.3.horizontal.decrease.circle",
                                title: MoroL10n.Notifications.filteredEmptyTitle,
                                message: MoroL10n.Notifications.moreAvailable,
                                actionTitle: viewModel.loadMoreFailed
                                    ? MoroL10n.Notifications.retryAction
                                    : MoroL10n.Notifications.loadMore,
                                action: { Task { await viewModel.loadMore() } }
                            ))
                            .disabled(isLoadingMore)
                            .padding(.vertical, theme.spacing.xl)
                            .accessibilityIdentifier("notifications.loadOlderEmptyState")
                        }

                        ForEach(filteredNotifications.indexed(), id: \.element.id) {
                            index, notification in
                            let isNearBottom = filteredNotifications.count - index <= 3

                            VStack(spacing: 0) {
                                NotificationRow(
                                    notification: notification,
                                    onAvatarTap: {
                                        if let account = notification.presentationAccount {
                                            router.navigate(to: .userProfile(account))
                                        }
                                    },
                                    onStatusTap: { status in
                                        let targetStatus = status.displayStatus
                                        Task {
                                            await viewModel.traceAndWarmStatusDetailOpen(
                                                for: targetStatus,
                                                source: notification.kind == .quotedUpdate
                                                    ? "notification-quoted-update"
                                                    : "notification-main"
                                            )
                                        }
                                        router.navigate(to: .statusDetail(targetStatus))
                                    },
                                    onAccountTap: {
                                        if let account = notification.presentationAccount {
                                            router.navigate(to: .userProfile(account))
                                        }
                                    },
                                    onActorsTap: {
                                        actorsSheet = NotificationActorsSheetState(
                                            id: notification.id,
                                            title: actorsSheetTitle(for: notification),
                                            accounts: notification.accounts
                                        )
                                    },
                                    onAcceptFollowRequest: {
                                        Task { await viewModel.acceptFollowRequest(notification) }
                                    },
                                    onRejectFollowRequest: {
                                        Task { await viewModel.rejectFollowRequest(notification) }
                                    },
                                    isAcceptingFollowRequest: viewModel.isAcceptingFollowRequest(id: notification.id),
                                    isRejectingFollowRequest: viewModel.isRejectingFollowRequest(id: notification.id)
                                )
                                .onAppear {
                                    let prefetchWindowSize = 8
                                    guard index < prefetchWindowSize else { return }
                                    guard let status = notification.status else { return }
                                    Task {
                                        await viewModel.prefetchStatusAndQuoteIfNeeded(for: status.displayStatus)
                                    }
                                }

                                if index < filteredNotifications.count - 1 {
                                    Rectangle()
                                        .fill(theme.colors.borderSubtle)
                                        .frame(height: 1)
                                }

                                if isNearBottom {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            Task { await viewModel.loadMore() }
                                        }
                                }
                            }
                            .id(notification.id)
                        }

                        PaginationFooter(
                            isLoadingMore: isLoadingMore,
                            didFail: viewModel.loadMoreFailed,
                            onRetry: { Task { await viewModel.loadMore() } }
                        )
                        // Restored/grouped rows can already fill less than one screen
                        // while refresh is running. Resume when ready even if the tail
                        // never disappeared and therefore will not get another onAppear.
                        Color.clear.frame(height: 1)
                            .onAppear {
                                paginationFooterVisible = true
                                loadMoreFromVisibleFooter()
                            }
                            .onDisappear { paginationFooterVisible = false }
                    }
                    .scrollTargetLayout()
                    .moroReadableColumn()
                }
            }
            .scrollPosition(id: $scrollPositionID, anchor: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isScrolledToTop = atTop
            }
            .refreshable {
                // Runs for a real pull and for a tab re-tap that started the same control.
                isPullRefreshing = true
                defer { isPullRefreshing = false }
                await refreshAndMarkRead()
            }
            .overlay(alignment: .top) { pullRefreshProbe }
            // Same as Home: re-tapping Inbox scrolls up, and at the top it refreshes the way a
            // pull does (spinner shown, rows pushed down). A re-tap during that refresh is ignored.
            .onTabReselect(.inbox) {
                guard isActive else { return }
                if !isScrolledToTop {
                    withAnimation(.snappy) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
                } else if !refreshBridge.isRefreshing {
                    MoroRefreshFeedback.armed()
                    if !refreshBridge.beginRefreshing() {
                        Task { await refreshAndMarkRead() }
                    }
                }
            }
        }
    }

    /// UI tests cannot see the system refresh control or the rows it pushes down, so DEBUG
    /// builds launched by them expose whether the pull-to-refresh action is running.
    @ViewBuilder
    private var pullRefreshProbe: some View {
        #if DEBUG
        if isPullRefreshing, ProcessInfo.processInfo.environment["UITEST_USE_FULL_APP"] == "1" {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("pull refresh running")
                .accessibilityIdentifier("notifications.pullRefreshRunning")
        }
        #endif
    }

    private func loadInitialAndMarkRead() async {
        let sessionID = notificationUnreadStore.activeSessionID
        let newestNotificationID = await viewModel.loadInitial()
        await markReadIfVisible(through: newestNotificationID, sessionID: sessionID)
    }

    private func activateAndMarkRead() async {
        let sessionID = notificationUnreadStore.activeSessionID
        let newestNotificationID = await viewModel.activate(
            forceRefresh: notificationUnreadStore.activeUnreadCount > 0)
        await markReadIfVisible(through: newestNotificationID, sessionID: sessionID)
    }

    private func refreshAndMarkRead() async {
        let sessionID = notificationUnreadStore.activeSessionID
        let newestNotificationID = await viewModel.refresh()
        // A refresh action can be cancelled during SwiftUI updates even while
        // its feed stays visible. Recheck visibility and account before marking it.
        await Task { @MainActor in
            await markReadIfVisible(through: newestNotificationID, sessionID: sessionID)
        }.value
    }

    private func markReadIfVisible(through notificationID: String?, sessionID: String?) async {
        // A filtered page must not mark unrelated, unseen notifications as read.
        guard !Task.isCancelled, isActive, selectedFilter == .all,
            sessionID == notificationUnreadStore.activeSessionID,
            viewModel.scope == .everything, notificationUnreadStore.isNotificationListVisible,
            let notificationID
        else {
            return
        }
        await notificationUnreadStore.markActiveNotificationsRead(through: notificationID)
    }

    private var notificationSettingsButton: some View {
        Button {
            router.navigate(to: .notificationSettings)
        } label: {
            Image(systemName: "gearshape")
                .moroScaledFont(size: 18, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.NotificationSettings.title)
        .accessibilityIdentifier("notifications.settings")
    }

    private func actorsSheetTitle(for notification: NotificationDisplayItem) -> String {
        switch notification.type {
        case "favourite":
            return MoroL10n.Notifications.actorListFavouriters
        case "reblog":
            return MoroL10n.Notifications.actorListRebloggers
        case "follow":
            return MoroL10n.Notifications.actorListFollowers
        case "follow_request":
            return MoroL10n.Notifications.actorListFollowRequesters
        default:
            return MoroL10n.Notifications.actorListRelated
        }
    }

}

private struct NotificationActorsSheetState: Identifiable {
    let id: String
    let title: String
    let accounts: [Account]
}

private struct NotificationActorsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    let title: String
    let accounts: [Account]
    let onSelect: (Account) -> Void

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onSelect(account)
                    }
                } label: {
                    HStack(spacing: 12) {
                        MoroAvatar(
                            imageURL: account.avatarAnimatedURL,
                            staticImageURL: account.avatarURL,
                            initials: account.displayNameInitials, seed: account.placeholderSeed,
                            size: 40
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            AccountDisplayNameView(
                                account: account,
                                typography: .subtitle,
                                textColor: theme.colors.textPrimary
                            )
                            Text("@\(account.acct)")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .moroReadableListMargins()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)
    
    return NotificationsView(apiClient: client)
        .environmentObject(appState)
        .moroTheme(MoroTheme())
}
