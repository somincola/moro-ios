import SwiftUI

/// A discussion keeps a full-width opening reply and one fixed inset for its children.
struct ThreadDiscussionRow: View {
    @Environment(\.moroTheme) private var theme

    let row: ThreadReadingRow
    let parent: Status?
    let endsGroup: Bool
    let isCollapsed: Bool
    let apiClient: MastodonAPI
    let accountCache: AccountCache
    let actions: PostActions
    let onToggleBranch: () -> Void
    let onJumpToParent: (String) -> Void

    private var inset: CGFloat { row.isNestedReply ? theme.spacing.m : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Adjacent replies already have a visible parent directly above them.
                // Keep the jump link where a fork or the author filter separates them.
                if let parent {
                    Button { onJumpToParent(parent.id) } label: {
                        Label(MoroL10n.ThreadReading.parent(parent.account.displayName), systemImage: "arrow.turn.up.left")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, theme.spacing.timelineDividerInset)
                    .padding(.trailing, theme.spacing.l)
                    .accessibilityIdentifier("thread.parent.\(row.id)")
                }

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
            }
            .padding(.leading, inset)
            .overlay(alignment: .leading) {
                if row.isNestedReply {
                    Rectangle()
                        .fill(theme.colors.textSecondary.opacity(0.2))
                        .frame(width: 1)
                        .padding(.leading, theme.spacing.l)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            MoroDivider(
                leadingInset: endsGroup ? theme.spacing.l : theme.spacing.timelineDividerInset + inset,
                trailingInset: theme.spacing.l
            )
            .opacity(endsGroup ? 1 : 0.55)
            .padding(.vertical, endsGroup ? theme.spacing.xs : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread.row.\(row.id)")
    }
}

struct ThreadSectionLabel: View {
    @Environment(\.moroTheme) private var theme
    let title: String

    var body: some View {
        Text(title)
            .font(theme.typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.m)
            .padding(.bottom, theme.spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}
