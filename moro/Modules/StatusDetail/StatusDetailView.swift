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

    let apiClient: MastodonAPI
    @StateObject private var postMenuActionCenter: PostMenuActionCenter
    private let threadCache: ThreadCache
    private let accountCache: AccountCache

    @MainActor
    init(
        status: Status,
        apiClient: MastodonAPI,
        threadCache: ThreadCache? = nil,
        accountCache: AccountCache? = nil
    ) {
        self.apiClient = apiClient
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
        }
        .navigationTitle(MoroL10n.StatusDetail.headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.focusedStatus.editedAt != nil {
                    Button {
                        showingEditHistorySheet = true
                        Task { await viewModel.loadStatusHistory() }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel(Text(MoroL10n.StatusDetail.editHistory))
                }

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
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(MoroL10n.ThreadReading.options)
                .accessibilityIdentifier("thread.readingOptions")

                detailHeaderMoreButton
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
            .moroSheetSurface(
                detents: [
                    .height(
                        BoostOrQuoteDialog.preferredDetentHeight(
                            quoteButtonTitle: quoteInfo.title,
                            quoteButtonSubtitle: quoteInfo.subtitle
                        ))
                ]
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
            get: { actionSurface.statusToDelete != nil },
            set: {
                if !$0 { actionSurface.clearDeleteRequest() }
            }
        )) {
            Button(MoroL10n.ComposeDrafts.deleteAndRedraftAction, role: .destructive) {
                if let status = actionSurface.statusToDelete {
                    handlers.performDelete(status, redraft: true)
                }
                actionSurface.clearDeleteRequest()
            }
            Button(MoroL10n.ComposeDrafts.deleteAction, role: .destructive) {
                if let status = actionSurface.statusToDelete {
                    handlers.performDelete(status)
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
            .moroSheetSurface(detents: [.large])
        }
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
                ForEach(ancestors) { item in
                    threadPostCard(item: item)
                        .background(highlightedStatusID == item.id ? theme.colors.surfaceSubtle : Color.clear)
                        .id(item.status.id)

                    MoroDivider()
                }

                focusedPostCard(status: viewModel.focusedStatus)
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
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
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
        }
        .scrollPosition(id: $visibleStatusID, anchor: .top)
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
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing.l)
        case .error:
            HStack(spacing: theme.spacing.m) {
                Text(MoroL10n.StatusDetail.threadLoadFailed)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer(minLength: theme.spacing.s)

                Button(MoroL10n.StatusDetail.retry) {
                    Task { await viewModel.refresh() }
                }
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.primary500)
            }
            .padding(.horizontal, theme.spacing.l)
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
            onEdit: actions.onEdit,
            onMuteUser: actions.menu?.onMuteUser,
            onBlockUser: actions.menu?.onBlockUser,
            onBlockAndReport: actions.menu?.onBlockAndReport,
            onReport: actions.menu?.onReport,
            onPin: actions.onPin,
            onDelete: actions.onDelete
        )
        .frame(width: 36, height: 44)
        .contentShape(Rectangle())
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
            currentUserID: appState.currentAccount?.id,
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
