//
//  ListsView.swift
//  moro
//
//  List management and list timeline entry page.
//

import SwiftUI
import UIKit

struct ListsView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.activeAccountKey) private var activeAccountKey
    @StateObject private var viewModel: ListsViewModel
    @ObservedObject private var settings = AppSettings.shared
    private let apiClient: MastodonAPI

    @State private var showEditor = false
    @State private var editorDraft = ListEditorDraft.new
    @State private var selectedListForMembers: MastodonList?

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
        _viewModel = StateObject(wrappedValue: ListsViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            contentList
        }
        .navigationTitle(MoroL10n.Lists.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorDraft = .new
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .moroScaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.Lists.newList)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showEditor) {
            ListEditorSheet(
                draft: $editorDraft,
                isSaving: viewModel.isMutating,
                onCancel: {
                    showEditor = false
                },
                onSave: {
                    await saveEditor()
                }
            )
        }
        .sheet(item: $selectedListForMembers) { list in
            ListMembersView(list: list, apiClient: apiClient)
        }
    }

    private var contentState: ContentState {
        if viewModel.lists.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
        }
        if viewModel.lists.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Lists.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Lists.retry,
                    action: { Task { await viewModel.refresh() } }
                )
            )
        }
        if viewModel.lists.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "list.bullet.rectangle",
                    title: MoroL10n.Lists.emptyTitle,
                    message: MoroL10n.Lists.emptyMessage,
                    actionTitle: MoroL10n.Lists.newList,
                    action: {
                        editorDraft = .new
                        showEditor = true
                    }
                )
            )
        }
        return .loaded
    }

    @ViewBuilder
    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.s) {
                if let transientErrorMessage = viewModel.transientErrorMessage {
                    HStack(alignment: .top, spacing: theme.spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.error)
                            .padding(.top, 2)
                        Text(transientErrorMessage)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                    }
                    .padding(theme.spacing.s)
                    .background(theme.colors.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.colors.borderSubtle, lineWidth: 1)
                    )
                }

                ForEach(viewModel.lists) { list in
                    NavigationLink {
                        ListTimelineView(list: list, apiClient: apiClient)
                    } label: {
                        listRow(list)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            selectedListForMembers = list
                        } label: {
                            Label(MoroL10n.Lists.members, systemImage: "person.2")
                        }
                        .tint(theme.colors.primary600)

                        Button {
                            editorDraft = .from(list)
                            showEditor = true
                        } label: {
                            Label(MoroL10n.Lists.rename, systemImage: "pencil")
                        }
                        .tint(theme.colors.primary500)

                        Button(role: .destructive) {
                            Task {
                                if await viewModel.deleteList(list) {
                                    // A deleted list can't stay pinned to Home.
                                    settings.unpinTimelineList(
                                        id: list.id, accountKey: activeAccountKey)
                                }
                            }
                        } label: {
                            Label(MoroL10n.Lists.delete, systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
        }
    }

    @ViewBuilder
    private func listRow(_ list: MastodonList) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .moroScaledFont(size: 14, weight: .semibold)
                .foregroundStyle(theme.colors.primary500)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.colors.primary50)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(theme.typography.subtitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(repliesPolicyLabel(for: list.repliesPolicy))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()

            pinToHomeButton(list)

            Image(systemName: "chevron.right")
                .moroScaledFont(size: 11, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }

    /// Pin/unpin this list into the home timeline switcher.
    @ViewBuilder
    private func pinToHomeButton(_ list: MastodonList) -> some View {
        let isPinned = settings.isTimelineListPinned(list.id, accountKey: activeAccountKey)

        Button {
            handlePinTap(list, isPinned: isPinned)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .moroScaledFont(size: 13, weight: .semibold)
                .foregroundStyle(
                    isPinned ? theme.colors.primary500 : theme.colors.textTertiary
                )
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isPinned ? MoroL10n.PinnedTimeline.unpin : MoroL10n.PinnedTimeline.pin
        )
    }

    private func handlePinTap(_ list: MastodonList, isPinned: Bool) {
        if isPinned {
            settings.unpinTimelineList(id: list.id, accountKey: activeAccountKey)
            AppFeedbackCenter.shared.showSuccess(MoroL10n.PinnedTimeline.unpinned)
        } else {
            settings.pinTimelineList(
                id: list.id, title: list.title, accountKey: activeAccountKey)
            AppFeedbackCenter.shared.showSuccess(MoroL10n.PinnedTimeline.pinned)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func repliesPolicyLabel(for policy: MastodonList.RepliesPolicy?) -> String {
        switch policy {
        case .some(.followed):
            return MoroL10n.Lists.replyPolicyFollowed
        case .some(.list):
            return MoroL10n.Lists.replyPolicyList
        case .some(.none):
            return MoroL10n.Lists.replyPolicyNone
        case nil:
            return MoroL10n.Lists.replyPolicyDefault
        }
    }

    private func saveEditor() async {
        let title = editorDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let success: Bool
        if let editingList = editorDraft.editingList {
            success = await viewModel.updateList(
                editingList,
                title: title,
                repliesPolicy: editorDraft.repliesPolicy
            )
            if success {
                // Keep a pinned home tab's title in sync after a rename.
                settings.renamePinnedTimelineList(
                    id: editingList.id, title: title, accountKey: activeAccountKey)
            }
        } else {
            success = await viewModel.createList(
                title: title,
                repliesPolicy: editorDraft.repliesPolicy
            )
        }

        if success {
            showEditor = false
        }
    }
}

private struct ListEditorDraft {
    var editingList: MastodonList?
    var title: String
    var repliesPolicy: MastodonList.RepliesPolicy

    static let new = ListEditorDraft(
        editingList: nil,
        title: "",
        repliesPolicy: .list
    )

    static func from(_ list: MastodonList) -> ListEditorDraft {
        ListEditorDraft(
            editingList: list,
            title: list.title,
            repliesPolicy: list.repliesPolicy ?? .list
        )
    }

    var isEditing: Bool { editingList != nil }
}

private struct ListEditorSheet: View {
    @Environment(\.moroTheme) private var theme
    @Binding var draft: ListEditorDraft

    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(MoroL10n.Lists.formNameSection) {
                    TextField(MoroL10n.Lists.formNamePlaceholder, text: $draft.title)
                }

                Section(MoroL10n.Lists.formReplySection) {
                    Picker(MoroL10n.Lists.formReplyLabel, selection: $draft.repliesPolicy) {
                        Text(MoroL10n.Lists.formReplyFollowed).tag(MastodonList.RepliesPolicy.followed)
                        Text(MoroL10n.Lists.formReplyList).tag(MastodonList.RepliesPolicy.list)
                        Text(MoroL10n.Lists.formReplyNone).tag(MastodonList.RepliesPolicy.none)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(draft.isEditing ? MoroL10n.Lists.formEditTitle : MoroL10n.Lists.newList)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(MoroL10n.Lists.formCancel) { onCancel() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(draft.isEditing ? MoroL10n.Lists.formSave : MoroL10n.Lists.formCreate) {
                        Task { await onSave() }
                    }
                    .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        theme.colors.textPrimary.opacity(0.12).ignoresSafeArea()
                        ProgressView()
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .moroTheme(MoroTheme())
    }
}

struct ListTimelineView: View {
    let list: MastodonList
    @StateObject private var viewModel: ListTimelineViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState

    init(list: MastodonList, apiClient: MastodonAPI) {
        self.list = list
        _viewModel = StateObject(
            wrappedValue: ListTimelineViewModel(apiClient: apiClient, listID: list.id)
        )
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            timelineList
        }
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitial()
        }
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.statuses.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.timeline)
        }
        if viewModel.statuses.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Lists.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Lists.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    }
                )
            )
        }
        if viewModel.statuses.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "list.bullet.rectangle",
                    title: MoroL10n.Lists.timelineEmptyTitle,
                    message: MoroL10n.Lists.timelineEmptyMessage,
                    actionTitle: MoroL10n.Lists.timelineRefresh,
                    action: {
                        Task { await viewModel.refresh() }
                    }
                )
            )
        }
        return .loaded
    }

    @ViewBuilder
    private var timelineList: some View {
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

                ForEach(Array(viewModel.statuses.enumerated()), id: \.element.id) { index, status in
                    ListTimelineStatusRow(
                        status: status,
                        isOwnPost: PostMoreMenuPolicy.isOwnPost(status, currentUserID: appState.currentAccount?.id),
                        onTapDetail: {
                            router.navigate(to: .statusDetail(status.displayStatus))
                        },
                        onNavigate: { route in
                            router.navigate(to: route)
                        }
                    )

                    MoroDivider()

                    if viewModel.statuses.count - index <= 3 {
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
        }
    }
}

private struct ListTimelineStatusRow: View {
    let status: Status
    let isOwnPost: Bool
    let onTapDetail: () -> Void
    let onNavigate: (Route) -> Void

    var body: some View {
        let nav = PostNavigationActionCenter.handlers(
            for: status,
            detailStatus: status.displayStatus,
            navigate: onNavigate
        )

        PostCard(
            status: status,
            actions: PostActions(
                navigation: nav,
                isOwnPost: isOwnPost
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTapDetail()
        }
    }
}
