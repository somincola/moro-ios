import SwiftUI

extension TimelineHomeView {
    var currentDetectionCount: Int { viewModel.newPostCount }

    var topIndicator: some View {
        TimelineNewPostsNotice(
            timeline: selectedTimeline,
            count: currentDetectionCount,
            hasMore: viewModel.newPostsHaveMore,
            isEnabled: settings.timelineInAppNewPostBannerEnabled,
            isRefreshing: showsTopRefreshIndicator,
            bridge: scrollBridge
        ) {
            loadDetectedPosts(scrollToTop: true, providesFeedback: true)
        }
        .padding(.top, headerHeight + 8)
    }

    var showsTopRefreshIndicator: Bool {
        guard case .refreshing(let trigger) = viewModel.refreshState else { return false }
        return trigger == .tabRetap || trigger == .compose
    }

    func refreshCurrentTimelineFromTab() {
        let timeline = selectedTimeline
        let target = viewModel
        MoroRefreshFeedback.armed()
        Task { @MainActor in
            let result = await target.refresh(trigger: .tabRetap)
            guard selectedTimeline == timeline else { return }
            if result.succeeded {
                processLiveUpdates(for: timeline, viewModel: target)
                syncDetectionTopID(for: timeline)
            } else if case .failure = result {
                MoroRefreshFeedback.deliver(.failed)
            }
        }
    }

    func processLiveUpdates(for timeline: TimelineType, viewModel target: TimelineViewModel) {
        guard target.hasReadingState, scrollBridge.canPresentUpdates(for: timeline) else { return }
        let session = pageSessionStore.session(for: timeline)
        if !session.hasRestoredReadingAnchor, !target.statuses.isEmpty {
            session.hasRestoredReadingAnchor = true
            if let saved = target.savedReadingAnchor {
                scrollBridge.restoreReadingAnchor(saved, for: timeline)
                return
            }
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
    let isRefreshing: Bool
    let bridge: TimelineScrollBridge
    let onTap: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtTop: Bool
    @State private var compactTimelines: Set<TimelineType> = []

    init(
        timeline: TimelineType,
        count: Int,
        hasMore: Bool,
        isEnabled: Bool,
        isRefreshing: Bool,
        bridge: TimelineScrollBridge,
        onTap: @escaping () -> Void
    ) {
        self.timeline = timeline
        self.count = count
        self.hasMore = hasMore
        self.isEnabled = isEnabled
        self.isRefreshing = isRefreshing
        self.bridge = bridge
        self.onTap = onTap
        _isAtTop = State(initialValue: bridge.isAtTop(timeline))
    }

    private var hasPendingPosts: Bool { count > 0 || hasMore }
    private var isCompact: Bool { compactTimelines.contains(timeline) }

    var body: some View {
        VStack {
            if isEnabled, !isAtTop, hasPendingPosts {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: onTap) {
                        if isCompact {
                            TimelineNewPostsBadge(text: compactText)
                                .frame(minWidth: 44, minHeight: 44)
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
                .padding(.horizontal, theme.spacing.m)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isCompact)
            } else if isRefreshing {
                MoroNoticePill(icon: "arrow.trianglehead.2.clockwise", text: MoroL10n.Timeline.refreshing)
                    .frame(maxWidth: 280)
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

    var body: some View {
        Text(text)
            .moroScaledFont(size: 13, weight: .semibold)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 28, minHeight: 28)
            .foregroundStyle(.white)
            .background(colorScheme == .dark ? theme.colors.surfaceElevated : theme.colors.textPrimary)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(colorScheme == .dark ? Color.white.opacity(0.12) : .black.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 6, y: 2)
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
