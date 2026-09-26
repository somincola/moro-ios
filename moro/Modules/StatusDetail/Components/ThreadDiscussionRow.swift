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

    private var showsBranchControl: Bool { row.showsBranchControl(isCollapsed: isCollapsed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThreadPostRow(
                status: row.item.status,
                translationAPIClient: apiClient,
                accountCache: accountCache,
                actions: actions
            )

            if showsBranchControl {
                MoroDivider(
                    leadingInset: theme.spacing.contentHorizontalInset,
                    trailingInset: theme.spacing.contentHorizontalInset
                )

                Button {
                    // Content below this control changes; keep its current reading position.
                    var transaction = Transaction()
                    transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                    withTransaction(transaction) { onToggleBranch() }
                } label: {
                    HStack(spacing: theme.spacing.s) {
                        Text(isCollapsed ? MoroL10n.ThreadReading.expand(row.replyCount) : MoroL10n.ThreadReading.collapse(row.replyCount))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: theme.spacing.s)
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .fontWeight(.medium)
                            .accessibilityHidden(true)
                    }
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, theme.spacing.contentHorizontalInset)
                    .padding(.vertical, theme.spacing.s)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ThreadBranchButtonStyle(pressedBackground: theme.colors.surfaceSubtle))
                .accessibilityIdentifier("thread.branch.\(row.id)")
            }

            if endsGroup {
                ThreadGroupDivider()
                    .padding(.vertical, theme.spacing.s)
            } else {
                MoroDivider(
                    leadingInset: showsBranchControl
                        ? theme.spacing.contentHorizontalInset
                        : theme.spacing.timelineDividerInset,
                    trailingInset: theme.spacing.contentHorizontalInset
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread.row.\(row.id)")
    }
}

private struct ThreadBranchButtonStyle: ButtonStyle {
    let pressedBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedBackground : Color.clear)
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
