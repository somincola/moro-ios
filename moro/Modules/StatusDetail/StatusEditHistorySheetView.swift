//
//  StatusEditHistorySheetView.swift
//  moro
//
//  Sheet UI for browsing status edit history.
//

import SwiftUI

struct StatusEditHistorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    let state: StatusDetailViewModel.HistoryLoadingState
    let items: [StatusEditHistoryItem]
    let onRetry: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading:
                    loadingView
                case .loaded:
                    if items.isEmpty {
                        emptyView
                    } else {
                        historyListView
                    }
                case .error(let error):
                    errorView(error)
                }
            }
            .navigationTitle(MoroL10n.EditHistory.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    MoroNavigationControlButton(kind: .close) { dismiss() }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: theme.spacing.m) {
            ProgressView()
            Text(MoroL10n.EditHistory.loading)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    private var emptyView: some View {
        VStack(spacing: theme.spacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .moroScaledFont(size: 24, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
            Text(MoroL10n.EditHistory.emptyTitle)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)
            Text(MoroL10n.EditHistory.emptyMessage)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: theme.spacing.m) {
            InlineFeedbackCard(
                kind: .error,
                message: MoroL10n.EditHistory.loadFailed(error.localizedDescription),
                actionTitle: MoroL10n.EditHistory.retry,
                action: onRetry
            )
        }
        .padding(theme.spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing.s) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    historyCard(item: item, index: index, total: items.count)
                }
            }
            .padding(theme.spacing.m)
        }
        .background(theme.colors.background)
    }

    private func historyCard(item: StatusEditHistoryItem, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: 8) {
                Text(index == 0 ? MoroL10n.EditHistory.currentVersion : MoroL10n.EditHistory.historyVersion(total - index))
                    .font(theme.typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.primary500)

                Spacer()

                Text(formattedTime(item.createdAt))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            if let spoiler = item.spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines),
                !spoiler.isEmpty
            {
                Text(MoroL10n.EditHistory.contentWarning(spoiler))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.colors.surfaceSubtle)
                    )
            }

            let plainText = HTMLParser.stripHTML(item.content)
            Text(plainText.isEmpty ? MoroL10n.EditHistory.noBody : plainText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.leading)

            if !item.mediaAttachments.isEmpty {
                Text(MoroL10n.EditHistory.mediaCount(item.mediaAttachments.count))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(theme.spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return MoroL10n.EditHistory.unknownTime }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
