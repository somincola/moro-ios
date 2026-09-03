//
//  PinnedStatusSection.swift
//  moro
//
//  Native timeline rows for a profile's pinned statuses.
//

import SwiftUI

struct PinnedStatusSection: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pinnedStatuses: [Status]
    var translationAPIClient: MastodonAPI? = nil
    var accountCache: AccountCache? = nil
    var postActions: (Status) -> PostActions = { _ in .empty }

    @State private var showsAllPinnedStatuses: Bool

    init(
        pinnedStatuses: [Status],
        translationAPIClient: MastodonAPI? = nil,
        accountCache: AccountCache? = nil,
        postActions: @escaping (Status) -> PostActions = { _ in .empty },
        initiallyExpanded: Bool = false
    ) {
        self.pinnedStatuses = pinnedStatuses
        self.translationAPIClient = translationAPIClient
        self.accountCache = accountCache
        self.postActions = postActions
        _showsAllPinnedStatuses = State(initialValue: initiallyExpanded)
    }

    private var stablePinnedStatuses: [Status] {
        PinnedStatusSectionState.deduplicated(pinnedStatuses, id: { $0.id })
    }

    private var visiblePinnedStatuses: [Status] {
        PinnedStatusSectionState.visibleStatuses(
            stablePinnedStatuses,
            showsAll: showsAllPinnedStatuses
        )
    }

    private var statusIDs: [String] {
        stablePinnedStatuses.map(\.id)
    }

    private var hiddenStatusCount: Int {
        PinnedStatusSectionState.hiddenCount(
            totalCount: stablePinnedStatuses.count,
            showsAll: showsAllPinnedStatuses
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            ForEach(Array(visiblePinnedStatuses.enumerated()), id: \.element.id) {
                index, status in
                TimelinePostRow(
                    status: status,
                    threadContext: .none,
                    translationAPIClient: translationAPIClient,
                    accountCache: accountCache,
                    actions: postActions(status)
                )
                .transition(.opacity)

                if index < visiblePinnedStatuses.count - 1 {
                    MoroDivider()
                }
            }

            if hiddenStatusCount > 0 {
                revealButton
            }
        }
        .background(theme.colors.surfaceBase)
        .onChange(of: statusIDs) { previousIDs, newIDs in
            if previousIDs != newIDs {
                showsAllPinnedStatuses = false
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "pin.fill")
                .moroScaledFont(size: 14)
                .foregroundStyle(theme.colors.primary500)

            Text(MoroL10n.PinnedPosts.title)
                .font(theme.typography.subtitle)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textPrimary)

            Text("\(stablePinnedStatuses.count)")
                .font(theme.typography.caption)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, theme.spacing.hairline)
                .padding(.vertical, theme.spacing.micro)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.colors.surfaceSubtle)
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.top, theme.spacing.m)
        .padding(.bottom, theme.spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var revealButton: some View {
        VStack(spacing: 0) {
            MoroDivider(leadingInset: theme.spacing.timelineDividerInset)

            Button {
                withAnimation(reduceMotion ? nil : AnimationTokens.easing.easeOutMD) {
                    showsAllPinnedStatuses = true
                }
            } label: {
                HStack(spacing: theme.spacing.s) {
                    Text(MoroL10n.PinnedPosts.viewAll)
                        .font(theme.typography.bodyStrong)

                    Image(systemName: "chevron.down")
                        .moroScaledFont(size: 11, weight: .semibold)
                }
                .foregroundStyle(theme.colors.primary500)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.pinnedPosts.viewAll")
        }
    }
}

enum PinnedStatusSectionState {
    static func deduplicated<Element>(
        _ elements: [Element],
        id: (Element) -> String
    ) -> [Element] {
        var seenIDs = Set<String>()
        return elements.filter { seenIDs.insert(id($0)).inserted }
    }

    static func visibleStatuses<Element>(
        _ elements: [Element],
        showsAll: Bool
    ) -> [Element] {
        showsAll ? elements : Array(elements.prefix(1))
    }

    static func hiddenCount(totalCount: Int, showsAll: Bool) -> Int {
        showsAll ? 0 : max(totalCount - 1, 0)
    }
}

#Preview("Pinned statuses — collapsed") {
    ScrollView {
        PinnedStatusSection(pinnedStatuses: pinnedStatusPreviewStatuses)
    }
    .moroTheme(MoroTheme())
}

#Preview("Pinned statuses — expanded") {
    ScrollView {
        PinnedStatusSection(
            pinnedStatuses: pinnedStatusPreviewStatuses,
            initiallyExpanded: true
        )
    }
    .moroTheme(MoroTheme())
}

private let pinnedStatusPreviewStatuses: [Status] = {
    let account = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200
    )

    return [
        Status(
            id: "1",
            content: "<p>First pinned status with important profile information.</p>",
            createdAt: Date(),
            account: account,
            mediaAttachments: [],
            favouritesCount: 42,
            reblogsCount: 12,
            repliesCount: 5,
            bookmarked: false,
            favourited: false,
            reblogged: false
        ),
        Status(
            id: "2",
            content: "<p>Second pinned status, revealed on demand.</p>",
            createdAt: Date().addingTimeInterval(-3600),
            account: account,
            mediaAttachments: [],
            favouritesCount: 28,
            reblogsCount: 8,
            repliesCount: 3,
            bookmarked: false,
            favourited: false,
            reblogged: false
        ),
    ]
}()
