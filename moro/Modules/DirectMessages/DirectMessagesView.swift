//
//  DirectMessagesView.swift
//  moro
//
//  Direct-message conversations list view.
//

import SwiftUI

enum DirectMessagesPresentation {
    case standalone
    case inbox
}

struct DirectMessagesView: View {
    @StateObject private var viewModel: DirectMessagesViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var lastProcessedEventID: String?
    @State private var navigatingConversationID: String?
    @State private var showingNewConversationSheet = false
    @State private var lastForegroundRefreshAt: Date = .distantPast
    private let apiClient: MastodonAPI
    private let showsDismissButton: Bool
    private let presentation: DirectMessagesPresentation
    private let isActive: Bool
    private let newConversationRequest: Int
    private let inboxUnreadStore = InboxUnreadStore.shared
    private var streamWatcher = StreamWatcher.shared
    private let loadMoreThreshold = 6
    private let foregroundRefreshCooldown: TimeInterval = 15

    init(
        apiClient: MastodonAPI,
        showsDismissButton: Bool = true,
        presentation: DirectMessagesPresentation = .standalone,
        isActive: Bool = true,
        newConversationRequest: Int = 0
    ) {
        self.apiClient = apiClient
        self.showsDismissButton = showsDismissButton
        self.presentation = presentation
        self.isActive = isActive
        self.newConversationRequest = newConversationRequest
        _viewModel = StateObject(wrappedValue: DirectMessagesViewModel(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if presentation == .inbox {
                messagesContent
            } else {
                PageScaffold(
                    title: MoroL10n.DirectMessages.title,
                    trailing: {
                        HStack(spacing: 18) {
                            newConversationButton

                            if showsDismissButton {
                                MoroNavigationControlButton(kind: .close) {
                                    dismiss()
                                }
                            }
                        }
                    }
                ) {
                    messagesContent
                }
            }
        }
        .sheet(isPresented: $showingNewConversationSheet) {
            NewConversationSheetView(
                apiClient: apiClient,
                recentAccounts: recentAccounts,
                currentUserID: appState.currentAccount?.id
            ) { account in
                openConversation(with: account)
            }
            .moroSheetSurface(detents: [.large])
        }
        .task(id: isActive) {
            guard isActive else { return }
            ensureDirectStreamSubscription()
            await viewModel.loadInitial()
            await inboxUnreadStore.reconcileActiveCount()
            lastForegroundRefreshAt = Date()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard isActive, newPhase == .active else { return }
            ensureDirectStreamSubscription()
            Task {
                await refreshOnForegroundIfNeeded()
            }
        }
        .onChange(of: streamWatcher.latestEvent?.id) { _, newEventID in
            guard isActive,
                let newEventID = newEventID,
                newEventID != lastProcessedEventID,
                let event = streamWatcher.latestEvent
            else { return }

            lastProcessedEventID = newEventID
            viewModel.handleStreamEvent(event)
        }
        .onChange(of: newConversationRequest) { _, _ in
            guard presentation == .inbox, isActive else { return }
            showNewConversation()
        }
    }

    private var messagesContent: some View {
        ContentStateContainer(state: contentState) {
            conversationList
        }
    }

    private var newConversationButton: some View {
        Button {
            showNewConversation()
        } label: {
            Image(systemName: "plus.message")
                .moroScaledFont(size: 18, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.DirectMessages.newMessage)
        .accessibilityIdentifier("directMessages.newConversation")
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.conversations.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
        }
        if viewModel.conversations.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.DirectMessages.errorLoadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.DirectMessages.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    }
                ))
        }
        if viewModel.conversations.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "bubble.left.and.bubble.right",
                    title: MoroL10n.DirectMessages.emptyTitle,
                    message: MoroL10n.DirectMessages.emptyMessage,
                    actionTitle: MoroL10n.DirectMessages.emptyAction,
                    action: {
                        showNewConversation()
                    }
                ))
        }
        return .loaded
    }

    private var recentAccounts: [Account] {
        let currentUserID = appState.currentAccount?.id
        var seen = Set<String>()
        var unique: [Account] = []

        for conversation in viewModel.conversations {
            for account in conversation.accounts where account.id != currentUserID {
                if seen.insert(account.id).inserted {
                    unique.append(account)
                }
            }
        }

        return unique
    }

    @ViewBuilder
    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let transientErrorMessage = viewModel.transientErrorMessage {
                    HStack(alignment: .top, spacing: theme.spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.error)
                            .padding(.top, 2)
                        Text(transientErrorMessage)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(theme.spacing.s)
                    .background(theme.colors.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.colors.borderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
                }

                ForEach(Array(viewModel.conversations.enumerated()), id: \.element.id) {
                    index,
                    conversation in
                    let isNearBottom = viewModel.conversations.count - index <= loadMoreThreshold
                    DirectMessageConversationRow(
                        conversation: conversation,
                        currentUserID: appState.currentAccount?.id,
                        isNavigating: navigatingConversationID == conversation.id
                    ) {
                        Task {
                            navigatingConversationID = conversation.id
                            if await viewModel.markAsReadIfNeeded(conversation) {
                                inboxUnreadStore.markConversationRead(id: conversation.id)
                            }
                            let resolvedConversation = viewModel.conversations.first {
                                $0.id == conversation.id
                            } ?? conversation
                            router.navigate(to: .conversationDetail(resolvedConversation))
                            navigatingConversationID = nil
                        }
                    } onMarkAsRead: {
                        Task {
                            if await viewModel.markAsReadIfNeeded(conversation) {
                                inboxUnreadStore.markConversationRead(id: conversation.id)
                            }
                        }
                    } onDelete: {
                        Task {
                            if await viewModel.delete(conversation) {
                                inboxUnreadStore.removeConversation(id: conversation.id)
                            }
                        }
                    }

                    MoroDivider()

                    if isNearBottom {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                }

                PaginationFooter(
                    isLoadingMore: isLoadingMore,
                    didFail: viewModel.loadMoreFailed,
                    onRetry: { Task { await viewModel.loadMore() } }
                )
            }
        }
        .refreshable {
            await viewModel.refresh()
            await inboxUnreadStore.reconcileActiveCount()
        }
    }

    private func ensureDirectStreamSubscription() {
        if streamWatcher.hasActiveConnection {
            streamWatcher.addStream(.direct)
            return
        }

        guard let token = appState.authToken else { return }
        streamWatcher.configure(baseURL: AppEnvironment.apiBaseURL, accessToken: token)
        streamWatcher.watch(streams: [.user, .direct])
    }

    private func openConversation(with account: Account) {
        if let existingConversation = viewModel.conversation(withParticipantID: account.id) {
            router.navigate(to: .conversationDetail(existingConversation))
            return
        }

        let draftConversation = Conversation.draft(participants: [account])
        router.navigate(to: .conversationDetail(draftConversation))
    }

    private func showNewConversation() {
        showingNewConversationSheet = true
    }

    private func refreshOnForegroundIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastForegroundRefreshAt) >= foregroundRefreshCooldown else { return }
        lastForegroundRefreshAt = now
        await viewModel.refresh()
        await inboxUnreadStore.reconcileActiveCount()
    }
}

private struct DirectMessageConversationRow: View {
    let conversation: Conversation
    let currentUserID: String?
    let isNavigating: Bool
    let onTap: () -> Void
    let onMarkAsRead: () -> Void
    let onDelete: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var participants: [Account] {
        let filtered = conversation.accounts.filter { $0.id != currentUserID }
        return filtered.isEmpty ? conversation.accounts : filtered
    }

    private var primaryAccount: Account? { participants.first }
    private var isUnread: Bool { conversation.unread }

    private var titleText: String {
        let names = participants.map { $0.displayNameFormatted }
        if names.isEmpty {
            return MoroL10n.DirectMessages.conversation
        }
        return names.prefix(2).joined(separator: ", ")
    }

    private var metadataText: String {
        guard !participants.isEmpty else { return MoroL10n.DirectMessages.conversation }

        if participants.count == 1, let account = primaryAccount {
            let handle = account.acct.isEmpty ? account.username : account.acct
            return "@\(handle)"
        }

        let handles = participants
            .prefix(2)
            .map { account in
                let handle = account.acct.isEmpty ? account.username : account.acct
                return "@\(handle)"
            }
            .joined(separator: "、")

        if participants.count > 2 {
            return MoroL10n.DirectMessages.groupConversation(participants.count, handles)
        }

        return handles
    }

    private var previewText: String {
        guard let lastStatus = conversation.lastStatus else { return MoroL10n.DirectMessages.noContent }
        let sender = lastStatus.account.displayNameFormatted
        let resolvedBody = ConversationMessageContent.summary(for: lastStatus)

        if participants.count > 1 {
            return "\(sender)：\(resolvedBody)"
        }
        return resolvedBody
    }

    private var timeText: String {
        if let createdAt = conversation.lastStatus?.createdAt {
            return DateFormatting.relativeString(for: createdAt)
        }
        if let updatedAt = conversation.updatedAt {
            return DateFormatting.relativeString(for: updatedAt)
        }
        return ""
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                if let account = primaryAccount {
                    MoroAvatar(
                        imageURL: account.avatarAnimatedURL,
                        staticImageURL: account.avatarURL,
                        initials: account.displayNameInitials,
                        size: 44
                    )
                } else {
                    Circle()
                        .fill(theme.colors.textSecondary.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person")
                                .moroScaledFont(size: 14, weight: .medium)
                                .foregroundStyle(theme.colors.textSecondary)
                        )
                }

                VStack(alignment: .leading, spacing: 5) {
                    headerLine

                    Text(metadataText)
                        .font(theme.typography.caption)
                        .foregroundStyle(isUnread ? theme.colors.textSecondary : theme.colors.textTertiary)
                        .lineLimit(1)

                    Text(previewText)
                        .font(theme.typography.body)
                        .foregroundStyle(isUnread ? theme.colors.textPrimary : theme.colors.textSecondary)
                        .fontWeight(isUnread ? .medium : .regular)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(unreadBackground)
            .overlay(alignment: .leading) {
                if isUnread {
                    Capsule(style: .continuous)
                        .fill(theme.colors.contentLink)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUnread ? MoroL10n.DirectMessages.accessibilityLabelUnread(titleText, previewText) : MoroL10n.DirectMessages.accessibilityLabel(titleText, previewText))
        .accessibilityHint(MoroL10n.DirectMessages.accessibilityOpenDetail)
        .accessibilityIdentifier("directMessages.conversation.\(conversation.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label(MoroL10n.DirectMessages.swipeDelete, systemImage: "trash")
            }

            if isUnread {
                Button(action: onMarkAsRead) {
                    Label(MoroL10n.DirectMessages.swipeRead, systemImage: "eye")
                }
                .tint(theme.colors.primary500)
            }
        }
    }

    private var unreadBackground: Color {
        guard isUnread else { return .clear }
        switch theme.colorScheme {
        case .light:
            return theme.colors.surfaceSubtle
        case .dark:
            return theme.colors.surfaceElevated
        @unknown default:
            return theme.colors.surfaceSubtle
        }
    }

    @ViewBuilder
    private var headerLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                titleLabel(lineLimit: 2)
                trailingMeta
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                titleLabel(lineLimit: 1)

                Spacer()

                trailingMeta
            }
        }
    }

    @ViewBuilder
    private func titleLabel(lineLimit: Int) -> some View {
        if participants.count == 1, let account = primaryAccount {
            AccountDisplayNameView(
                account: account,
                typography: isUnread ? .subtitle : .bodyStrong,
                textColor: theme.colors.textPrimary,
                lineLimit: lineLimit
            )
        } else {
            Text(titleText)
                .font(theme.typography.subtitle)
                .fontWeight(isUnread ? .bold : .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(lineLimit)
        }
    }

    @ViewBuilder
    private var trailingMeta: some View {
        if isNavigating {
            ProgressView()
                .scaleEffect(0.75)
        } else {
            HStack(spacing: 6) {
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(theme.typography.caption)
                        .foregroundStyle(isUnread ? theme.colors.textPrimary : theme.colors.textTertiary)
                        .fontWeight(isUnread ? .semibold : .regular)
                        .lineLimit(1)
                }

                if isUnread {
                    Circle()
                        .fill(theme.colors.contentLink)
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)

    return DirectMessagesView(apiClient: client)
        .environmentObject(appState)
        .moroTheme(MoroTheme())
}
