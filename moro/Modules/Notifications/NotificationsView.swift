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
    case interactions
    case follows
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return MoroL10n.Notifications.filterAll
        case .interactions:
            return MoroL10n.Notifications.filterInteractions
        case .mentions:
            return MoroL10n.Notifications.filterMentions
        case .follows:
            return MoroL10n.Notifications.filterFollows
        case .updates:
            return MoroL10n.Notifications.filterUpdates
        }
    }

    func matches(_ item: NotificationDisplayItem) -> Bool {
        let category = item.kind.descriptor.filterCategory
        switch self {
        case .all:
            return true
        case .interactions:
            return category == .interactions
        case .mentions:
            return category == .mentions
        case .follows:
            return category == .follows
        case .updates:
            return category == .updates
        }
    }
}

enum NotificationFilterMenuStyle {
    case labeled
    case icon
}

struct NotificationsView: View {
    @StateObject private var viewModel: NotificationsViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @ObservedObject private var notificationUnreadStore = NotificationUnreadStore.shared
    @State private var actorsSheet: NotificationActorsSheetState?
    @State private var localSelectedFilter: NotificationFilter = .all
    @State private var scrollPositionID: String?
    private let presentation: NotificationsPresentation
    private let isActive: Bool
    private let selectedFilterOverride: Binding<NotificationFilter>?

    init(
        apiClient: MastodonAPI,
        presentation: NotificationsPresentation = .standalone,
        isActive: Bool = true,
        selectedFilter: Binding<NotificationFilter>? = nil
    ) {
        self.presentation = presentation
        self.isActive = isActive
        self.selectedFilterOverride = selectedFilter
        _viewModel = StateObject(wrappedValue: NotificationsViewModel(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if presentation == .inbox {
                notificationsContent
            } else {
                PageScaffold(
                    title: MoroL10n.Notifications.title,
                    titleSize: 24,
                    trailing: { notificationFilterMenu }
                ) {
                    notificationsContent
                }
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            await loadInitialAndMarkRead()
        }
        .onChange(of: notificationUnreadStore.refreshVersion) { _, _ in
            guard isActive, notificationUnreadStore.isNotificationListVisible else { return }
            Task { await refreshAndMarkRead() }
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
        if viewModel.notifications.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
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
            if viewModel.filterInsight.hidesEverything {
                return .empty(
                    EmptyStateSpec(
                        icon: "line.3.horizontal.decrease.circle",
                        title: MoroL10n.Notifications.hiddenByPolicy,
                        message: hiddenByAppPolicyMessage,
                        actionTitle: MoroL10n.Notifications.refreshAction,
                        action: {
                            Task { await refreshAndMarkRead() }
                        }
                    ))
            }
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
                            selectedFilterBinding.wrappedValue = .all
                        }
                    }
                ))
        }
        return .loaded
    }

    private var filteredNotifications: [NotificationDisplayItem] {
        viewModel.notifications.filter { selectedFilter.matches($0) }
    }

    @ViewBuilder
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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

                ForEach(Array(filteredNotifications.enumerated()), id: \.element.id) {
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
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPositionID, anchor: .top)
        .refreshable {
            await refreshAndMarkRead()
        }
    }

    private func loadInitialAndMarkRead() async {
        let newestNotificationID = await viewModel.loadInitial()
        await markReadIfVisible(through: newestNotificationID)
    }

    private func refreshAndMarkRead() async {
        let newestNotificationID = await viewModel.refresh()
        await markReadIfVisible(through: newestNotificationID)
    }

    private func markReadIfVisible(through notificationID: String?) async {
        guard notificationUnreadStore.isNotificationListVisible,
            let notificationID
        else {
            return
        }
        await notificationUnreadStore.markActiveNotificationsRead(through: notificationID)
    }

    private var notificationFilterMenu: some View {
        NotificationFilterMenu(
            selectedFilter: selectedFilterBinding,
            style: .labeled
        )
    }

    private var selectedFilterBinding: Binding<NotificationFilter> {
        selectedFilterOverride ?? $localSelectedFilter
    }

    private var selectedFilter: NotificationFilter {
        selectedFilterBinding.wrappedValue
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

    private var hiddenByAppPolicyMessage: String {
        let insight = viewModel.filterInsight
        var reasons: [String] = []
        if insight.hiddenByTypeCount > 0 {
            reasons.append(MoroL10n.Notifications.policyHiddenByType(insight.hiddenByTypeCount))
        }
        if insight.hiddenByPolicyCount > 0 {
            reasons.append(MoroL10n.Notifications.policyHiddenBySource(insight.hiddenByPolicyCount))
        }

        let reasonText = reasons.isEmpty ? MoroL10n.Notifications.policyDefaultMessage : reasons.joined(separator: "，")
        return MoroL10n.Notifications.policySettingsHint(reasonText)
    }
}

struct NotificationFilterMenu: View {
    @Binding var selectedFilter: NotificationFilter
    let style: NotificationFilterMenuStyle

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Menu {
            Picker(MoroL10n.Notifications.accessibilityFilter, selection: $selectedFilter) {
                ForEach(NotificationFilter.allCases) { filter in
                    Text(filter.title)
                        .tag(filter)
                }
            }
        } label: {
            switch style {
            case .labeled:
                HStack(spacing: 5) {
                    Text(selectedFilter.title)
                        .foregroundStyle(theme.colors.textPrimary)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)

                    Image(systemName: "chevron.down")
                        .moroScaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(theme.colors.surfaceSubtle)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                }
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .frame(minHeight: 44)
                .contentShape(Rectangle())

            case .icon:
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .moroScaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(
                            selectedFilter == .all
                                ? theme.colors.textPrimary
                                : theme.colors.primary500
                        )
                        .frame(width: 44, height: 44)

                    if selectedFilter != .all {
                        Circle()
                            .fill(theme.colors.primary500)
                            .frame(width: 7, height: 7)
                            .offset(x: -7, y: 7)
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selectedFilter)
        .accessibilityLabel(MoroL10n.Notifications.accessibilityFilter)
        .accessibilityValue(selectedFilter.title)
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
                            initials: account.displayNameInitials,
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
