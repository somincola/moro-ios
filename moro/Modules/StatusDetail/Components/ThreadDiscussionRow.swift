import SwiftUI

/// Replies keep their reading width; shared horizontal boundaries separate discussions.
struct ThreadDiscussionRow: View {
    @Environment(\.moroTheme) private var theme

    let row: ThreadReadingRow
    let endsGroup: Bool
    let isCollapsed: Bool
    let apiClient: MastodonAPI
    let accountCache: AccountCache
    let actions: PostActions
    let onToggleBranch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThreadPostRow(
                status: row.item.status,
                translationAPIClient: apiClient,
                accountCache: accountCache,
                actions: actions
            )

            if row.replyCount > 0 {
                Button(action: onToggleBranch) {
                    Label(
                        isCollapsed ? MoroL10n.ThreadReading.expand(row.replyCount) : MoroL10n.ThreadReading.collapse(row.replyCount),
                        systemImage: isCollapsed ? "chevron.down" : "chevron.up"
                    )
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, theme.spacing.timelineDividerInset)
                .padding(.trailing, theme.spacing.l)
                .accessibilityIdentifier("thread.branch.\(row.id)")
            }

            if endsGroup {
                ThreadGroupDivider()
                    .padding(.vertical, theme.spacing.s)
            } else {
                MoroDivider(
                    leadingInset: theme.spacing.timelineDividerInset,
                    trailingInset: theme.spacing.l
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread.row.\(row.id)")
    }
}

struct ThreadGroupDivider: View {
    @Environment(\.moroTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.colors.textSecondary.opacity(0.24))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
