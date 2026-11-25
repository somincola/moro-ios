//
//  ComposeQuotePreview.swift
//  moro
//
//  Non-interactive quoted post preview inside ComposeView, sharing the
//  same compact X-inspired visual style as QuotedStatusCardView.
//

import SwiftUI

struct ComposeQuotePreview: View {
    let quote: Status

    var body: some View {
        QuotedStatusCardView(
            quote: quote,
            style: .flat,
            isInteractive: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MoroL10n.ComposeQuote.previewTitle)
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
        content: "<p>This is a quoted post with some content that might be very long and should be truncated cleanly inside the compose preview.</p>",
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
