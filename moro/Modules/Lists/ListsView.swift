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
    /// iPhone Duo's inner display held landscape: the lists stay on the left and the open list
    /// (or the editor) fills the right. Elsewhere a list pushes and the editor is a sheet.
    @State private var isWide = false
    @State private var selectedListID: String?
    /// Wide: the editor is open in the right column, with cancel and save in the system bar.
    @State private var isEditingInline = false

    private let listsColumnWidth: CGFloat = 360

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
        _viewModel = StateObject(wrappedValue: ListsViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            if isWide {
                wideLayout
            } else {
                contentList
            }
        }
        .background(theme.colors.surfaceBase)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= ThreadSplitLayout.splitMinimumWidth
        } action: { wide in
            isWide = wide
        }
        .navigationTitle(MoroL10n.Lists.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            await viewModel.loadInitial()
            selectFirstListIfNeeded()
        }
        .onChange(of: viewModel.lists.map(\.id)) { _, _ in
            selectFirstListIfNeeded()
        }
        .onChange(of: isWide) { _, wide in
            // Narrow again mid-edit: carry the draft over to the sheet.
            if !wide, isEditingInline {
                isEditingInline = false
                showEditor = true
            }
            selectFirstListIfNeeded()
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

    // MARK: - Toolbar

    /// In the system bar (iPhone Duo's side bar when held landscape): new list, or while the
    /// editor is open beside the lists, cancel and save.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isWide && isEditingInline {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: cancelInlineEditor) {
                    Label(MoroL10n.Lists.formCancel, systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isMutating)
                .accessibilityIdentifier("lists.editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveEditor() }
                } label: {
                    Label(
                        editorDraft.isEditing ? MoroL10n.Lists.formSave : MoroL10n.Lists.formCreate,
                        systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveEditor)
                .accessibilityIdentifier("lists.editor.save")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: startNewList) {
                    Label(MoroL10n.Lists.newList, systemImage: "plus")
                }
                .accessibilityIdentifier("lists.new")
            }
        }
    }

    private var canSaveEditor: Bool {
        !viewModel.isMutating
            && !editorDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startNewList() {
        editorDraft = .new
        if isWide {
            withAnimation(.snappy(duration: 0.25)) { isEditingInline = true }
        } else {
            showEditor = true
        }
    }

    private func startEditing(_ list: MastodonList) {
        editorDraft = .from(list)
        if isWide {
            selectedListID = list.id
            withAnimation(.snappy(duration: 0.25)) { isEditingInline = true }
        } else {
            showEditor = true
        }
    }

    private func cancelInlineEditor() {
        withAnimation(.snappy(duration: 0.25)) { isEditingInline = false }
    }

    private func selectFirstListIfNeeded() {
        guard isWide else { return }
        if let selectedListID, viewModel.lists.contains(where: { $0.id == selectedListID }) { return }
        selectedListID = viewModel.lists.first?.id
    }

    private var selectedList: MastodonList? {
        viewModel.lists.first { $0.id == selectedListID }
    }

    // MARK: - Content

    private var contentState: ContentState {
        // Creating the first list happens beside the (empty) lists column.
        if isWide, isEditingInline { return .loaded }
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
                    action: startNewList
                )
            )
        }
        return .loaded
    }

    /// Lists on the left at a fixed width; the open list, or the editor, on the right.
    private var wideLayout: some View {
        HStack(spacing: 0) {
            contentList
                .frame(width: listsColumnWidth)
            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(width: 0.5)
                .ignoresSafeArea(edges: .vertical)
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if isEditingInline {
            // No title row of its own: the left column's highlighted row already says what's
            // being made, and a white band over the grouped form read as a stray strip.
            ListEditorForm(draft: $editorDraft, isSaving: viewModel.isMutating)
            .transition(.opacity)
            .accessibilityIdentifier("lists.editor.inline")
        } else if let list = selectedList {
            VStack(spacing: 0) {
                columnHeader(list.title, subtitle: repliesPolicyLabel(for: list.repliesPolicy))
                ListTimelineView(
                    list: list, apiClient: apiClient, cacheClientID: activeAccountKey,
                    setsNavigationTitle: false)
                    .id(activeAccountKey + ":" + list.id)
            }
            .accessibilityIdentifier("lists.detail")
        } else {
            Color.clear
        }
    }

    /// The right column's title row, level with the system bar's title on the left.
    private func columnHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .frame(height: 44)
            MoroDivider()
        }
        .background(theme.colors.surfaceBase)
    }

    @ViewBuilder
    private var contentList: some View {
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
                    .padding(.horizontal, theme.spacing.contentHorizontalInset)
                    .padding(.vertical, theme.spacing.s)
                    MoroDivider()
                }

                // Creating beside the lists: where the new list will land, so the left
                // column says what's happening even before there are any lists.
                if isWide, isEditingInline, !editorDraft.isEditing {
                    draftRow
                    MoroDivider(leadingInset: theme.spacing.contentHorizontalInset + 44)
                }

                ForEach(viewModel.lists) { list in
                    listEntry(list)
                    MoroDivider(leadingInset: theme.spacing.contentHorizontalInset + 44)
                }
            }
            .moroReadableColumn()
        }
        .background(theme.colors.surfaceBase)
    }

    /// Wide, a row selects the list for the right column; otherwise it pushes the list.
    @ViewBuilder
    private func listEntry(_ list: MastodonList) -> some View {
        Group {
            if isWide {
                Button {
                    isEditingInline = false
                    selectedListID = list.id
                } label: {
                    listRow(list, isSelected: !isEditingInline && selectedListID == list.id)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    ListTimelineView(list: list, apiClient: apiClient, cacheClientID: activeAccountKey)
                        .id(activeAccountKey + ":" + list.id)
                } label: {
                    listRow(list, isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu { listActions(list) }
        .accessibilityIdentifier("lists.row.\(list.id)")
    }

    @ViewBuilder
    private func listActions(_ list: MastodonList) -> some View {
        Button {
            selectedListForMembers = list
        } label: {
            Label(MoroL10n.Lists.members, systemImage: "person.2")
        }
        Button {
            startEditing(list)
        } label: {
            Label(MoroL10n.Lists.rename, systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            Task {
                if await viewModel.deleteList(list) {
                    // A deleted list can't stay pinned to Home.
                    settings.unpinTimelineList(id: list.id, accountKey: activeAccountKey)
                    if selectedListID == list.id { selectedListID = nil }
                    selectFirstListIfNeeded()
                }
            }
        } label: {
            Label(MoroL10n.Lists.delete, systemImage: "trash")
        }
    }

    private var draftRow: some View {
        let name = editorDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 12) {
            Image(systemName: "plus")
                .moroScaledFont(size: 15, weight: .semibold)
                .foregroundStyle(theme.colors.themeTint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(theme.colors.themeTint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? MoroL10n.Lists.newList : name)
                    .font(theme.typography.body.weight(.semibold))
                    .foregroundStyle(name.isEmpty ? theme.colors.textSecondary : theme.colors.textPrimary)
                    .lineLimit(1)
                Text(MoroL10n.Lists.formDraftHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.themeTint.opacity(0.10))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lists.draftRow")
    }

    /// A flat row like the rest of Moro's lists: icon, name and reply rule, then pin and more.
    @ViewBuilder
    private func listRow(_ list: MastodonList, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .moroScaledFont(size: 15, weight: .semibold)
                .foregroundStyle(theme.colors.themeTint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(theme.colors.themeTint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(theme.typography.body.weight(.semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(repliesPolicyLabel(for: list.repliesPolicy))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.spacing.s)

            pinToHomeButton(list)

            Menu {
                listActions(list)
            } label: {
                Image(systemName: "ellipsis")
                    .moroScaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(MoroL10n.StatusAction.more)

            if !isWide {
                Image(systemName: "chevron.right")
                    .moroScaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? theme.colors.themeTint.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
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
                    isPinned ? theme.colors.themeTint : theme.colors.textTertiary
                )
                .frame(width: 32, height: 32)
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
            let existingIDs = Set(viewModel.lists.map(\.id))
            success = await viewModel.createList(
                title: title,
                repliesPolicy: editorDraft.repliesPolicy
            )
            if success, isWide {
                // Open the new list beside the others.
                selectedListID = viewModel.lists.first { !existingIDs.contains($0.id) }?.id ?? selectedListID
            }
        }

        if success {
            showEditor = false
            if isEditingInline {
                withAnimation(.snappy(duration: 0.25)) { isEditingInline = false }
            }
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

/// The editor's fields: in a sheet, or beside the lists on iPhone Duo.
private struct ListEditorForm: View {
    @Environment(\.moroTheme) private var theme
    @Binding var draft: ListEditorDraft
    let isSaving: Bool
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section(MoroL10n.Lists.formNameSection) {
                TextField(MoroL10n.Lists.formNamePlaceholder, text: $draft.title)
                    .focused($isNameFocused)
                    .accessibilityIdentifier("lists.editor.name")
            }

            Section(MoroL10n.Lists.formReplySection) {
                ForEach(Self.replyOptions, id: \.policy) { option in
                    replyOptionRow(option)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.surfaceSubtle)
        .disabled(isSaving)
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
        .onAppear {
            if !draft.isEditing { isNameFocused = true }
        }
    }

    private struct ReplyOption {
        let policy: MastodonList.RepliesPolicy
        let icon: String
        let title: String
        let detail: String
    }

    private static var replyOptions: [ReplyOption] {
        [
            ReplyOption(policy: .list, icon: "person.3", title: MoroL10n.Lists.formReplyList,
                detail: MoroL10n.Lists.formReplyListDetail),
            ReplyOption(policy: .followed, icon: "person.crop.circle.badge.checkmark",
                title: MoroL10n.Lists.formReplyFollowed, detail: MoroL10n.Lists.formReplyFollowedDetail),
            ReplyOption(policy: MastodonList.RepliesPolicy.none, icon: "eye.slash", title: MoroL10n.Lists.formReplyNone,
                detail: MoroL10n.Lists.formReplyNoneDetail),
        ]
    }

    /// One choice per row, with what it means underneath, rather than a cramped segmented
    /// control whose labels don't say what they do.
    private func replyOptionRow(_ option: ReplyOption) -> some View {
        let isSelected = draft.repliesPolicy == option.policy
        return Button {
            withAnimation(.snappy(duration: 0.2)) { draft.repliesPolicy = option.policy }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .moroScaledFont(size: 15, weight: .medium)
                    .foregroundStyle(isSelected ? theme.colors.themeTint : theme.colors.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(option.detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .moroScaledFont(size: 20, weight: .regular)
                    .foregroundStyle(isSelected ? theme.colors.themeTint : theme.colors.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("lists.editor.reply.\(option.policy.rawValue)")
    }
}

private struct ListEditorSheet: View {
    @Binding var draft: ListEditorDraft

    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void

    var body: some View {
        NavigationStack {
            ListEditorForm(draft: $draft, isSaving: isSaving)
                .navigationTitle(draft.isEditing ? MoroL10n.Lists.formEditTitle : MoroL10n.Lists.newList)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        MoroToolbarButton(MoroL10n.Lists.formCancel, kind: .close) { onCancel() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        MoroToolbarButton(
                            draft.isEditing ? MoroL10n.Lists.formSave : MoroL10n.Lists.formCreate, kind: .confirm
                        ) {
                            Task { await onSave() }
                        }
                        .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .moroTheme(MoroTheme())
    }
}

/// Titles the page only when it stands alone; beside the lists the page keeps its own title.
private struct ListTimelineTitle: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

struct ListTimelineView: View {
    let list: MastodonList
    /// False beside the lists (iPhone Duo), where the page keeps the Lists title.
    var setsNavigationTitle = true
    @StateObject private var viewModel: TimelineViewModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @EnvironmentObject private var appState: AppState

    init(
        list: MastodonList, apiClient: MastodonAPI, cacheClientID: String,
        timelineCache: TimelineCache? = nil, setsNavigationTitle: Bool = true
    ) {
        self.list = list
        self.setsNavigationTitle = setsNavigationTitle
        _viewModel = StateObject(
            wrappedValue: TimelineViewModel(apiClient: apiClient, timelineType: .list(id: list.id, title: list.title),
                timelineCache: timelineCache, cacheClientID: cacheClientID)
        )
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            timelineList
        }
        .modifier(ListTimelineTitle(title: setsNavigationTitle ? list.title : nil))
        .background(theme.colors.surfaceBase)
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
                if case .failed = viewModel.refreshState {
                    TimelineCachedContentNotice { Task { await viewModel.refresh() } }
                }

                ForEach(viewModel.statuses.indexed(), id: \.element.id) { index, status in
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
            .moroReadableColumn()
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
