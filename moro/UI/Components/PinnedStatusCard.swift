//
//  PinnedStatusCard.swift
//  moro
//
//  Compact card component for displaying a pinned status in the carousel.
//

import SwiftUI

struct PinnedStatusCard: View {
    @Environment(\.moroTheme) private var theme

    let status: Status
    let maxCardWidth: CGFloat?
    let onTap: () -> Void

    init(
        status: Status,
        maxCardWidth: CGFloat? = nil,
        onTap: @escaping () -> Void
    ) {
        self.status = status
        self.maxCardWidth = maxCardWidth
        self.onTap = onTap
    }

    private var displayStatus: Status {
        status.displayStatus
    }

    private var accountHandle: String {
        let acct = displayStatus.account.acct
        if acct.isEmpty {
            return "@\(displayStatus.account.username)"
        }
        return "@\(acct)"
    }

    private var supportedMediaAttachments: [Status.Attachment] {
        displayStatus.mediaAttachments.filter {
            let type = $0.type.lowercased()
            return type == "image" || type == "video" || type == "gifv"
        }
    }

    private var leadingMediaAttachment: Status.Attachment? {
        supportedMediaAttachments.first
    }

    private var leadingMediaPreviewURL: URL? {
        guard let attachment = leadingMediaAttachment else { return nil }
        return attachment.previewURL ?? attachment.url
    }

    private var isLeadingMediaVideo: Bool {
        guard let attachment = leadingMediaAttachment else { return false }
        let type = attachment.type.lowercased()
        return type == "video" || type == "gifv"
    }

    private var isLeadingMediaGIF: Bool {
        guard let attachment = leadingMediaAttachment else { return false }
        let type = attachment.type.lowercased()
        return type == "gifv" || attachment.url.pathExtension.lowercased() == "gif"
    }

    private var mediaBadgeText: String? {
        let mediaCount = supportedMediaAttachments.count
        guard mediaCount > 1 else { return nil }
        return "+\(mediaCount - 1)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                HStack(alignment: .top, spacing: theme.spacing.s) {
                    MoroAvatar(
                        imageURL: displayStatus.account.avatarAnimatedURL,
                        staticImageURL: displayStatus.account.avatarURL,
                        initials: displayStatus.account.displayNameInitials,
                        size: 30
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                            AccountDisplayNameView(
                                account: displayStatus.account,
                                typography: .bodyStrong,
                                textColor: theme.colors.textPrimary,
                                lineLimit: 1,
                                truncationMode: .tail,
                                minimumScaleFactor: 0.86,
                                allowsTightening: true
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                            Text(DateFormatting.relativeString(for: displayStatus.createdAt))
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(2)
                        }

                        Text(accountHandle)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !HTMLParser.stripHTML(displayStatus.content).isEmpty {
                    // Cap the preview to keep cards a consistent size for the shared-height
                    // carousel; the full text is one tap away on the status detail.
                    LinkedTextView(
                        html: displayStatus.content,
                        mentions: displayStatus.mentions,
                        tags: displayStatus.tags,
                        emojis: displayStatus.emojis,
                        lineLimit: 6
                    )
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let previewURL = leadingMediaPreviewURL {
                    ZStack {
                        CachedAsyncImage(url: previewURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.colors.surfaceSubtle.opacity(0.7))
                        }
                        .frame(height: 170)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if isLeadingMediaVideo {
                            Image(systemName: isLeadingMediaGIF ? "play.circle.fill" : "play.fill")
                                .moroScaledFont(size: isLeadingMediaGIF ? 34 : 28, weight: .semibold)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        }

                        VStack {
                            HStack {
                                if isLeadingMediaVideo {
                                    Text(isLeadingMediaGIF ? "GIF" : MoroL10n.PinnedCard.mediaLabel)
                                        .font(theme.typography.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.65))
                                        .clipShape(Capsule(style: .continuous))
                                }

                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)

                        if let mediaBadgeText {
                            VStack {
                                HStack {
                                    Spacer(minLength: 0)
                                    Text(mediaBadgeText)
                                        .font(theme.typography.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Capsule(style: .continuous))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                        }
                    }
                }

                if let spoiler = displayStatus.spoilerText,
                    !spoiler.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .moroScaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(theme.colors.textSecondary)

                        Text(MoroL10n.PinnedCard.cwWarning)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
            .padding(theme.spacing.m)
            .frame(maxWidth: maxCardWidth ?? .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.surfaceBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
    
// Keep preview data for SwiftUI previews.
#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "This is a test bio",
        avatar: "https://mastodon.social/avatars/original/missing.png",
        avatarStatic: "https://mastodon.social/avatars/original/missing.png",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200,
        createdAt: Date(),
        locked: false,
        bot: false,
        fields: [],
        url: nil,
        moved: nil,
        suspended: false,
        limited: false
    )

    let sampleStatus = Status(
        id: "1",
        content: "<p>This is a pinned status that showcases important content. It can be multiple lines long to demonstrate dynamic card height.</p>",
        createdAt: Date(),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 42,
        reblogsCount: 12,
        repliesCount: 5,
        bookmarked: false,
        favourited: false,
        reblogged: false,
        reblog: nil,
        quote: nil,
        inReplyToID: nil,
        inReplyToAccountID: nil,
        spoilerText: nil,
        sensitive: false,
        visibility: "public",
        language: "en",
        uri: "https://mastodon.social/@testuser/1",
        url: URL(string: "https://mastodon.social/@testuser/1"),
        mentions: nil,
        tags: nil,
        emojis: nil,
        card: nil,
        poll: nil
    )

    PinnedStatusCard(status: sampleStatus, onTap: {})
        .padding()
        .background(Color.gray.opacity(0.1))
}
