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
    /// Rows at least half on screen. Only these may move the read marker.
    @State private var visibleRowIDs: Set<String> = []
    @State private var isUserScrolling = false
    /// Bumped each time the reader puts a finger on the list, so a refresh can tell whether
    /// they took over the scroll position while it ran.
    @State private var userScrollGeneration = 0
    /// New or grown rows the reader hasn't seen yet; counted by the "new notifications" pill.
    @State private var unseenNewRowIDs: Set<String> = []
    /// New rows that just came into view, tinted briefly so the eye finds them.
    @State private var highlightedRowIDs: Set<String> = []
    /// Bumped to scroll the list to its newest row (only the list's reader proxy can).
    @State private var scrollToNewestRequest = 0

    private static let topAnchorID = "notifications.top"
    /// How long a refresh opened over unread notifications stays silent before the spinner
    /// shows, so a fast answer never flashes one.
    private static let lateIndicatorDelay: Duration = .milliseconds(800)
    private static let highlightDuration: Duration = .seconds(2)

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
            await openFeed()
        }
        .onChange(of: notificationUnreadStore.refreshVersion) { _, _ in
            guard isActive, notificationUnreadStore.isNotificationListVisible else { return }
            Task { await refreshFeed(userInitiated: false) }
        }
        // Rows already on screen count as seen as soon as the list is showing and has
        // something unread (a push can raise the count under a row the reader is looking at).
        .onChange(of: notificationUnreadStore.isNotificationListVisible) { _, _ in markSeenRows() }
        .onChange(of: notificationUnreadStore.activeUnreadCount) { _, _ in markSeenRows() }
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
                        Task {
                            await viewModel.loadInitial()
                            markSeenRows()
                        }
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
                        Task { await refreshFeed(userInitiated: true) }
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
                            Task { await refreshFeed(userInitiated: true) }
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
                                    Task { await refreshFeed(userInitiated: true) }
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
                            .background {
                                if highlightedRowIDs.contains(notification.id) {
                                    theme.colors.themeTint.opacity(0.10)
                                        .accessibilityIdentifier("notifications.newRowHighlight")
                                }
                            }
                            .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                                rowVisibilityChanged(notification.id, isVisible: isVisible)
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
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase != .idle
                if phase == .interacting { userScrollGeneration &+= 1 }
            }
            .onChange(of: scrollToNewestRequest) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
            }
            .refreshable {
                // Runs for a real pull and for a tab re-tap that started the same control.
                isPullRefreshing = true
                defer { isPullRefreshing = false }
                await refreshFeed(userInitiated: true)
            }
            .overlay(alignment: .top) { pullRefreshProbe }
            .overlay(alignment: .top) { newNotificationsPill }
            .animation(.snappy, value: unseenNewRowCount == 0)
            // Same as Home: re-tapping Inbox scrolls up, and at the top it refreshes the way a
            // pull does (spinner shown, rows pushed down). A re-tap during that refresh is ignored.
            .onTabReselect(.inbox) {
                guard isActive else { return }
                if !isScrolledToTop {
                    withAnimation(.snappy) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
                } else if !refreshBridge.isRefreshing {
                    MoroRefreshFeedback.armed()
                    if !refreshBridge.beginRefreshing() {
                        Task { await refreshFeed(userInitiated: true) }
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

    // MARK: - Refresh

    /// Opening the page is an automatic refresh: silent, even with unread notifications, which
    /// only send the request at once. If it is slow and the reader is still resting at the top,
    /// the spinner shows after a moment (checked when it would show, not when it started).
    private func openFeed() async {
        let prioritized = notificationUnreadStore.activeUnreadCount > 0
        let before = rowSources()
        let settled = isSettledAtTop
        let generation = userScrollGeneration
        let lateIndicator = prioritized ? Task { @MainActor in
            try? await Task.sleep(for: Self.lateIndicatorDelay)
            guard !Task.isCancelled else { return }
            revealLateIndicatorIfStillWaiting()
        } : nil
        await viewModel.activate(forceRefresh: prioritized)
        lateIndicator?.cancel()
        presentRefreshResult(before: before, settled: settled, scrollGeneration: generation)
    }

    /// A pull, a re-tap at the top, a retry button, or a signal (push, streaming) while the
    /// list is showing. Signals that land during the request are not lost: when the signal
    /// version moved while it ran, it fetches once more.
    private func refreshFeed(userInitiated: Bool) async {
        var signal = notificationUnreadStore.refreshVersion
        for _ in 0..<3 {
            let before = rowSources()
            // The reader asked for this one, so new rows show at the top unless they take over
            // the scroll position while it runs.
            let settled = userInitiated || isSettledAtTop
            let generation = userScrollGeneration
            await viewModel.refresh()
            // SwiftUI can cancel a refresh action as its content changes even while the feed
            // stays on screen; the result still has to be shown and its rows still counted.
            await Task { @MainActor in
                presentRefreshResult(before: before, settled: settled, scrollGeneration: generation)
            }.value
            let current = notificationUnreadStore.refreshVersion
            guard current != signal, isActive, notificationUnreadStore.isNotificationListVisible else {
                return
            }
            signal = current
        }
    }

    private var isSettledAtTop: Bool {
        isScrolledToTop && !isUserScrolling
    }

    private func revealLateIndicatorIfStillWaiting() {
        guard isActive, notificationUnreadStore.isNotificationListVisible, viewModel.isRefreshing,
            !viewModel.notifications.isEmpty, isSettledAtTop, !refreshBridge.isRefreshing
        else { return }
        // Starts the list's own pull to refresh, which joins the request already running.
        _ = refreshBridge.beginRefreshing()
    }

    /// Each row's notifications before a refresh, to tell new rows (and groups that grew)
    /// from ones already there.
    private func rowSources() -> [String: Set<String>] {
        Dictionary(
            filteredNotifications.map { ($0.id, Set($0.sourceNotificationIDs)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// New rows never move what the reader is looking at. Resting at the top (or after asking
    /// for the refresh), the list scrolls to them and tints them; otherwise the pill counts them.
    private func presentRefreshResult(before: [String: Set<String>], settled: Bool, scrollGeneration: Int) {
        defer { markSeenRows() }
        // A first load has nothing to compare against: all of it is simply the list.
        guard !before.isEmpty else { return }
        let newRowIDs = filteredNotifications.compactMap { row -> String? in
            guard let old = before[row.id] else { return row.id }
            return Set(row.sourceNotificationIDs).isSubset(of: old) ? nil : row.id
        }
        guard !newRowIDs.isEmpty else { return }

        let readerTookOver = scrollGeneration != userScrollGeneration || isUserScrolling
        if settled, !readerTookOver, isActive {
            highlight(newRowIDs)
            scrollToNewestRequest &+= 1
        } else {
            // A group that grew while on screen has been seen already.
            let onScreen = newRowIDs.filter(visibleRowIDs.contains)
            highlight(onScreen)
            unseenNewRowIDs.formUnion(newRowIDs.filter { !visibleRowIDs.contains($0) })
        }
    }

    private func highlight(_ rowIDs: [String]) {
        guard !rowIDs.isEmpty else { return }
        highlightedRowIDs.formUnion(rowIDs)
        Task { @MainActor in
            try? await Task.sleep(for: Self.highlightDuration)
            withAnimation(.easeOut(duration: 0.6)) { highlightedRowIDs.subtract(rowIDs) }
        }
    }

    // MARK: - Read Boundary

    private func rowVisibilityChanged(_ rowID: String, isVisible: Bool) {
        guard isVisible else {
            visibleRowIDs.remove(rowID)
            return
        }
        visibleRowIDs.insert(rowID)
        if unseenNewRowIDs.remove(rowID) != nil {
            highlight([rowID])
        }
        markSeenRows()
    }

    private var unseenNewRowCount: Int {
        guard !unseenNewRowIDs.isEmpty else { return 0 }
        return filteredNotifications.reduce(0) { $0 + (unseenNewRowIDs.contains($1.id) ? 1 : 0) }
    }

    /// Moves the read marker to the newest notification on screen: downloaded or merged rows
    /// the reader hasn't seen keep the badge. Only the "All" list of the current account,
    /// while it is showing, may move it, so "Mentions" never clears other kinds.
    private func markSeenRows() {
        guard isActive, selectedFilter == .all, viewModel.scope == .everything,
            notificationUnreadStore.isNotificationListVisible,
            notificationUnreadStore.activeUnreadCount > 0,
            viewModel.hasCurrentHead
        else { return }
        let viewModel = viewModel
        let newestSeen = filteredNotifications
            .filter { visibleRowIDs.contains($0.id) }
            .compactMap { viewModel.newestSourceID(of: $0) }
            .reduce(nil) { (newest: String?, id: String) -> String? in
                guard let newest else { return id }
                return viewModel.isNotification(id, newerThan: newest) == true ? id : newest
            }
        guard let newestSeen else { return }
        let sessionID = notificationUnreadStore.activeSessionID
        let remainingUnread = viewModel.loadedNotificationCount(newerThan: newestSeen)
        let store = notificationUnreadStore
        Task { @MainActor in
            guard sessionID == store.activeSessionID else { return }
            await store.markActiveNotificationsSeen(
                through: newestSeen,
                remainingUnread: remainingUnread,
                isNewer: { viewModel.isNotification($0, newerThan: $1) }
            )
        }
    }

    @ViewBuilder
    private var newNotificationsPill: some View {
        let count = unseenNewRowCount
        if isActive, count > 0 {
            Button {
                scrollToNewestRequest &+= 1
            } label: {
                MoroNoticePill(icon: "arrow.up", text: MoroL10n.Notifications.newNotifications(count))
            }
            .buttonStyle(.plain)
            .padding(.top, theme.spacing.s)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("notifications.newNotifications")
        }
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
