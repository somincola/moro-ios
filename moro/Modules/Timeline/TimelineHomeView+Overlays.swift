import Combine
import SwiftUI

extension TimelineHomeView {
    var currentDetectionCount: Int { viewModel.newPostCount }

    var topIndicator: some View {
        TimelineNewPostsNotice(
            timeline: selectedTimeline,
            count: currentDetectionCount,
            hasMore: viewModel.newPostsHaveMore,
            isEnabled: settings.timelineInAppNewPostBannerEnabled,
            bridge: scrollBridge
        ) {
            loadDetectedPosts(scrollToTop: true, providesFeedback: true)
        }
        // Flush with the header's bottom edge: the compact badge hangs from it, the full
        // notice keeps its own gap below.
        .padding(.top, headerHeight)
    }

    /// Re-tapping Home at the top is a pull without the finger: it opens the same petal slot
    /// and runs the same refresh, so it shows, finishes and keeps the reader's place the same.
    /// A re-tap while that refresh is still running is ignored.
    func refreshCurrentTimelineFromTab() {
        let timeline = selectedTimeline
        let target = viewModel
        guard scrollBridge.beginProgrammaticPullRefresh(
            for: timeline, threshold: pullRefreshTriggerDistance, isSelected: true)
        else { return }
        MoroRefreshFeedback.armed()
        Task { @MainActor in
            await performPullRefresh(viewModel: target, timelineType: timeline, trigger: .tabRetap)
        }
    }

    func processLiveUpdates(for timeline: TimelineType, viewModel target: TimelineViewModel) {
        guard target.hasReadingState, scrollBridge.canPresentUpdates(for: timeline) else { return }
        let session = pageSessionStore.session(for: timeline)
        if !session.hasRestoredReadingAnchor, !target.statuses.isEmpty {
            session.hasRestoredReadingAnchor = true
            // Back soon after leaving: reopen where the reader was. After a longer absence
            // the timeline starts at the top with the latest posts.
            if TimelineLaunchPolicy.restoresReadingPosition, let saved = target.savedReadingAnchor {
                scrollBridge.holdReadingPosition(for: timeline)
                scrollBridge.restoreReadingAnchor(saved, for: timeline)
                return
            }
            scrollBridge.endRestoreVeil(for: timeline)
        }
        if target.hasUnappliedUpdates {
            guard scrollBridge.prepareContentUpdate(for: timeline, revision: target.presentationRevision + 1, retainedIDs: target.canonicalStatusIDs) else { return }
            target.applyLiveUpdates()
            return // The matching row layout event will finish the transaction.
        }
        if scrollBridge.latestIsVisible(for: timeline, statusID: target.statuses.first?.id,
            revision: target.presentationRevision) {
            target.acknowledgePresentedUpdates(through: target.presentedSequence)
        }
        let visibleAnchors = scrollBridge.readingAnchors(for: timeline)
        if let anchor = visibleAnchors.first {
            target.saveReadingAnchor(anchor)
            if timeline == .home, target.currentTopVisibleStatusID != anchor.statusID {
                target.currentTopVisibleStatusID = anchor.statusID
            }
        }
        target.fillRecentGapsIfNeeded(near: Set(visibleAnchors.map(\.statusID)))
    }

    func loadDetectedPosts(scrollToTop: Bool, providesFeedback: Bool) {
        let timeline = selectedTimeline
        let target = viewModel
        if providesFeedback { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if scrollToTop {
            if target.hasUnappliedUpdates,
                scrollBridge.prepareContentUpdate(for: timeline,
                    revision: target.presentationRevision + 1, jumpToLatest: true) {
                target.applyLiveUpdates()
            } else {
                scrollBridge.scrollToTop(timeline)
            }
        } else {
            processLiveUpdates(for: timeline, viewModel: target)
        }
    }

    func detectionDimension(for timeline: TimelineType) -> TimelineDimension? {
        switch timeline {
        case .home: .following
        case .local: .local
        case .federated: .federated
        case .list: nil
        }
    }
}

private struct TimelineNewPostsNotice: View {
    let timeline: TimelineType
    let count: Int
    let hasMore: Bool
    let isEnabled: Bool
    let bridge: TimelineScrollBridge
    let onTap: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtTop: Bool
    @State private var compactTimelines: Set<TimelineType> = []
    /// A pull to refresh is in progress: it brings the new posts in itself, so the notice
    /// steps aside instead of flashing a count that the refresh is about to clear.
    @State private var isPullRefreshing = false

    init(
        timeline: TimelineType,
        count: Int,
        hasMore: Bool,
        isEnabled: Bool,
        bridge: TimelineScrollBridge,
        onTap: @escaping () -> Void
    ) {
        self.timeline = timeline
        self.count = count
        self.hasMore = hasMore
        self.isEnabled = isEnabled
        self.bridge = bridge
        self.onTap = onTap
        _isAtTop = State(initialValue: bridge.isAtTop(timeline))
    }

    private var hasPendingPosts: Bool { count > 0 || hasMore }
    private var isCompact: Bool { compactTimelines.contains(timeline) }

    var body: some View {
        VStack {
            if isEnabled, !isAtTop, !isPullRefreshing, hasPendingPosts {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: onTap) {
                        if isCompact {
                            // A tab hanging from the header's trailing corner; the 44pt hit
                            // area extends below the visible badge.
                            TimelineNewPostsBadge(text: compactText)
                                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                                .contentShape(Rectangle())
                        } else {
                            MoroNoticePill(icon: "arrow.up", text: noticeText)
                                .frame(maxWidth: 280)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(noticeText)
                    .accessibilityIdentifier("timeline.newPosts")
                    if !isCompact { Spacer(minLength: 0) }
                }
                .padding(.horizontal, isCompact ? 0 : theme.spacing.m)
                .padding(.top, isCompact ? 0 : 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isCompact)
            }
            Spacer()
        }
        .onReceive(bridge.atTopEvents) { source in
            guard source == timeline else { return }
            let value = bridge.isAtTop(source)
            guard isAtTop != value else { return }
            isAtTop = value
        }
        .onChange(of: timeline) { _, newTimeline in
            isAtTop = bridge.isAtTop(newTimeline)
            isPullRefreshing = Self.isPulling(bridge.pullRefreshSubject(for: newTimeline).value)
        }
        .onReceive(bridge.pullRefreshSubject(for: timeline)) { state in
            let pulling = Self.isPulling(state)
            guard isPullRefreshing != pulling else { return }
            isPullRefreshing = pulling
        }
        .onReceive(bridge.userScrollEvents) { source in
            guard source == timeline, hasPendingPosts else { return }
            compactTimelines.insert(timeline)
        }
        .onChange(of: hasPendingPosts, initial: true) { _, hasPending in
            if !hasPending {
                compactTimelines.remove(timeline)
            } else if bridge.isUserScrolling(timeline) {
                compactTimelines.insert(timeline)
            }
        }
    }

    private static func isPulling(_ state: TimelinePullRefreshVisualState) -> Bool {
        state.distance > 0 || state.isPinned || state.isRefreshing
    }

    private var compactText: String {
        if count > 99 { return "99+" }
        if count == 0 { return "•" }
        return count.formatted()
    }

    private var noticeText: String {
        if count > 99 { return MoroL10n.Timeline.newPostsMany }
        if count == 0, hasMore {
            return MoroL10n.Timeline.hasNewPosts
        }
        return MoroL10n.Timeline.newPosts(count)
    }
}

private struct TimelineNewPostsBadge: View {
    let text: String
    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Square where it meets the header (top) and the screen edge (trailing); only the
    /// free bottom-leading corner is rounded.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12,
            bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
    }

    var body: some View {
        Text(text)
            .moroScaledFont(size: 13, weight: .semibold)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .frame(minWidth: 44, minHeight: 30)
            .foregroundStyle(.white)
            .background(colorScheme == .dark ? theme.colors.surfaceElevated : theme.colors.textPrimary)
            .clipShape(shape)
            .overlay {
                if colorScheme == .dark { shape.stroke(Color.white.opacity(0.12), lineWidth: 1) }
            }
            // Cast downward only: the top edge sits on the header.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 4, y: 2)
    }
}

#Preview("New post notices") {
    VStack(spacing: 20) {
        MoroNoticePill(icon: "arrow.up", text: MoroL10n.Timeline.newPosts(20))
        HStack {
            Spacer()
            TimelineNewPostsBadge(text: "20")
            TimelineNewPostsBadge(text: "99+")
        }
    }
    .padding()
    .moroTheme(MoroTheme())
}
