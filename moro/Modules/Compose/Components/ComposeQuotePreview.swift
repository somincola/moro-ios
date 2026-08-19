//
//  ComposeQuotePreview.swift
//  moro
//
//  Preview component for quoted post in compose view.
//  Displays quoted content with indentation, truncated to 3 lines, non-clickable.
//

import SwiftUI

struct ComposeQuotePreview: View {
    let quote: Status
    
    @Environment(\.moroTheme) private var theme
    
    // Cache parsed content to avoid re-parsing on every view update
    private var parsedContent: String {
        HTMLParser.stripHTML(quote.content)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble")
                    .moroScaledFont(size: 11, weight: .semibold)
                Text(MoroL10n.ComposeQuote.previewTitle)
                    .font(theme.typography.caption)
            }
            .foregroundStyle(theme.colors.textSecondary)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        MoroAvatar(
                            imageURL: quote.account.avatarAnimatedURL,
                            staticImageURL: quote.account.avatarURL,
                            initials: quote.account.displayNameInitials,
                            size: 16
                        )

                        AccountDisplayNameView(
                            account: quote.account,
                            typography: .captionStrong,
                            textColor: theme.colors.textPrimary,
                            lineLimit: 1
                        )

                        Text("@\(quote.account.username)")
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                    }

                    Text(parsedContent)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(theme.colors.surfaceSubtle.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 0,
        followingCount: 0,
        statusesCount: 0
    )
    
    let sampleQuote = Status(
        id: "1",
        content: "<p>This is a quoted post with some content that might be very long and should be truncated to 3 lines maximum. This is line 1. This is line 2. This is line 3. This is line 4 which should not be visible.</p>",
        createdAt: Date(),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 0,
        reblogsCount: 0,
        repliesCount: 0,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )
    
    ComposeQuotePreview(quote: sampleQuote)
        .moroTheme(MoroTheme())
        .padding()
}
