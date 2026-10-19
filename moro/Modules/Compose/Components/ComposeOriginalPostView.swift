//
//  ComposeOriginalPostView.swift
//  moro
//
//  Lightweight reply/quote context summary shown above the editor.
//

import SwiftUI

struct ComposeOriginalPostView: View {
    enum PresentationStyle {
        case reply
        case quote
    }

    let status: Status
    let presentationStyle: PresentationStyle

    @Environment(\.moroTheme) private var theme

    private var summary: ComposeOriginalPostSummary {
        ComposeOriginalPostSummary(
            status: status.displayStatus,
            presentationStyle: presentationStyle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.showsContextLabel {
                Label {
                    Text(summary.contextLabel)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: summary.contextIcon)
                        .moroScaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                MoroAvatar(
                    imageURL: summary.status.account.avatarAnimatedURL,
                    staticImageURL: summary.status.account.avatarURL,
                    initials: summary.status.account.displayNameInitials, seed: summary.status.account.placeholderSeed,
                    size: 22
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            AccountDisplayNameView(
                                account: summary.status.account,
                                typography: .bodyStrong,
                                textColor: theme.colors.textPrimary,
                                lineLimit: 1
                            )

                            Text(summary.accountHandle)
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(DateFormatting.relativeString(for: summary.status.createdAt))
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }

                    Text(summary.previewText)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !summary.badges.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(summary.badges) { badge in
                                Label {
                                    Text(badge.text)
                                        .font(theme.typography.caption)
                                } icon: {
                                    Image(systemName: badge.icon)
                                        .moroScaledFont(size: 11, weight: .medium)
                                }
                                .foregroundStyle(theme.colors.textSecondary)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ComposeOriginalPostSummary: Equatable {
    struct Badge: Identifiable, Equatable {
        let id: String
        let icon: String
        let text: String
    }

    let status: Status
    let presentationStyle: ComposeOriginalPostView.PresentationStyle

    var showsContextLabel: Bool {
        presentationStyle == .quote
    }

    var contextLabel: String {
        switch presentationStyle {
        case .reply:
            return MoroL10n.ComposeOriginal.replyTo(accountHandle)
        case .quote:
            return MoroL10n.ComposeOriginal.quoting(accountHandle)
        }
    }

    var contextIcon: String {
        switch presentationStyle {
        case .reply:
            return "arrowshape.turn.up.left"
        case .quote:
            return "quote.bubble"
        }
    }

    var accountHandle: String {
        let acct = status.account.acct
        return acct.hasPrefix("@") ? acct : "@\(acct)"
    }

    var previewText: String {
        let spoiler = status.spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spoiler.isEmpty {
            return spoiler
        }

        let plainContent = HTMLParser.stripHTML(status.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !plainContent.isEmpty {
            return plainContent
        }

        return fallbackSummary
    }

    var badges: [Badge] {
        var items: [Badge] = []

        if !(status.spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            items.append(Badge(id: "cw", icon: "exclamationmark.triangle", text: MoroL10n.ComposeOriginal.badgeCW))
        }

        if !status.mediaAttachments.isEmpty {
            let count = status.mediaAttachments.count
            items.append(Badge(
                id: "media",
                icon: "photo.on.rectangle",
                text: count == 1 ? MoroL10n.ComposeOriginal.badgeMediaSingular : MoroL10n.ComposeOriginal.badgeMediaPlural(count)
            ))
        }

        if status.poll != nil {
            items.append(Badge(id: "poll", icon: "chart.bar", text: MoroL10n.ComposeOriginal.badgePoll))
        }

        if status.quote?.displayableStatus != nil {
            items.append(Badge(id: "quote", icon: "quote.bubble", text: MoroL10n.ComposeOriginal.badgeQuote))
        }

        return items
    }

    private var fallbackSummary: String {
        let parts = badges.map(\.text)
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return MoroL10n.ComposeOriginal.fallbackTitle
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
    
    ComposeOriginalPostView(
        status: sampleStatus,
        presentationStyle: .reply
    )
        .moroTheme(MoroTheme())
        .padding()
}
