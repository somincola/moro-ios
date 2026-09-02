//
//  PinnedStatusCard.swift
//  moro
//
//  Timeline-card wrapper for displaying a pinned status in the carousel.
//

import SwiftUI

struct PinnedStatusCard: View {
    @Environment(\.moroTheme) private var theme

    let status: Status
    let cardWidth: CGFloat
    var translationAPIClient: MastodonAPI? = nil
    var accountCache: AccountCache? = nil
    var actions: PostActions = .empty

    var body: some View {
        TimelinePostRow(
            status: status,
            threadContext: .none,
            translationAPIClient: translationAPIClient,
            accountCache: accountCache,
            actions: actions
        )
        .frame(width: cardWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surfaceBase)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
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

    PinnedStatusCard(status: sampleStatus, cardWidth: 340)
        .padding()
        .background(Color.gray.opacity(0.1))
}
