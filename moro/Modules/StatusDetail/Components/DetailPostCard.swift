//
//  DetailPostCard.swift
//  moro
//
//  Expanded post card for the focused post in thread detail view.
//  Shows full timestamp and engagement counts on highlighted action buttons.
//  Uses modular components: PostAuthorInfo, PostContent, PostFooter, PostToolbar
//

import SwiftUI
import UIKit

/// Expanded post card for the focused/current post in thread detail view
struct DetailPostCard: View {
    let status: Status
    var translationAPIClient: MastodonAPI? = nil
    var actions: PostActions = .empty

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @StateObject private var translationViewModel = StatusTranslationViewModel()

    private var detailBodyFont: Font {
        .system(size: 20, weight: .regular)
    }

    private var detailBodyUIFont: UIFont {
        .moroScaled(ofSize: 20, weight: .regular, relativeTo: .title3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                Button(action: { actions.navigation?.onAvatarTap() }) {
                    MoroAvatar(
                        imageURL: status.account.avatarAnimatedURL,
                        staticImageURL: status.account.avatarURL,
                        initials: status.account.displayNameInitials,
                        size: 48
                    )
                }
                .buttonStyle(.plain)

                PostAuthorInfo(
                    account: status.account,
                    createdAt: status.createdAt,
                    layoutMode: .detail,
                    onUsernameTap: { actions.navigation?.onUsernameTap() },
                    avatarSize: 48
                )

                Spacer()
            }

            PostContent(
                status: status,
                translationAPIClient: translationAPIClient,
                translationViewModel: translationViewModel,
                onMentionTap: actions.navigation?.onMentionTap,
                onHashtagTap: actions.navigation?.onHashtagTap,
                onLinkTap: actions.onLinkTap,
                onPollVote: actions.onPollVote,
                onQuotedStatusTap: actions.navigation?.onQuotedStatusTap,
                onImageTap: actions.navigation?.onImageTap,
                textFont: detailBodyFont,
                uiTextFont: detailBodyUIFont,
                quoteStyle: .card
            )

            PostFooter(
                status: status,
                showFullTimestamp: true,
                showEngagementStats: false
            )

            MoroDivider(leadingInset: theme.spacing.detailDividerInset)

            PostToolbar(
                status: status,
                isOwnPost: actions.isOwnPost,
                isMutingUser: actions.menu?.isMutingUser,
                isBlockingUser: actions.menu?.isBlockingUser,
                onReply: actions.onReply,
                onBoost: actions.onBoost,
                onLike: actions.onLike,
                onBookmark: actions.onBookmark,
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
                onDelete: actions.onDelete,
                showCounts: true
            )
            .padding(.top, 2)
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.m)
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
        content: "今天又有供应商送的咖啡，有个人不由分说给了我一杯热的，我反复问没有其他的吗也不理我。等领导回来他又变出两杯冷的给领导挑选，领导一句不想喝又给我了",
        createdAt: Date().addingTimeInterval(-3600),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 1,
        reblogsCount: 0,
        repliesCount: 0,
        bookmarked: false,
        favourited: true,
        reblogged: false
    )

    ScrollView {
        DetailPostCard(status: sampleStatus)
    }
    .moroTheme(MoroTheme())
}
