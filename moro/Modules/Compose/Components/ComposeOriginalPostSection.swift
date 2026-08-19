//
//  ComposeOriginalPostSection.swift
//  moro
//
//  Section component for displaying reply/quote context above the editor.
//

import SwiftUI

struct ComposeOriginalPostSection: View {
    let originalStatus: Status
    let presentationStyle: ComposeOriginalPostView.PresentationStyle

    @Environment(\.moroTheme) private var theme
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(AnimationTokens.easing.springSoft) {
                    isExpanded.toggle()
                }
            } label: {
                if isExpanded {
                    expandedView
                } else {
                    collapsedView
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, theme.spacing.m)
            .padding(.top, 2)
            .padding(.bottom, theme.spacing.xs)

            MoroDivider()
        }
    }

    @ViewBuilder
    private var collapsedView: some View {
        let displayStatus = originalStatus.displayStatus
        let plainText = HTMLParser.stripHTML(displayStatus.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        HStack(spacing: 8) {
            MoroAvatar(
                imageURL: displayStatus.account.avatarAnimatedURL,
                staticImageURL: displayStatus.account.avatarURL,
                initials: displayStatus.account.displayNameInitials,
                size: 20
            )

            AccountDisplayNameView(
                account: displayStatus.account,
                typography: .caption,
                textColor: theme.colors.textSecondary,
                lineLimit: 1
            )

            Text(plainText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            Image(systemName: "chevron.down")
                .moroScaledFont(size: 11, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    @ViewBuilder
    private var expandedView: some View {
        HStack(alignment: .top, spacing: 0) {
            ComposeOriginalPostView(
                status: originalStatus,
                presentationStyle: presentationStyle
            )

            Spacer(minLength: 4)

            Image(systemName: "chevron.up")
                .moroScaledFont(size: 11, weight: .medium)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.top, 4)
        }
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

    let sampleStatus = Status(
        id: "1",
        content: "This is the original post content.",
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

    ComposeOriginalPostSection(
        originalStatus: sampleStatus,
        presentationStyle: .reply
    )
        .moroTheme(MoroTheme())
}
