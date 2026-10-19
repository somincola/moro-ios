//
//  ConversationDetailView.swift
//  moro
//
//  Direct-message conversation reading and replies.
//

import SwiftUI

struct ConversationDetailView: View {
    private enum Constants {
        static let bottomAnchor = "conversation_bottom_anchor"
    }

    @StateObject private var viewModel: ConversationDetailViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    @Environment(\.appRouter) private var router
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @FocusState private var isInputFocused: Bool
    @State private var lastProcessedEventID: String?
    @State private var participantsSheet: ConversationParticipantsSheetState?
    @State private var isKeyboardVisible = false
    @State private var keyboardAnimationDuration: Double = 0.25
    @State private var lastForegroundRefreshAt: Date = .distantPast
    private var streamWatcher = StreamWatcher.shared
    private let inboxUnreadStore = InboxUnreadStore.shared
    private let foregroundRefreshCooldown: TimeInterval = 12

    init(conversation: Conversation, apiClient: MastodonAPI) {
        _viewModel = StateObject(
            wrappedValue: ConversationDetailViewModel(
                conversation: conversation,
                apiClient: apiClient
            )
        )
    }

    var body: some View {
        ZStack {
            sceneCanvasColor.ignoresSafeArea()

            ScrollViewReader { proxy in
                contentView
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(MoroL10n.Conversation.navTitle)
                    .toolbar {
                        if participants.count > 1 {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(action: handleParticipantsTap) {
                                    Image(systemName: "person.2")
                                }
                                .accessibilityLabel(MoroL10n.Conversation.viewMembers)
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        inputBar(proxy: proxy)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if case .error = viewModel.loadingState, !viewModel.messages.isEmpty {
                            HStack {
                                Text(MoroL10n.Conversation.loadFailed)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                                Spacer()
                                Button(MoroL10n.Conversation.retry) {
                                    Task { await viewModel.refresh() }
                                }
                                .frame(minHeight: 44)
                            }
                            .padding(.horizontal, theme.spacing.m)
                            .background(sceneCanvasColor)
                            .accessibilityIdentifier("conversation.refreshError")
                        }
                    }
                    .task {
                        ensureDirectStreamSubscription()
                        await viewModel.loadInitial()
                        if !viewModel.conversation.unread {
                            inboxUnreadStore.markConversationRead(id: viewModel.conversation.id)
                        }
                        lastForegroundRefreshAt = Date()
                    }
                    .refreshable {
                        await viewModel.refresh()
                        lastForegroundRefreshAt = Date()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        ensureDirectStreamSubscription()
                        Task {
                            await refreshOnForegroundIfNeeded()
                        }
                    }
                    .sheet(item: $participantsSheet) { sheet in
                        ConversationParticipantsSheet(
                            title: sheet.title,
                            accounts: sheet.accounts
                        ) { account in
                            participantsSheet = nil
                            DispatchQueue.main.async {
                                router.navigate(to: .userProfile(account))
                            }
                        }
                        .moroSheetSurface(detents: sheet.detents)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: streamWatcher.latestEvent?.id) { _, newEventID in
                        guard let newEventID = newEventID,
                            newEventID != lastProcessedEventID,
                            let event = streamWatcher.latestEvent
                        else { return }

                        lastProcessedEventID = newEventID
                        viewModel.handleStreamEvent(event)
                        Task {
                            if await viewModel.markCurrentConversationReadIfNeeded() {
                                inboxUnreadStore.markConversationRead(id: viewModel.conversation.id)
                            }
                        }
                    }
                    .onChange(of: isKeyboardVisible) { _, visible in
                        guard visible else { return }
                        scheduleKeyboardScrollAdjustment(proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                        keyboardAnimationDuration = keyboardDuration(from: notification)
                        isKeyboardVisible = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                        keyboardAnimationDuration = keyboardDuration(from: notification)
                        isKeyboardVisible = false
                    }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.messages.isEmpty {
                emptyView
            } else {
                messagesListView
            }
        case .error(let error):
            if viewModel.messages.isEmpty {
                errorView(error)
            } else {
                messagesListView
            }
        }
    }

    @ViewBuilder
    private var messagesListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    let replyMessages = viewModel.replyMessages

                    ForEach(replyMessages.indexed(), id: \.element.id) { index, status in
                        let previousStatus = index > 0 ? replyMessages[index - 1] : nil
                        let nextStatus =
                            index + 1 < replyMessages.count ? replyMessages[index + 1] : nil
                        let isOutgoing = PostMoreMenuPolicy.isOwnPost(
                            status,
                            currentUserID: appState.currentAccount?.id
                        )

                        ConversationMessageRow(
                            status: status,
                            isOutgoing: isOutgoing,
                            layout: ConversationMessageLayout.resolve(
                                current: status,
                                previous: previousStatus,
                                next: nextStatus,
                                isOutgoing: isOutgoing,
                                isGroupConversation: viewModel.conversation.accounts.count > 2
                            ),
                            onAvatarTap: {
                                router.navigate(to: .userProfile(status.account))
                            }
                        )
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Constants.bottomAnchor)
                } header: {
                    if let rootStatus = viewModel.rootStatus {
                        ConversationRootStatusCard(status: rootStatus) {
                            router.navigate(to: .statusDetail(rootStatus.displayStatus))
                        }
                        .padding(.horizontal, theme.spacing.m)
                        .padding(.vertical, theme.spacing.s)
                        .background(sceneCanvasColor)
                    }
                }
            }
            .padding(.bottom, theme.spacing.s)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var participants: [Account] {
        let currentUserID = appState.currentAccount?.id
        let filtered = viewModel.conversation.accounts.filter { $0.id != currentUserID }
        return filtered.isEmpty ? viewModel.conversation.accounts : filtered
    }

    private func handleParticipantsTap() {
        guard !participants.isEmpty else { return }
        if participants.count == 1, let participant = participants.first {
            router.navigate(to: .userProfile(participant))
            return
        }

        participantsSheet = ConversationParticipantsSheetState(
            title: MoroL10n.Conversation.membersTitle,
            accounts: participants
        )
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: theme.spacing.l) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .moroScaledFont(size: 36)
                .foregroundStyle(theme.colors.textSecondary)

            Text(MoroL10n.Conversation.emptyTitle)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text(MoroL10n.Conversation.emptyMessage)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.spacing.xl)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: theme.spacing.l) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .moroScaledFont(size: 36)
                .foregroundStyle(theme.colors.error)

            Text(MoroL10n.Conversation.loadFailed)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text(error.localizedDescription)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.spacing.xl)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text(MoroL10n.Conversation.retry)
                    .font(theme.typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.primaryForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.colors.primary500))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(Constants.bottomAnchor, anchor: .bottom)
        }
        if animated {
            DispatchQueue.main.async {
                withAnimation {
                    action()
                }
            }
        } else {
            action()
        }
    }

    @ViewBuilder
    private func inputBar(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.sendErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .moroScaledFont(size: 12, weight: .semibold)
                    Text(errorMessage)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if viewModel.canRetryLastFailedSend {
                        Button(MoroL10n.Conversation.retry) {
                            sendDraftMessage(proxy: proxy, retryFailed: true)
                        }
                        .buttonStyle(.plain)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                    }
                }
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.error)
                .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(MoroL10n.Conversation.inputPlaceholder, text: $viewModel.draftMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit {
                        sendDraftMessage(proxy: proxy, retryFailed: false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    )
                    .accessibilityIdentifier("conversation.input")

                Button {
                    sendDraftMessage(proxy: proxy, retryFailed: false)
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(viewModel.canSendMessage ? theme.colors.primaryForeground : theme.colors.surfaceBase)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(viewModel.canSendMessage ? theme.colors.primaryForeground : theme.colors.surfaceBase)
                            .frame(width: 44, height: 44)
                    }
                }
                .background(
                    Circle()
                        .fill(
                            viewModel.canSendMessage ? theme.colors.primary500 : theme.colors.textSecondary
                        )
                )
                .disabled(!viewModel.canSendMessage)
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.Conversation.send)
                .accessibilityIdentifier("conversation.send")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.top, 8)
        .padding(.bottom, ConversationKeyboardMetrics.inputBottomPadding(isKeyboardVisible: isKeyboardVisible))
        .animation(.easeOut(duration: keyboardAnimationDuration), value: isKeyboardVisible)
        .background(
            sceneCanvasColor
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    MoroDivider()
                }
        )
    }

    private var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .grouped).backgroundColor(in: theme)
    }

    private func keyboardDuration(from notification: Notification) -> Double {
        ConversationKeyboardMetrics.animationDuration(from: notification.userInfo)
    }

    private func scheduleKeyboardScrollAdjustment(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            scrollToBottom(proxy, animated: false)
        }
    }

    private func ensureDirectStreamSubscription() {
        streamWatcher.ensureUserSession(accessToken: appState.authToken)
    }

    private func sendDraftMessage(proxy: ScrollViewProxy, retryFailed: Bool) {
        Task {
            let success: Bool
            if retryFailed {
                success = await viewModel.retryLastFailedSend(currentUserID: appState.currentAccount?.id)
            } else {
                success = await viewModel.sendMessage(currentUserID: appState.currentAccount?.id)
            }

            if success {
                scrollToBottom(proxy, animated: true)
                isInputFocused = true
            }
        }
    }

    private func refreshOnForegroundIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastForegroundRefreshAt) >= foregroundRefreshCooldown else { return }
        lastForegroundRefreshAt = now
        await viewModel.refresh()
    }
}

struct ConversationKeyboardMetrics {
    static func animationDuration(from userInfo: [AnyHashable: Any]?) -> Double {
        guard
            let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            duration > 0
        else {
            return 0.25
        }
        return duration
    }

    static func inputBottomPadding(isKeyboardVisible: Bool) -> CGFloat {
        isKeyboardVisible ? 3 : 6
    }
}

private struct ConversationParticipantsSheetState: Identifiable {
    let id = UUID()
    let title: String
    let accounts: [Account]

    var detents: Set<PresentationDetent> {
        let visibleRows = min(max(accounts.count, 1), 5)
        let height = 88 + CGFloat(visibleRows) * 64 + 20
        if accounts.count <= 5 {
            return [.height(height)]
        }
        return [.height(height), .large]
    }
}

private struct ConversationParticipantsSheet: View {
    let title: String
    let accounts: [Account]
    let onSelectAccount: (Account) -> Void
    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(accounts) { account in
                        Button {
                            dismiss()
                            onSelectAccount(account)
                        } label: {
                            participantRow(account)
                        }
                        .buttonStyle(.plain)

                        if account.id != accounts.last?.id {
                            Divider()
                                .padding(.leading, 72)
                                .padding(.trailing, theme.spacing.m)
                        }
                    }
                }
                .padding(.top, theme.spacing.xs)
            }
            .scrollDisabled(accounts.count <= 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func participantRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 40
            )

            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1,
                    truncationMode: .tail
                )

                Text("@\(account.acct.isEmpty ? account.username : account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .moroScaledFont(size: 11, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct ConversationRootStatusCard: View {
    let status: Status
    let onTap: () -> Void
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var messageText: String {
        ConversationMessageContent.summary(for: status)
    }

    private var supportedMediaAttachments: [Status.Attachment] {
        status.mediaAttachments.filter {
            let type = $0.type.lowercased()
            return type == "image" || type == "video" || type == "gifv"
        }
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        cardText
                        mediaThumbnail
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        cardText
                        mediaThumbnail
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(theme.colors.surfaceBase)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(MoroL10n.Conversation.navTitle))
    }

    private var cardText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(messageText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(DateFormatting.relativeString(for: status.createdAt))
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mediaThumbnail: some View {
        if !supportedMediaAttachments.isEmpty {
            NotificationMediaThumbnail(
                attachments: supportedMediaAttachments,
                isSensitive: status.sensitive,
                size: 76
            )
        }
    }

}

private struct ConversationMessageRow: View {
    let status: Status
    let isOutgoing: Bool
    let layout: ConversationMessageLayout
    let onAvatarTap: () -> Void
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appRouter) private var router
    @Environment(\.openURL) private var openURL

    private var contentElements: [ContentElement] {
        ConversationMessageContent.elements(for: status)
    }

    private var previewableMediaAttachments: [Status.Attachment] {
        status.mediaAttachments.filter {
            let type = $0.type.lowercased()
            return type == "image" || type == "video" || type == "gifv"
        }
    }

    private var unsupportedMediaAttachmentCount: Int {
        status.mediaAttachments.count - previewableMediaAttachments.count
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            if !isOutgoing, layout.reservesAvatarSpace {
                if layout.showsAvatar {
                    Button(action: onAvatarTap) {
                        MoroAvatar(
                            imageURL: status.account.avatarAnimatedURL,
                            staticImageURL: status.account.avatarURL,
                            initials: status.account.displayNameInitials, seed: status.account.placeholderSeed,
                            size: 30
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MoroL10n.Conversation.openProfile)
                } else {
                    Color.clear
                        .frame(width: 30, height: 30)
                }
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 3) {
                if layout.showsSenderName && !isOutgoing {
                    AccountDisplayNameView(
                        account: status.account,
                        typography: .captionStrong,
                        textColor: theme.colors.textSecondary
                    )
                    .padding(.leading, 2)
                }

                bubble
            }
            .frame(
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 286,
                alignment: isOutgoing ? .trailing : .leading
            )

            if !isOutgoing {
                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
        .padding(.leading, isOutgoing ? 48 : 0)
        .padding(.horizontal, theme.spacing.m)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
    }

    @ViewBuilder
    private var bubble: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xs) {
            if !contentElements.isEmpty {
                RichTextContentView(
                    elements: contentElements,
                    textColorOverride: isOutgoing ? theme.colors.primaryForeground : theme.colors.textPrimary,
                    linkColorOverride: isOutgoing ? theme.colors.primaryForeground : theme.colors.contentLink,
                    underlinesLinks: true
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("conversation.body.\(status.id)")
            }

            if !previewableMediaAttachments.isEmpty {
                ConversationCompactMediaGrid(
                    attachments: previewableMediaAttachments,
                    isSensitive: status.sensitive
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if let card = status.card {
                LinkPreviewCardView(card: card) {
                    URLHandler.shared.handleURL(card.url, router: router, systemOpenURL: openURL)
                }
                .accessibilityIdentifier("conversation.link.\(status.id)")
            }

            supportingMetadata
        }
        .padding(.horizontal, 12)
        .padding(.vertical, theme.spacing.s)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isOutgoing ? theme.colors.primary500 : theme.colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isOutgoing ? theme.colors.primary300 : theme.colors.borderSubtle,
                    lineWidth: isOutgoing ? 0 : 1
                )
        )
        .frame(
            maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 286,
            alignment: isOutgoing ? .trailing : .leading
        )
    }

    @ViewBuilder
    private var supportingMetadata: some View {
        Group {
            if unsupportedMediaAttachmentCount > 0 {
                Text(unsupportedMediaAttachmentCount == 1 ? MoroL10n.Conversation.mediaCount1 : MoroL10n.Conversation.mediaCount(unsupportedMediaAttachmentCount))
                    .font(theme.typography.caption)
                    .foregroundStyle(isOutgoing ? theme.colors.primary300 : theme.colors.textSecondary)
            }

            if status.quote != nil {
                Text(MoroL10n.Conversation.hasQuote)
                    .font(theme.typography.caption)
                    .foregroundStyle(isOutgoing ? theme.colors.primary300 : theme.colors.textSecondary)
            }

            if layout.showsTimestamp {
                Text(DateFormatting.relativeString(for: status.createdAt))
                    .font(theme.typography.caption)
                    .foregroundStyle(
                        isOutgoing
                            ? theme.colors.primaryForeground.opacity(0.68)
                            : theme.colors.textSecondary
                    )
                    .lineLimit(1)
            }
        }
    }
}

struct ConversationMessageLayout: Equatable {
    let showsSenderName: Bool
    let showsAvatar: Bool
    let reservesAvatarSpace: Bool
    let showsTimestamp: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    private static let clusterThreshold: TimeInterval = 5 * 60

    static func resolve(
        current: Status,
        previous: Status?,
        next: Status?,
        isOutgoing: Bool,
        isGroupConversation: Bool
    ) -> ConversationMessageLayout {
        let continuesFromPrevious = previous.map { belongsToSameCluster($0, current) } ?? false
        let continuesToNext = next.map { belongsToSameCluster(current, $0) } ?? false
        let startsCluster = !continuesFromPrevious
        let endsCluster = !continuesToNext

        return ConversationMessageLayout(
            showsSenderName: isGroupConversation && !isOutgoing && startsCluster,
            showsAvatar: !isOutgoing && startsCluster,
            reservesAvatarSpace: !isOutgoing,
            showsTimestamp: true,
            topPadding: startsCluster ? 12 : 4,
            bottomPadding: endsCluster ? 8 : 2
        )
    }

    private static func belongsToSameCluster(_ lhs: Status, _ rhs: Status) -> Bool {
        guard lhs.account.id == rhs.account.id else { return false }
        return abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) <= clusterThreshold
    }
}
