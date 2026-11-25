//
//  StatusDetailView.swift
//  moro
//
//  Displays a single status with its thread context (ancestors and descendants).
//

import SwiftUI

struct StatusDetailView: View {
    @StateObject private var viewModel: StatusDetailViewModel
    @StateObject private var interactionService: PostInteractionService
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState
    @StateObject private var actionSurface = PostActionSurfaceCenter()
    @State private var showingEditHistorySheet = false
    @State private var visibleStatusID: String?
    @State private var readingState = ThreadReadingState()
    @State private var highlightedStatusID: String?
    /// iPhone Duo Home: the panel's actions go in the system side bar, not the title row.
    @Environment(\.threadSplitPanelBar) private var panelBar
    @State private var panelBarOwner = UUID()

    let apiClient: MastodonAPI
    @StateObject private var postMenuActionCenter: PostMenuActionCenter
    private let threadCache: ThreadCache
    private let accountCache: AccountCache
    /// Shown in a column next to the timeline rather than as a pushed page: the title and
    /// actions go in the view's own header instead of the shared navigation bar.
    private let isEmbedded: Bool
    /// Embedded: a control at the start of the title row (the panel's close button).
    private let embeddedLeadingAction: AnyView?

    @MainActor
    init(
        status: Status,
        apiClient: MastodonAPI,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil,
        isEmbedded: Bool = false,
        embeddedLeadingAction: AnyView? = nil
    ) {
        self.apiClient = apiClient
        self.isEmbedded = isEmbedded
        self.embeddedLeadingAction = embeddedLeadingAction
        _postMenuActionCenter = StateObject(
            wrappedValue: PostMenuActionCenter(apiClient: apiClient))
        // Use provided caches or fall back to shared instance
        self.threadCache = threadCache ?? CacheManager.shared.threadCache
        self.accountCache = accountCache ?? CacheManager.shared.accountCache
        _visibleStatusID = State(initialValue: status.id)
        _viewModel = StateObject(wrappedValue: StatusDetailViewModel(
            status: status,
            apiClient: apiClient,
            threadCache: threadCache,
            accountCache: accountCache
        ))
        _interactionService = StateObject(wrappedValue: PostInteractionService(apiClient: apiClient))
    }

    var body: some View {
        ZStack {
            sceneCanvasColor
                .ignoresSafeArea()

            conversationView
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isEmbedded { embeddedHeader }
                }
        }
        .modifier(PageNavigationTitle(isEnabled: !isEmbedded))
        .onChange(of: panelBarToken, initial: true) { _, _ in publishPanelBarActions() }
        .onAppear { publishPanelBarActions() }
        .onDisappear { panelBar?.withdraw(owner: panelBarOwner) }
        .toolbar {
            if !isEmbedded {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    headerActions
                }
            }
        }
        .task {
            await viewModel.loadThread()
        }
        .sheet(isPresented: $showingEditHistorySheet) {
            StatusEditHistorySheetView(
                state: viewModel.historyLoadingState,
                items: viewModel.statusHistory,
                onRetry: {
                    Task { await viewModel.loadStatusHistory(forceReload: true) }
                }
            )
            .moroSheetSurface(detents: [.medium, .large])
        }
        .sheet(item: $actionSurface.boostDialogStatus) { status in
            let quoteInfo = QuoteButtonInfo.forStatus(
                status,
                currentUserID: appState.currentAccount?.id
            )
            BoostOrQuoteDialog(
                status: status,
                isBoosted: status.reblogged,
                canQuote: quoteInfo.isEnabled,
                quoteButtonTitle: quoteInfo.title,
                quoteButtonSubtitle: quoteInfo.subtitle,
                onBoost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onUnboost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onQuote: {
                    actionSurface.startQuote(from: status)
                },
                onDismiss: {
                    actionSurface.dismissBoostDialog()
                }
            )
        }
        .alert(item: Binding(
            get: { interactionService.activeAlert },
            set: { _ in interactionService.activeAlert = nil }
        )) { alert in
            switch alert {
            case .confirmBoost(let didConfirm):
                return Alert(
                    title: Text(MoroL10n.StatusDetail.confirmBoostTitle),
                    message: Text(MoroL10n.StatusDetail.confirmBoostMessage),
                    primaryButton: .default(Text(MoroL10n.StatusDetail.boost)) {
                        didConfirm(true)
                    },
                    secondaryButton: .cancel(Text(MoroL10n.StatusDetail.cancel)) {
                        didConfirm(false)
                    }
                )
            }
        }
        .alert(MoroL10n.ComposeDrafts.deleteConfirmTitle, isPresented: Binding(
            get: { actionSurface.deleteRequest != nil },
            set: {
                if !$0 { actionSurface.clearDeleteRequest() }
            }
        )) {
            Button(
                actionSurface.deleteRequest?.shouldRedraft == true
                    ? MoroL10n.ComposeDrafts.deleteAndRedraftAction
                    : MoroL10n.ComposeDrafts.deleteAction,
                role: .destructive
            ) {
                if let request = actionSurface.deleteRequest {
                    handlers.performDelete(request.status, redraft: request.shouldRedraft)
                }
                actionSurface.clearDeleteRequest()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {
                actionSurface.clearDeleteRequest()
            }
        } message: {
            Text(MoroL10n.ComposeDrafts.deleteConfirmMessage)
        }
        .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
            ComposeView(
                context: wrapper.context,
                apiClient: apiClient,
                currentUserID: appState.currentAccount?.id,
                initialDraft: wrapper.draft,
                onDismiss: { actionSurface.composeContext = nil }
            ) { publishedStatus in
                Task {
                    await viewModel.refresh()
                }
            }
            .environmentObject(appState)
        }
        .sheet(item: $actionSurface.reportStatus) { status in
            ReportView(
                status: status,
                apiClient: apiClient,
                onDismiss: { actionSurface.dismissReport() }
            )
        }
    }

    /// The panel hands its actions to the system bar (see `ThreadSplitPanelBar`).
    private var raisesActionsToPanelBar: Bool {
        isEmbedded && panelBar != nil
    }

    /// What the raised actions show; they are handed over again whenever it changes.
    private struct PanelBarToken: Equatable {
        let status: Status
        let hasReadingControls: Bool
        let authorOnly: Bool
        let hasCollapsed: Bool
        let isMutingUser: Bool?
        let isBlockingUser: Bool?
    }

    private var panelBarToken: PanelBarToken? {
        guard raisesActionsToPanelBar else { return nil }
        let menu = postActions(for: viewModel.focusedStatus).menu
        return PanelBarToken(
            status: viewModel.focusedStatus,
            hasReadingControls: hasThreadReadingControls,
            authorOnly: readingState.authorOnly,
            hasCollapsed: !readingState.collapsedIDs.isEmpty,
            isMutingUser: menu?.isMutingUser,
            isBlockingUser: menu?.isBlockingUser)
    }

    private var hasThreadReadingControls: Bool {
        if readingState.authorOnly || !readingState.collapsedIDs.isEmpty {
            return true
        }
        if let items = viewModel.threadModel?.threadItems, items.count > 1 {
            return true
        }
        return viewModel.focusedStatus.repliesCount > 0
            || viewModel.focusedStatus.inReplyToID != nil
    }

    private func publishPanelBarActions() {
        guard raisesActionsToPanelBar, let panelBar else { return }
        panelBar.publish(
            ThreadSplitPanelBar.Actions(
                editHistory: viewModel.focusedStatus.editedAt != nil ? AnyView(editHistoryButton) : nil,
                readingOptions: hasThreadReadingControls ? AnyView(readingOptionsMenu) : nil,
                more: AnyView(detailHeaderMoreButton)),
            owner: panelBarOwner)
    }

    /// Edit history, reading options and more: in the navigation bar, or in the embedded header.
    @ViewBuilder
    private var headerActions: some View {
        if viewModel.focusedStatus.editedAt != nil {
            editHistoryButton
        }
        if hasThreadReadingControls {
            readingOptionsMenu
        }
        detailHeaderMoreButton
    }

    private var editHistoryButton: some View {
        Button {
            showingEditHistorySheet = true
            Task { await viewModel.loadStatusHistory() }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel(Text(MoroL10n.StatusDetail.editHistory))
    }

    private var readingOptionsMenu: some View {
        Menu {
            Button {
                readingState.setAuthorOnly(!readingState.authorOnly)
                jumpToPost(viewModel.focusedStatus.id)
            } label: {
                Label(MoroL10n.ThreadReading.authorOnly, systemImage: readingState.authorOnly ? "checkmark" : "person")
            }
            .accessibilityIdentifier("thread.authorOnly")
            Button(MoroL10n.ThreadReading.returnToPost) { jumpToPost(viewModel.focusedStatus.id) }
                .accessibilityIdentifier("thread.returnToPost")
            if !readingState.collapsedIDs.isEmpty {
                Button(MoroL10n.ThreadReading.expandAll) { readingState.expandAll() }
            }
        } label: {
            Image(systemName: "text.book.closed")
                .font(.system(size: 16, weight: .regular))
        }
        .accessibilityLabel(MoroL10n.ThreadReading.options)
        .accessibilityIdentifier("thread.readingOptions")
    }

    /// The column header used when embedded: the same title and actions as the navigation bar.
    private var embeddedHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                if let embeddedLeadingAction, !raisesActionsToPanelBar {
                    embeddedLeadingAction
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                Text(MoroL10n.StatusDetail.headerTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !raisesActionsToPanelBar {
                    headerActions
                        .foregroundStyle(theme.colors.textPrimary)
                }
            }
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .frame(height: 44)
            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(height: 0.5)
        }
        .background(sceneCanvasColor)
    }

    private var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .content).backgroundColor(in: theme)
    }
    
    // MARK: - Thread List View

    @ViewBuilder
    private var conversationView: some View {
        let threadItems = viewModel.threadModel?.threadItems ?? []
        let focusedIndex = threadItems.firstIndex { $0.status.id == viewModel.focusedStatus.id }
        let ancestors: [ThreadItem] = focusedIndex.map {
            Array(threadItems.prefix($0))
        } ?? []
        let descendants: [ThreadItem] = focusedIndex.map {
            Array(threadItems.dropFirst($0 + 1))
        } ?? []
        let rows = ThreadReadingProjection(items: descendants, authorID: viewModel.focusedStatus.account.id, state: readingState).rows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, item in
                    threadPostCard(item: item)
                        .background(alignment: .topLeading) {
                            ancestorThreadLine(drawsAbove: index > 0, drawsBelow: true)
                        }
                        .background(highlightedStatusID == item.id ? theme.colors.surfaceSubtle : Color.clear)
                        .id(item.status.id)
                }

                focusedPostCard(status: viewModel.focusedStatus)
                    .background(alignment: .topLeading) {
                        if !ancestors.isEmpty {
                            ancestorThreadLine(drawsAbove: true, drawsBelow: false)
                        }
                    }
                    .id(viewModel.focusedStatus.id)

                if rows.isEmpty {
                    MoroDivider()
                } else {
                    ThreadGroupDivider()
                        .padding(.vertical, theme.spacing.s)
                }
                if readingState.authorOnly {
                    Text(MoroL10n.ThreadReading.authorOnlyHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(theme.spacing.m)
                        .accessibilityIdentifier("thread.authorOnlyHint")
                }

                if viewModel.threadModel == nil {
                    threadLoadingState
                } else {
                    ForEach(rows.indexed(), id: \.element.id) { index, row in
                        let isLast = index == rows.count - 1
                        let endsGroup = isLast || rows[index + 1].item.replyGroup != row.item.replyGroup
                        ThreadDiscussionRow(
                            row: row,
                            endsGroup: endsGroup,
                            isCollapsed: readingState.collapsedIDs.contains(row.id),
                            apiClient: apiClient,
                            accountCache: accountCache,
                            actions: postActions(for: row.item.status),
                            onToggleBranch: { readingState.toggleBranch(row.id) }
                        )
                        .background(highlightedStatusID == row.id ? theme.colors.surfaceSubtle : Color.clear)
                        .id(row.id)
                    }
                }
            }
            .scrollTargetLayout()
            .moroReadableColumn()
        }
        .scrollPosition(id: $visibleStatusID, anchor: .top)
        .modifier(PostEmojiScrollPlayback())
        // Pull for new replies. The loaded thread stays on screen while it reloads, so a
        // failure keeps it and says so instead of falling back to the inline retry row.
        .refreshable {
            await viewModel.refresh()
            if case .error = viewModel.loadingState, viewModel.threadModel != nil {
                MoroRefreshFeedback.deliver(.failed, failureMessage: MoroL10n.StatusDetail.threadLoadFailed)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusDetailQuickReplyBar(
                targetUsername: viewModel.focusedStatus.account.username,
                currentAccount: appState.currentAccount,
                onReply: { postActions(for: viewModel.focusedStatus).onReply?() }
            )
        }
    }

    /// Subtle vertical thread stem connecting ancestor posts into the focused post.
    private func ancestorThreadLine(drawsAbove: Bool, drawsBelow: Bool) -> some View {
        GeometryReader { proxy in
            let x = theme.spacing.contentHorizontalInset + 22
            let avatarTop = theme.spacing.timelineVertical
            let avatarBottom = avatarTop + 44
            let strokeColor = theme.colors.textTertiary.opacity(0.32)

            Path { path in
                if drawsAbove {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: max(0, avatarTop - 3)))
                }
                if drawsBelow {
                    path.move(to: CGPoint(x: x, y: avatarBottom + 4))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func jumpToPost(_ id: String) {
        readingState.expandAll()
        highlightedStatusID = id
        withAnimation { visibleStatusID = id }
    }

    @ViewBuilder
    private var threadLoadingState: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            HStack {
                Spacer(minLength: 0)
                MoroMascotView(expression: .thinking, size: 34)
                Spacer(minLength: 0)
            }
            .padding(.vertical, theme.spacing.l)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(MoroL10n.Search.loading))
        case .error:
            MoroInlineNoticeBanner(
                message: MoroL10n.StatusDetail.threadLoadFailed,
                tone: .error,
                actionTitle: MoroL10n.StatusDetail.retry,
                action: { Task { await viewModel.refresh() } }
            )
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .padding(.vertical, theme.spacing.m)
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var detailHeaderMoreButton: some View {
        let actions = postActions(for: viewModel.focusedStatus)
        StatusMoreButton(
            status: viewModel.focusedStatus,
            isOwnPost: actions.isOwnPost,
            isMutingUser: actions.menu?.isMutingUser,
            isBlockingUser: actions.menu?.isBlockingUser,
            onShare: actions.menu?.onShare,
            onCopyLink: actions.menu?.onCopyLink,
            onCopyText: actions.menu?.onCopyText,
            onOpenInBrowser: actions.menu?.onOpenInBrowser,
            onQuote: actions.onQuote,
            onEdit: actions.onEdit,
            onMuteUser: actions.menu?.onMuteUser,
            onBlockUser: actions.menu?.onBlockUser,
            onBlockAndReport: actions.menu?.onBlockAndReport,
            onReport: actions.menu?.onReport,
            onPin: actions.onPin,
            onDeleteAndRedraft: actions.onDeleteAndRedraft,
            onDelete: actions.onDelete
        )
    }

    private func postActions(for status: Status) -> PostActions {
        handlers.buildPostActions(
            for: status,
            onPollVote: { pollID, choices in
                await viewModel.votePoll(pollID: pollID, choices: choices)
            }
        )
    }

    @ViewBuilder
    private func focusedPostCard(status: Status) -> some View {
        DetailPostCard(
            status: status,
            translationAPIClient: apiClient,
            actions: postActions(for: status)
        )
    }

    @ViewBuilder
    private func threadPostCard(item: ThreadItem) -> some View {
        ThreadPostRow(
            status: item.status,
            translationAPIClient: apiClient,
            accountCache: accountCache,
            actions: postActions(for: item.status)
        )
    }

    // MARK: - Post Interaction Handlers

    private var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService,
            actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter,
            apiClient: apiClient,
            appState: appState,
            router: router,
            onRemoveStatus: { statusID in
                if statusID == viewModel.focusedStatus.id {
                    router.pop()
                } else {
                    viewModel.removeStatus(id: statusID)
                }
            }
        )
    }
}

// MARK: - Thread Post Row

/// A full post row used for inline context and replies in detail view.
struct ThreadPostRow: View {
    let status: Status
    var translationAPIClient: MastodonAPI? = nil
    var accountCache: AccountCache? = nil
    var actions: PostActions = .empty

    var body: some View {
        PostCard(
            status: status,
            translationAPIClient: translationAPIClient,
            actions: actions,
            threadDisplayMode: .hideReplyHeader,
            accountCache: accountCache
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actions.onTap?()
        }
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "moro",
        acct: "moro@mastodon.social",
        displayName: "Moro User",
        note: "Building a friendly Mastodon client",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200
    )

    let sampleStatus = Status(
        id: "1",
        content: "This is a sample status with some content. #Moro #iOS #SwiftUI",
        createdAt: Date().addingTimeInterval(-3600),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 12,
        reblogsCount: 3,
        repliesCount: 1,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )

    let state = AppState()
    let interceptor = AuthInterceptor(tokenProvider: state)
    let client = MastodonClient(authInterceptor: interceptor)
    
    NavigationStack {
        StatusDetailView(status: sampleStatus, apiClient: client)
    }
    .environmentObject(state)
    .moroTheme(MoroTheme())
}

/// Floating Liquid Glass quick-reply trigger pinned to the bottom of StatusDetailView.
private struct StatusDetailQuickReplyBar: View {
    let targetUsername: String
    let currentAccount: Account?
    let onReply: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var promptText: String {
        "\(MoroL10n.StatusAction.reply) @\(targetUsername)"
    }

    var body: some View {
        Button(action: onReply) {
            pillSurface
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.top, theme.spacing.s)
        .padding(.bottom, theme.spacing.s)
        .moroReadableColumn()
        .accessibilityLabel(promptText)
        .accessibilityIdentifier("statusDetail.quickReplyBar")
    }

    @ViewBuilder
    private var pillSurface: some View {
        let content = HStack(spacing: theme.spacing.s) {
            if let currentAccount {
                MoroAvatar(
                    imageURL: currentAccount.avatarAnimatedURL,
                    staticImageURL: currentAccount.avatarURL,
                    initials: currentAccount.displayNameInitials,
                    seed: currentAccount.placeholderSeed,
                    size: 26
                )
            }
            Text(promptText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "arrowshape.turn.up.left")
                .moroScaledFont(size: 14, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.leading, currentAccount != nil ? 10 : 16)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
        .contentShape(Capsule())

        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(theme.colors.surfaceElevated, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(theme.colors.borderSubtle, lineWidth: 1)
                }
        }
    }
}

/// Pushed pages title the navigation bar; an embedded column leaves the bar to its host.
private struct PageNavigationTitle: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(MoroL10n.StatusDetail.headerTitle)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
