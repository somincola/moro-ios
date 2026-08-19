//
//  EmojiManagementView.swift
//  moro
//
//  Per-instance custom emoji ordering settings.
//

import SwiftUI

struct EmojiManagementView: View {
    @Environment(\.moroTheme) private var theme

    let domain: String
    let apiClient: MastodonAPI?

    @State private var emojiViewModel: CustomEmojiViewModel?
    @State private var orderedGroups: [EmojiGroup] = []
    @State private var isApplyingManualOrder: Bool = false

    var body: some View {
        Group {
            if let emojiViewModel {
                emojiListView(emojiViewModel)
                    .onReceive(emojiViewModel.$emojiGroups) { incoming in
                        guard !isApplyingManualOrder else { return }
                        orderedGroups = incoming
                    }
            } else {
                ProgressView(MoroL10n.Emoji.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.colors.background)
            }
        }
        .navigationTitle(MoroL10n.Emoji.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            configureIfNeeded()
        }
    }

    private func emojiListView(_ emojiViewModel: CustomEmojiViewModel) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(domain)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(MoroL10n.Emoji.dragHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text(MoroL10n.Emoji.currentSite)
            }

            if orderedGroups.isEmpty {
                Section {
                    switch emojiViewModel.loadState {
                    case .initial, .loading:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    case .fail:
                        Text(MoroL10n.Emoji.loadFailed)
                            .foregroundStyle(theme.colors.textSecondary)
                    case .finish:
                        Text(MoroL10n.Emoji.noCustomEmoji)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                } header: {
                    Text(MoroL10n.Emoji.sort)
                }
            } else {
                Section {
                    ForEach(orderedGroups) { group in
                        emojiGroupRow(group)
                    }
                    .onMove(perform: { source, destination in
                        moveGroups(source: source, destination: destination, viewModel: emojiViewModel)
                    })
                } header: {
                    Text(MoroL10n.Emoji.groupSort)
                } footer: {
                    Text(MoroL10n.Emoji.groupSortHint)
                }
            }

            Section {
                Button(MoroL10n.Emoji.resetSort, role: .destructive) {
                    emojiViewModel.resetCustomGroupOrder()
                    orderedGroups = emojiViewModel.emojiGroups
                }
                .disabled(orderedGroups.isEmpty || !emojiViewModel.hasCustomGroupOrder)
            }
        }
        .moroSettingsListChrome()
        .environment(\.editMode, .constant(.active))
        .refreshable {
            emojiViewModel.load(forceRefresh: true)
        }
    }

    private func emojiGroupRow(_ group: EmojiGroup) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array(group.emojis.prefix(3).enumerated()), id: \.offset) { _, emoji in
                    CachedAsyncImage(url: emoji.staticURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    }
                    .frame(width: 20, height: 20)
                }
            }
            .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(MoroL10n.Emoji.emojiCount(group.emojis.count))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func moveGroups(
        source: IndexSet,
        destination: Int,
        viewModel: CustomEmojiViewModel
    ) {
        isApplyingManualOrder = true
        orderedGroups.move(fromOffsets: source, toOffset: destination)
        viewModel.applyCustomGroupOrder(orderedGroups.map(\.name))
        isApplyingManualOrder = false
    }

    @MainActor
    private func configureIfNeeded() {
        guard emojiViewModel == nil else { return }
        guard let fetched = EmojiService.shared.dequeueCustomEmojiViewModel(
            for: domain,
            apiClient: apiClient
        ) else { return }
        emojiViewModel = fetched
        orderedGroups = fetched.emojiGroups
        fetched.load()
    }
}

struct EmojiManagementUnavailableView: View {
    @Environment(\.moroTheme) private var theme

    var body: some View {
        ContentUnavailableView(
            MoroL10n.Emoji.noInstance,
            systemImage: "face.smiling.inverse",
            description: Text(MoroL10n.Emoji.noInstanceHint)
        )
        .foregroundStyle(theme.colors.textSecondary)
        .background(theme.colors.background)
        .navigationTitle(MoroL10n.Emoji.navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
