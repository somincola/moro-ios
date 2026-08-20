//
//  PinnedStatusCarousel.swift
//  moro
//
//  Horizontally scrollable carousel for displaying pinned statuses.
//

import SwiftUI

struct PinnedStatusCarousel: View {
    @Environment(\.moroTheme) private var theme

    let pinnedStatuses: [Status]
    let onStatusTap: (Status) -> Void

    @State private var selectedStatusID: String?
    @State private var availableWidth: CGFloat = 0
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var uniformCardHeight: CGFloat = 220

    // All pinned cards share ONE height — the tallest measured card, clamped — so
    // swiping left/right never resizes the carousel (and the profile content below it
    // never jumps). Shorter cards top-align with empty space beneath.
    private static let minCardHeight: CGFloat = 180
    private static let maxCardHeight: CGFloat = 460

    private var resolvedAvailableWidth: CGFloat {
        availableWidth > 0 ? availableWidth : 320
    }

    private var cardWidth: CGFloat {
        max(resolvedAvailableWidth - (theme.spacing.m * 2), 240)
    }

    private var stablePinnedStatuses: [Status] {
        PinnedStatusCarouselState.deduplicated(pinnedStatuses, id: { $0.id })
    }

    private var statusIDs: [String] {
        stablePinnedStatuses.map(\.id)
    }

    private var currentIndex: Int {
        guard let selectedStatusID,
              let index = statusIDs.firstIndex(of: selectedStatusID) else {
            return 0
        }
        return index
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            // Section Header
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "pin.fill")
                    .moroScaledFont(size: 14)
                    .foregroundStyle(theme.colors.primary500)
                
                Text(MoroL10n.PinnedCarousel.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                
                Spacer()

                // Page indicator
                if stablePinnedStatuses.count > 1 {
                    Text("\(currentIndex + 1)/\(stablePinnedStatuses.count)")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .padding(.horizontal, theme.spacing.m)

            // Native ScrollView paging avoids UIPageViewController transition assertions
            // when the server mutates pinned statuses during an active swipe.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(stablePinnedStatuses, id: \.id) { status in
                        PinnedStatusCard(
                            status: status,
                            maxCardWidth: cardWidth
                        ) {
                            onStatusTap(status)
                        }
                        .frame(width: cardWidth, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, theme.spacing.m)
                        .frame(
                            width: resolvedAvailableWidth,
                            height: uniformCardHeight,
                            alignment: .top
                        )
                        .id(status.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedStatusID)
            .frame(height: uniformCardHeight, alignment: .top)
            .background(alignment: .topLeading) {
                allCardHeightProbes
            }
            .onPreferenceChange(PinnedStatusHeightPreferenceKey.self) { heights in
                cardHeights.merge(heights) { _, new in new }
                recomputeUniformHeight()
            }

            // Page Dots (for multiple pinned statuses)
            if stablePinnedStatuses.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(statusIDs.enumerated()), id: \.element) { index, _ in
                        Capsule(style: .continuous)
                            .fill(
                                index == currentIndex
                                    ? theme.colors.primary500 : theme.colors.textSecondary.opacity(0.25)
                            )
                            .frame(width: index == currentIndex ? 14 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: currentIndex)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, theme.spacing.xs)
            }
        }
        .padding(.vertical, theme.spacing.m)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableWidth = max(proxy.size.width, 0)
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = max(newValue, 0)
                    }
            }
        )
        .onChange(of: statusIDs, initial: true) { previousIDs, newIDs in
            selectedStatusID = PinnedStatusCarouselState.reconciledSelection(
                currentID: selectedStatusID,
                previousIDs: previousIDs,
                newIDs: newIDs
            )

            let validIDs = Set(newIDs)
            cardHeights = cardHeights.filter { validIDs.contains($0.key) }

            guard !newIDs.isEmpty else {
                uniformCardHeight = 220
                return
            }

            recomputeUniformHeight(animated: false)
        }
    }

    /// Hidden measurement layer: lay out EVERY pinned card at its natural height and
    /// report each one keyed by stable status ID, so the shared height settles on the
    /// tallest from the start and remains correct across removal or reordering.
    private var allCardHeightProbes: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stablePinnedStatuses, id: \.id) { status in
                PinnedStatusCard(status: status, maxCardWidth: cardWidth) {}
                    .frame(width: cardWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PinnedStatusHeightPreferenceKey.self,
                                value: [status.id: proxy.size.height]
                            )
                        }
                    )
            }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Resolve the single shared height from the tallest measured card, clamped to a
    /// sane range. Animated only when it genuinely changes (data load / pin change),
    /// never on swipe — so the carousel height stays put while paging.
    private func recomputeUniformHeight(animated: Bool = true) {
        let measuredMax = cardHeights.values.max() ?? uniformCardHeight
        let target = min(max(measuredMax, Self.minCardHeight), Self.maxCardHeight)
        guard abs(target - uniformCardHeight) > 0.5 else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                uniformCardHeight = target
            }
        } else {
            uniformCardHeight = target
        }
    }
}

private struct PinnedStatusHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum PinnedStatusCarouselState {
    static func deduplicated<Element>(
        _ elements: [Element],
        id: (Element) -> String
    ) -> [Element] {
        var seenIDs = Set<String>()
        return elements.filter { seenIDs.insert(id($0)).inserted }
    }

    static func reconciledSelection(
        currentID: String?,
        previousIDs: [String],
        newIDs: [String]
    ) -> String? {
        guard let firstID = newIDs.first else { return nil }
        guard let currentID else { return firstID }

        if newIDs.contains(currentID) {
            return currentID
        }

        let newIDSet = Set(newIDs)
        let hasExistingPage = previousIDs.contains(where: newIDSet.contains)
        guard hasExistingPage,
              let previousIndex = previousIDs.firstIndex(of: currentID) else {
            return firstID
        }

        return newIDs[min(previousIndex, newIDs.count - 1)]
    }
}

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
    
    let sampleStatuses = [
        Status(
            id: "1",
            content: "<p>First pinned status with some important content.</p>",
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
        ),
        Status(
            id: "2",
            content: "<p>Second pinned status with different content.</p>",
            createdAt: Date().addingTimeInterval(-3600),
            account: sampleAccount,
            mediaAttachments: [],
            favouritesCount: 28,
            reblogsCount: 8,
            repliesCount: 3,
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
            uri: "https://mastodon.social/@testuser/2",
            url: URL(string: "https://mastodon.social/@testuser/2"),
            mentions: nil,
            tags: nil,
            emojis: nil,
            card: nil,
            poll: nil
        )
    ]
    
    PinnedStatusCarousel(pinnedStatuses: sampleStatuses, onStatusTap: { _ in })
        .background(Color.gray.opacity(0.1))
}
