//
//  AnnouncementsView.swift
//  moro
//
//  Announcement list and interaction page.
//

import SwiftUI

struct AnnouncementsView: View {
    @StateObject private var viewModel: AnnouncementsViewModel
    @State private var didCompleteInitialAppearance = false

    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var appRouter
    @EnvironmentObject private var appState: AppState

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: AnnouncementsViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            loadedContent
        }
        .navigationTitle(MoroL10n.Announcements.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialAnnouncements()
        }
        .onAppear {
            guard didCompleteInitialAppearance else {
                didCompleteInitialAppearance = true
                return
            }
            Task { await refreshAnnouncements() }
        }
        .onChange(of: viewModel.unreadCount) { _, _ in
            syncUnreadAnnouncementsCount()
        }
        .refreshable {
            await refreshAnnouncements()
        }
    }

    private var contentState: ContentState {
        if viewModel.isUnsupported {
            return .empty(
                EmptyStateSpec(
                    icon: "megaphone.slash",
                    title: MoroL10n.Announcements.unsupportedTitle,
                    message: MoroL10n.Announcements.unsupportedMessage,
                    actionTitle: MoroL10n.Announcements.refresh,
                    action: { Task { await refreshAnnouncements() } }
                ))
        }

        if viewModel.announcements.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
        }

        if viewModel.announcements.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Announcements.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Announcements.retry,
                    action: { Task { await refreshAnnouncements() } }
                ))
        }

        if viewModel.announcements.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "megaphone",
                    title: MoroL10n.Announcements.emptyTitle,
                    message: MoroL10n.Announcements.emptyMessage,
                    actionTitle: MoroL10n.Announcements.refresh,
                    action: { Task { await refreshAnnouncements() } }
                ))
        }

        return .loaded
    }

    private var loadedContent: some View {
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

                ForEach(Array(viewModel.announcements.enumerated()), id: \.element.id) { index, announcement in
                    announcementRow(announcement)

                    if index < viewModel.announcements.count - 1 {
                        MoroDivider()
                            .padding(.leading, theme.spacing.m)
                    }
                }
            }
        }
    }

    private func announcementRow(_ announcement: Announcement) -> some View {
        Button {
            appRouter.navigate(to: .announcementDetail(announcement))
        } label: {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(announcement.read ? Color.clear : theme.colors.primary500)
                        .frame(width: 7, height: 7)

                    Text(DateFormatting.dateTimeString(from: announcement.publishedAt))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)

                    Spacer()
                }

                Text(announcementSummary(announcement))
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !announcement.reactions.isEmpty {
                    reactionSummary(for: announcement)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func announcementSummary(_ announcement: Announcement) -> String {
        let summary = HTMLParser.stripHTML(announcement.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? MoroL10n.Announcements.title : summary
    }

    private func reactionSummary(for announcement: Announcement) -> some View {
        HStack(spacing: 8) {
            ForEach(announcement.reactions.prefix(6), id: \.name) { reaction in
                HStack(spacing: 4) {
                    reactionSymbol(reaction, size: 15)
                    Text("\(reaction.count)")
                        .fontWeight(.semibold)
                }
                .moroScaledFont(size: 12, weight: .medium)
                .foregroundStyle(reaction.me ? theme.colors.primary500 : theme.colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func reactionSymbol(_ reaction: AnnouncementReaction, size: CGFloat = 17) -> some View {
        if let imageURL = reaction.staticURL ?? reaction.url {
            MoroNetworkImage(url: imageURL, contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Text(reaction.name)
        }
    }

    private func syncUnreadAnnouncementsCount() {
        appState.unreadAnnouncementsCount = viewModel.unreadCount
    }

    private func loadInitialAnnouncements() async {
        await viewModel.loadInitial()
        syncUnreadAnnouncementsCount()
    }

    private func refreshAnnouncements() async {
        await viewModel.refresh()
        syncUnreadAnnouncementsCount()
    }
}

struct AnnouncementDetailView: View {
    @StateObject private var viewModel: AnnouncementsViewModel
    @State private var reactionPickerPresented = false
    @State private var emojiViewModel: CustomEmojiViewModel?

    @Environment(\.moroTheme) private var theme
    @EnvironmentObject private var appState: AppState

    private let initialAnnouncement: Announcement
    private let apiClient: MastodonAPI

    init(announcement: Announcement, apiClient: MastodonAPI) {
        self.initialAnnouncement = announcement
        self.apiClient = apiClient
        _viewModel = StateObject(
            wrappedValue: AnnouncementsViewModel(
                apiClient: apiClient,
                initialAnnouncement: announcement
            )
        )
    }

    private var announcement: Announcement {
        viewModel.announcements.first(where: { $0.id == initialAnnouncement.id }) ?? initialAnnouncement
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                header

                RichTextContentView(
                    html: announcement.content,
                    emojis: announcement.emojis.map {
                        Status.Emoji(
                            shortcode: $0.shortcode,
                            url: $0.url,
                            staticURL: $0.staticURL
                        )
                    },
                    emojiSize: 20,
                    isSelectable: true,
                    fontOverride: theme.typography.body,
                    textColorOverride: theme.colors.textPrimary,
                    linkColorOverride: theme.colors.primary500,
                    lineSpacing: 5
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                reactionBar

                if let transientErrorMessage = viewModel.transientErrorMessage {
                    Text(transientErrorMessage)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.error)
                }
            }
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .padding(.vertical, theme.spacing.l)
        }
        .navigationTitle(MoroL10n.Announcements.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshDetail()
        }
        .onChange(of: viewModel.unreadCount) { _, _ in
            syncUnreadAnnouncementsCount()
        }
        .sheet(isPresented: $reactionPickerPresented) {
            AnnouncementReactionPickerSheet(
                emojiViewModel: emojiViewModel,
                onClose: { reactionPickerPresented = false },
                onSelect: { name in
                    reactionPickerPresented = false
                    Task {
                        await viewModel.addReaction(for: announcement, name: name)
                        syncUnreadAnnouncementsCount()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                loadEmojiViewModelIfNeeded()
            }
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing.s) {
            Text(DateFormatting.dateTimeString(from: announcement.publishedAt))
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)

            if !announcement.read {
                Circle()
                    .fill(theme.colors.primary500)
                    .frame(width: 7, height: 7)
            }

            Spacer()

            if !announcement.read {
                Button(MoroL10n.Announcements.markRead) {
                    Task {
                        await viewModel.dismissAnnouncement(announcement)
                        syncUnreadAnnouncementsCount()
                    }
                }
                .font(theme.typography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.primary500)
                .disabled(viewModel.isMutating(announcementID: announcement.id))
            }
        }
    }

    private var reactionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(announcement.reactions, id: \.name) { reaction in
                    Button {
                        Task {
                            await viewModel.toggleReaction(
                                for: announcement,
                                reaction: reaction
                            )
                            syncUnreadAnnouncementsCount()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            reactionSymbol(reaction)

                            Text("\(reaction.count)")
                                .fontWeight(.semibold)
                        }
                        .moroScaledFont(size: 13, weight: .medium)
                        .foregroundStyle(
                            reaction.me ? theme.colors.primary500 : theme.colors.textSecondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    reaction.me
                                        ? theme.colors.primary500.opacity(0.14)
                                        : theme.colors.surfaceSubtle
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isMutating(announcementID: announcement.id))
                }

                Button {
                    reactionPickerPresented = true
                    loadEmojiViewModelIfNeeded()
                } label: {
                    Image(systemName: "plus")
                        .moroScaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(theme.colors.surfaceSubtle)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.ListMembers.add)
                .disabled(viewModel.isMutating(announcementID: announcement.id))
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func reactionSymbol(_ reaction: AnnouncementReaction, size: CGFloat = 17) -> some View {
        if let imageURL = reaction.staticURL ?? reaction.url {
            MoroNetworkImage(url: imageURL, contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Text(reaction.name)
        }
    }

    private var accountHost: String? {
        guard let urlString = appState.currentAccount?.url,
              let url = URL(string: urlString)
        else {
            return nil
        }
        return url.host
    }

    private func loadEmojiViewModelIfNeeded() {
        guard let host = accountHost else { return }
        let fetchedViewModel = EmojiService.shared.dequeueCustomEmojiViewModel(
            for: host,
            apiClient: apiClient
        )
        if emojiViewModel?.domain != host || emojiViewModel == nil {
            emojiViewModel = fetchedViewModel
        }
    }

    private func refreshDetail() async {
        await viewModel.refresh()
        syncUnreadAnnouncementsCount()
    }

    private func syncUnreadAnnouncementsCount() {
        appState.unreadAnnouncementsCount = viewModel.unreadCount
    }
}

private struct AnnouncementReactionPickerSheet: View {
    let emojiViewModel: CustomEmojiViewModel?
    let onClose: () -> Void
    let onSelect: (String) -> Void

    @Environment(\.moroTheme) private var theme
    @State private var searchText = ""

    private let commonReactions = [
        "👍", "❤️", "😂", "🎉", "😮", "😢", "👀", "🚀",
        "🔥", "👏", "🙏", "💯", "🤔", "🤯", "😎", "✨",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                searchField

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .moroScaledFont(size: 22, weight: .semibold)
                        .foregroundStyle(theme.colors.textSecondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.Common.close)
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.top, theme.spacing.m)
            .padding(.bottom, theme.spacing.s)

            ScrollView {
                VStack(spacing: theme.spacing.l) {
                    if searchText.isEmpty {
                        commonReactionGrid
                    }

                    if let emojiViewModel {
                        AnnouncementCustomEmojiReactionGrid(
                            emojiViewModel: emojiViewModel,
                            searchText: searchText,
                            onSelect: onSelect
                        )
                    } else {
                        ProgressView()
                            .padding(.top, theme.spacing.l)
                    }
                }
                .padding(.horizontal, theme.spacing.m)
                .padding(.bottom, theme.spacing.m)
            }

            if let emojiViewModel, searchText.isEmpty, !emojiViewModel.emojiGroups.isEmpty {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.s) {
                        ForEach(Array(emojiViewModel.emojiGroups.enumerated()), id: \.element.id) { index, group in
                            Button {
                                withAnimation(AnimationTokens.easing.springSoft) {
                                    emojiViewModel.selectGroup(at: index)
                                }
                            } label: {
                                Text(group.name)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(
                                        emojiViewModel.selectedGroupIndex == index
                                            ? theme.colors.primary500
                                            : theme.colors.textSecondary
                                    )
                                    .padding(.horizontal, theme.spacing.m)
                                    .padding(.vertical, theme.spacing.s)
                                    .background(
                                        Capsule()
                                            .fill(
                                                emojiViewModel.selectedGroupIndex == index
                                                    ? theme.colors.primary500.opacity(0.1)
                                                    : theme.colors.surfaceSubtle
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, theme.spacing.s)
                }
                .background(theme.colors.background)
            }
        }
        .background(theme.colors.background)
    }

    private var searchField: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "magnifyingglass")
                .moroScaledFont(size: 14, weight: .medium)
                .foregroundStyle(theme.colors.textSecondary)

            TextField(MoroL10n.EmojiPicker.search, text: $searchText)
                .textFieldStyle(.plain)
                .font(theme.typography.body)
        }
        .padding(.horizontal, theme.spacing.m)
        .frame(height: 42)
        .background(
            Capsule()
                .fill(theme.colors.surfaceSubtle)
        )
    }

    private var commonReactionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: theme.spacing.s)],
            spacing: theme.spacing.s
        ) {
            ForEach(commonReactions, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.colors.surfaceSubtle)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AnnouncementCustomEmojiReactionGrid: View {
    @ObservedObject var emojiViewModel: CustomEmojiViewModel
    let searchText: String
    let onSelect: (String) -> Void

    @Environment(\.moroTheme) private var theme

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: theme.spacing.s)],
            spacing: theme.spacing.s
        ) {
            ForEach(filteredEmojis) { emoji in
                Button {
                    onSelect(emoji.shortcode)
                } label: {
                    MoroNetworkImage(url: emoji.staticURL, contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.colors.surfaceSubtle)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji.shortcode)
            }
        }
    }

    private var filteredEmojis: [CustomEmoji] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emojiViewModel.currentGroupEmojis
        }

        if let trie = emojiViewModel.emojiTrie {
            return trie.search(searchText)
        }

        guard let emojis = emojiViewModel.emojis else { return [] }
        return emojis.filter { $0.shortcode.localizedCaseInsensitiveContains(searchText) }
    }
}
