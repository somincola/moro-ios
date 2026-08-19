//
//  PostToolbar.swift
//  moro
//
//  Post toolbar component with primary actions and compact utility actions.
//

import SwiftUI

private enum PostToolbarMetrics {
    static let minBarHeight: CGFloat = 44
}

/// Post toolbar component with action buttons
struct PostToolbar: View {
    let status: Status
    var isOwnPost: Bool = false
    var isMutingUser: Bool? = nil
    var isBlockingUser: Bool? = nil
    var onReply: (() -> Void)? = nil
    var onBoost: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onBookmark: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    var onCopyText: (() -> Void)? = nil
    var onOpenInBrowser: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onMuteUser: (() -> Void)? = nil
    var onBlockUser: (() -> Void)? = nil
    var onBlockAndReport: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onPin: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var showCounts: Bool = true

    @Environment(\.moroTheme) private var theme

    var body: some View {
        // Equal-width lanes: each primary action button occupies a 1/4 share of
        // the bar (minus the trailing "more" button's intrinsic width) and is
        // pinned to its lane's leading edge. When a counter goes 0→1 or 9→10
        // the new digits push into the lane's trailing whitespace instead of
        // shifting neighbouring icons. The "more" button sits at the very
        // right edge so the row still reads as Twitter-style chrome.
        HStack(spacing: 0) {
            replyButton.frame(maxWidth: .infinity, alignment: .leading)
            boostButton.frame(maxWidth: .infinity, alignment: .leading)
            likeButton.frame(maxWidth: .infinity, alignment: .leading)
            bookmarkButton.frame(maxWidth: .infinity, alignment: .leading)
            moreButton
        }
        .frame(maxWidth: .infinity, minHeight: PostToolbarMetrics.minBarHeight)
        .contentShape(Rectangle())
        .onTapGesture {}
        // Post chrome should remain stable at accessibility sizes; the content
        // itself still receives the user's full Dynamic Type preference.
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    // MARK: - Actions

    private var replyButton: some View {
        AnimatedActionButton(
            role: .reply,
            activeIcon: "arrowshape.turn.up.left.fill",
            inactiveIcon: "arrowshape.turn.up.left",
            isActive: false,
            activeColor: theme.colors.primary500,
            inactiveColor: theme.colors.textSecondary,
            count: showCounts ? status.repliesCount : 0,
            isDisabled: false,
            action: { onReply?() },
            accessibilityLabel: MoroL10n.StatusAction.reply,
            minHitHeight: PostToolbarMetrics.minBarHeight
        )
    }

    private var boostButton: some View {
        let canBoost = status.allowsReblogAction
        return AnimatedActionButton(
            role: .boost,
            activeIcon: "arrow.2.squarepath",
            inactiveIcon: "arrow.2.squarepath",
            isActive: status.reblogged,
            activeColor: theme.colors.primary500,
            inactiveColor: canBoost ? theme.colors.textSecondary : theme.colors.textTertiary,
            count: showCounts ? status.reblogsCount : 0,
            isDisabled: !canBoost,
            action: { onBoost?() },
            accessibilityLabel: status.reblogged ? MoroL10n.StatusAction.unboost : MoroL10n.StatusAction.boost,
            minHitHeight: PostToolbarMetrics.minBarHeight
        )
    }

    private var likeButton: some View {
        AnimatedActionButton(
            role: .like,
            activeIcon: "heart.fill",
            inactiveIcon: "heart",
            isActive: status.favourited,
            activeColor: theme.colors.error,
            inactiveColor: theme.colors.textSecondary,
            count: showCounts ? status.favouritesCount : 0,
            isDisabled: false,
            action: { onLike?() },
            accessibilityLabel: status.favourited ? MoroL10n.StatusAction.unfavourite : MoroL10n.StatusAction.favourite,
            minHitHeight: PostToolbarMetrics.minBarHeight
        )
    }

    private var bookmarkButton: some View {
        AnimatedActionButton(
            role: .bookmark,
            activeIcon: "bookmark.fill",
            inactiveIcon: "bookmark",
            isActive: status.bookmarked,
            activeColor: theme.colors.primary500,
            inactiveColor: theme.colors.textSecondary,
            count: 0,
            isDisabled: false,
            action: { onBookmark?() },
            accessibilityLabel: status.bookmarked ? MoroL10n.StatusAction.unbookmark : MoroL10n.StatusAction.bookmark,
            minHitHeight: PostToolbarMetrics.minBarHeight
        )
    }

    private var moreButton: some View {
        StatusMoreButton(
            status: status,
            isOwnPost: isOwnPost,
            isMutingUser: isMutingUser,
            isBlockingUser: isBlockingUser,
            onShare: onShare,
            onCopyLink: onCopyLink,
            onCopyText: onCopyText,
            onOpenInBrowser: onOpenInBrowser,
            onEdit: onEdit,
            onMuteUser: onMuteUser,
            onBlockUser: onBlockUser,
            onBlockAndReport: onBlockAndReport,
            onReport: onReport,
            onPin: onPin,
            onDelete: onDelete
        )
        .accessibilityLabel(Text(MoroL10n.StatusAction.more))
    }
}
