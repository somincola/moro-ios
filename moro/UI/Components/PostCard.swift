//
//  PostCard.swift
//  moro
//
//  Timeline post card following Moro's flat, reading-first design.
//  Uses modular components: PostHeader, PostAuthorInfo, PostContent, PostToolbar
//

import SwiftUI

struct PostCard: View {
    /// How to display thread-related UI elements
    enum ThreadDisplayMode {
        /// Normal display (show reply header if it's a reply)
        case normal
        /// Hide reply header (for contiguous self-replies with connection lines)
        case hideReplyHeader
        /// Show "上接嘟文串" link (for non-contiguous self-replies)
        case showThreadLink
    }
    
    /// Display mode for different contexts
    enum PostDisplayMode {
        /// Normal display (timeline, thread view)
        case normal
        /// Quoted/referenced post (in compose reply view)
        case quoted
    }

    let status: Status
    var translationAPIClient: MastodonAPI? = nil
    var actions: PostActions = .empty
    var threadDisplayMode: ThreadDisplayMode = .normal
    var displayMode: PostDisplayMode = .normal
    var hideAvatar: Bool = false
    var showToolbar: Bool = true

    /// Optional account cache for looking up avatar URLs
    var accountCache: AccountCache? = nil

    private enum Metrics {
        static let horizontalPadding: CGFloat = 20
        static let avatarSize: CGFloat = 44
        static let avatarContentSpacing: CGFloat = 12
        static let contextBottomSpacing: CGFloat = 5
        static let actionTopSpacing: CGFloat = 2

        static var contentLeadingInset: CGFloat {
            avatarSize + avatarContentSpacing
        }
    }
    
    /// Timeline density (comfortable/compact) drives row padding and body line spacing.
    /// Changing it re-renders rows through the normal
    /// settings → view rebuild path (never mid-scroll).
    private var density: AppSettings.TimelineDensity {
        settings.timelineDensity
    }

    /// Computed property: avatar size (unified across all modes)
    private var avatarSize: CGFloat {
        Metrics.avatarSize
    }

    /// Computed property: whether this is in quoted mode
    private var isQuoted: Bool {
        displayMode == .quoted
    }

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.appRouter) private var router
    @StateObject private var translationViewModel = StatusTranslationViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if displayMode == .quoted {
                postContent(
                    status: status.displayStatus,
                    avatarAction: { actions.navigation?.onAvatarTap() },
                    usernameAction: { actions.navigation?.onUsernameTap() }
                )
            } else {
                if status.statusType == .reblog, let rebloggedStatus = status.reblog?.value {
                    PostHeader(
                        type: .boost(
                            account: status.account,
                            onTap: actions.navigation?.onBoostUserTap
                        )
                    )
                    .padding(.leading, hideAvatar ? 0 : Metrics.contentLeadingInset)
                    .padding(.bottom, Metrics.contextBottomSpacing)

                    postContent(
                        status: rebloggedStatus,
                        avatarAction: { router.navigate(to: .userProfile(rebloggedStatus.account)) },
                        usernameAction: { router.navigate(to: .userProfile(rebloggedStatus.account)) }
                    )

                } else if status.statusType == .reply {
                    switch threadDisplayMode {
                    case .hideReplyHeader:
                        postContent(
                            status: status,
                            avatarAction: { actions.navigation?.onAvatarTap() },
                            usernameAction: { actions.navigation?.onUsernameTap() }
                        )

                    case .showThreadLink:
                        PostHeader(type: .threadLink)
                            .padding(.leading, hideAvatar ? 0 : Metrics.contentLeadingInset)
                            .padding(.bottom, Metrics.contextBottomSpacing)
                        postContent(
                            status: status,
                            avatarAction: { actions.navigation?.onAvatarTap() },
                            usernameAction: { actions.navigation?.onUsernameTap() }
                        )

                    case .normal:
                        PostHeader(
                            type: .reply(
                                account: status.account,
                                inReplyToAccountID: status.inReplyToAccountID,
                                mentions: status.mentions,
                                accountCache: accountCache,
                                onUsernameTap: { actions.navigation?.onUsernameTap() },
                                onReplyToUserTap: actions.navigation?.onReplyToUserTap
                            )
                        )
                        .padding(.leading, hideAvatar ? 0 : Metrics.contentLeadingInset)
                        .padding(.bottom, Metrics.contextBottomSpacing)
                        postContent(
                            status: status,
                            avatarAction: { actions.navigation?.onAvatarTap() },
                            usernameAction: { actions.navigation?.onUsernameTap() }
                        )
                    }

                } else {
                    postContent(
                        status: status,
                        avatarAction: { actions.navigation?.onAvatarTap() },
                        usernameAction: { actions.navigation?.onUsernameTap() }
                    )
                }
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.top, density.rowTopPadding)
        .padding(
            .bottom,
            showToolbar ? 0 : density.rowBottomPadding
        )
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Post Content

    @ViewBuilder
    private func postContent(
        status: Status,
        avatarAction: @escaping () -> Void,
        usernameAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Metrics.avatarContentSpacing) {
            if !hideAvatar {
                Button(action: avatarAction) {
                    MoroAvatar(
                        imageURL: status.account.avatarAnimatedURL,
                        staticImageURL: status.account.avatarURL,
                        initials: status.account.displayNameInitials,
                        size: avatarSize
                    )
                }
                .buttonStyle(.plain)
                .frame(width: avatarSize, height: avatarSize)
                .layoutPriority(1)
                .accessibilityLabel(
                    MoroL10n.Profile.openProfile(
                        status.account.acct.isEmpty ? status.account.username : status.account.acct
                    )
                )
            }

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                PostAuthorInfo(
                    account: status.account,
                    createdAt: status.createdAt,
                    layoutMode: .timeline,
                    onUsernameTap: usernameAction,
                    onStatusTap: actions.onTap,
                    isQuoted: isQuoted
                )

                VStack(alignment: .leading, spacing: 0) {
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
                        contentLineSpacing: density.contentLineSpacing,
                        isQuoted: isQuoted
                    )

                    if showToolbar {
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
                        .padding(.top, Metrics.actionTopSpacing)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
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
        content: "This is a sample status with some content. #Moro #iOS #SwiftUI",
        createdAt: Date().addingTimeInterval(-3600),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 12,
        reblogsCount: 3,
        repliesCount: 1,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )

    ScrollView {
        PostCard(status: sampleStatus, actions: .empty)
    }
    .moroTheme(MoroTheme())
}
