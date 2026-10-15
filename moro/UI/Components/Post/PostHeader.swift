//
//  PostHeader.swift
//  moro
//
//  Post header component for Boost/Reply/Mention context
//

import SwiftUI

/// Header component for Boost/Reply/Mention context
struct PostHeader: View {
    enum HeaderType {
        case boost(account: Account, onTap: (() -> Void)?)
        case reply(account: Account, inReplyToAccountID: String?, mentions: [Status.Mention]?, accountCache: AccountCache?, onUsernameTap: (() -> Void)?, onReplyToUserTap: ((Status.Mention) -> Void)?)
        case threadLink
    }
    
    let type: HeaderType
    
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private enum Metrics {
        static let iconSize: CGFloat = 11
        static let avatarSize: CGFloat = 16
        static let contextFontSize: CGFloat = 13
    }
    
    var body: some View {
        switch type {
        case .boost(let account, let onTap):
            boostHeader(account: account, onTap: onTap)
        case .reply(let account, let inReplyToAccountID, let mentions, let accountCache, let onUsernameTap, let onReplyToUserTap):
            replyHeader(account: account, inReplyToAccountID: inReplyToAccountID, mentions: mentions, accountCache: accountCache, onUsernameTap: onUsernameTap, onReplyToUserTap: onReplyToUserTap)
        case .threadLink:
            threadLinkHeader
        }
    }
    
    // MARK: - Boost Header
    
    @ViewBuilder
    private func boostHeader(account: Account, onTap: (() -> Void)?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button(action: { onTap?() }) {
                Label {
                    Text("\(account.displayNameFormatted) \(MoroL10n.Post.boosted)")
                        .moroScaledFont(size: Metrics.contextFontSize)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                        .moroScaledFont(size: Metrics.iconSize, weight: .medium)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.Profile.openProfile(account.acct))
        } else {
            HStack(spacing: theme.spacing.hairline) {
                Image(systemName: "arrow.2.squarepath")
                    .moroScaledFont(size: Metrics.iconSize, weight: .medium)
                    .accessibilityHidden(true)

                Button(action: { onTap?() }) {
                    HStack(spacing: theme.spacing.hairline) {
                        MoroAvatar(
                            imageURL: account.avatarAnimatedURL,
                            staticImageURL: account.avatarURL,
                            initials: account.displayNameInitials, seed: account.placeholderSeed,
                            size: Metrics.avatarSize
                        )

                        AccountDisplayNameView(
                            account: account,
                            typography: .caption,
                            textColor: theme.colors.textSecondary,
                            lineLimit: 1,
                            truncationMode: .tail,
                            minimumScaleFactor: 0.86,
                            allowsTightening: true
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.Profile.openProfile(account.acct))

                Text(MoroL10n.Post.boosted)
                    .moroScaledFont(size: Metrics.contextFontSize)

                Spacer()
            }
            .foregroundStyle(theme.colors.textSecondary)
        }
    }
    
    // MARK: - Reply Header
    
    @ViewBuilder
    private func replyHeader(account: Account, inReplyToAccountID: String?, mentions: [Status.Mention]?, accountCache: AccountCache?, onUsernameTap: (() -> Void)?, onReplyToUserTap: ((Status.Mention) -> Void)?) -> some View {
        if dynamicTypeSize.isAccessibilitySize,
           let context = replyContext(
               account: account,
               inReplyToAccountID: inReplyToAccountID,
               mentions: mentions,
               accountCache: accountCache,
               onUsernameTap: onUsernameTap,
               onReplyToUserTap: onReplyToUserTap
           ) {
            Button(action: context.action) {
                Label {
                    Text("\(MoroL10n.Post.replyingTo) \(context.name)")
                        .moroScaledFont(size: Metrics.contextFontSize)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .moroScaledFont(size: Metrics.iconSize, weight: .medium)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else {
            regularReplyHeader(
                account: account,
                inReplyToAccountID: inReplyToAccountID,
                mentions: mentions,
                accountCache: accountCache,
                onUsernameTap: onUsernameTap,
                onReplyToUserTap: onReplyToUserTap
            )
        }
    }

    private func regularReplyHeader(account: Account, inReplyToAccountID: String?, mentions: [Status.Mention]?, accountCache: AccountCache?, onUsernameTap: (() -> Void)?, onReplyToUserTap: ((Status.Mention) -> Void)?) -> some View {
        HStack(spacing: theme.spacing.hairline) {
            Image(systemName: "arrowshape.turn.up.left")
                .moroScaledFont(size: Metrics.iconSize, weight: .medium)
                .accessibilityHidden(true)

            Text(MoroL10n.Post.replyingTo)
                .moroScaledFont(size: Metrics.contextFontSize)

            // Check if replying to self
            if let replyToAccountID = inReplyToAccountID,
               replyToAccountID == account.id {
                // Self-reply: show own avatar and display name (clickable)
                Button(action: { onUsernameTap?() }) {
                    HStack(spacing: theme.spacing.xs) {
                        MoroAvatar(
                            imageURL: account.avatarAnimatedURL,
                            staticImageURL: account.avatarURL,
                            initials: account.displayNameInitials, seed: account.placeholderSeed,
                            size: Metrics.avatarSize
                        )

                        AccountDisplayNameView(
                            account: account,
                            typography: .caption,
                            textColor: theme.colors.textSecondary,
                            lineLimit: 1,
                            truncationMode: .tail,
                            minimumScaleFactor: 0.86,
                            allowsTightening: true
                        )
                    }
                }
                .buttonStyle(.plain)
            } else if let replyToAccountID = inReplyToAccountID,
                      let mention = mentions?.first(where: { $0.id == replyToAccountID }) {
                // Replying to someone else: try to get account info from cache (clickable)
                let cachedAccount = accountCache?.get(id: replyToAccountID)
                let avatarURL = cachedAccount?.avatarURL
                let displayName = cachedAccount?.displayNameFormatted
                    ?? formatMentionDisplayName(mention.username)

                Button(action: { onReplyToUserTap?(mention) }) {
                    HStack(spacing: theme.spacing.xs) {
                        MoroAvatar(
                            imageURL: cachedAccount?.avatarAnimatedURL,
                            staticImageURL: avatarURL,
                            initials: String(mention.username.prefix(2).uppercased()),
                            size: Metrics.avatarSize
                        )

                        if let cachedAccount {
                            AccountDisplayNameView(
                                account: cachedAccount,
                                typography: .caption,
                                textColor: theme.colors.textSecondary,
                                lineLimit: 1,
                                truncationMode: .tail,
                                minimumScaleFactor: 0.86,
                                allowsTightening: true
                            )
                        } else {
                            Text(displayName)
                                .moroIdentityPrimaryLine()
                                .moroScaledFont(size: Metrics.contextFontSize)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if let firstMention = mentions?.first {
                // Fallback to first mention - try cache lookup (clickable)
                let cachedAccount = accountCache?.get(id: firstMention.id)
                let avatarURL = cachedAccount?.avatarURL
                let displayName = cachedAccount?.displayNameFormatted
                    ?? formatMentionDisplayName(firstMention.username)

                Button(action: { onReplyToUserTap?(firstMention) }) {
                    HStack(spacing: theme.spacing.xs) {
                        MoroAvatar(
                            imageURL: avatarURL,
                            initials: String(firstMention.username.prefix(2).uppercased()),
                            size: Metrics.avatarSize
                        )

                        if let cachedAccount {
                            AccountDisplayNameView(
                                account: cachedAccount,
                                typography: .caption,
                                textColor: theme.colors.textSecondary,
                                lineLimit: 1,
                                truncationMode: .tail,
                                minimumScaleFactor: 0.86,
                                allowsTightening: true
                            )
                        } else {
                            Text(displayName)
                                .moroIdentityPrimaryLine()
                                .moroScaledFont(size: Metrics.contextFontSize)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .foregroundStyle(theme.colors.textSecondary)
    }
    
    // MARK: - Thread Link Header
    
    @ViewBuilder
    private var threadLinkHeader: some View {
        HStack(spacing: theme.spacing.hairline) {
            Image(systemName: "arrow.up.left")
                .moroScaledFont(size: Metrics.iconSize, weight: .medium)
                .accessibilityHidden(true)
            
            Text(MoroL10n.PostHeader.threadContext)
                .moroScaledFont(size: Metrics.contextFontSize)
            
            Spacer()
        }
        .foregroundStyle(theme.colors.textSecondary)
    }
    
    // MARK: - Helpers
    
    /// Format username to look like a display name (capitalize first letter)
    private func formatMentionDisplayName(_ username: String) -> String {
        guard !username.isEmpty else { return username }
        return username.prefix(1).uppercased() + username.dropFirst()
    }

    private func replyContext(
        account: Account,
        inReplyToAccountID: String?,
        mentions: [Status.Mention]?,
        accountCache: AccountCache?,
        onUsernameTap: (() -> Void)?,
        onReplyToUserTap: ((Status.Mention) -> Void)?
    ) -> (name: String, action: () -> Void)? {
        if inReplyToAccountID == account.id {
            return (account.displayNameFormatted, { onUsernameTap?() })
        }

        let mention = inReplyToAccountID.flatMap { replyID in
            mentions?.first(where: { $0.id == replyID })
        } ?? mentions?.first

        guard let mention else { return nil }
        let cachedAccount = accountCache?.get(id: mention.id)
        let name = cachedAccount?.displayNameFormatted
            ?? formatMentionDisplayName(mention.username)
        return (name, { onReplyToUserTap?(mention) })
    }
}
