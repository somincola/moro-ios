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
            headerHeight: headerHeight,
            bridge: scrollBridge
        ) {
            loadDetectedPosts(scrollToTop: true, providesFeedback: true)
        }
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

    var bottomRemoteSyncUndoIndicator: some View {
        TimelineRemoteSyncUndoOverlay(
            timeline: selectedTimeline,
            undoState: selectedTimeline == .home ? viewModel.remoteSyncUndoState : nil,
            bottomInset: bottomContentInset,
            bridge: scrollBridge,
            onUndo: { undoRemoteMarkerSync() },
            onUserScroll: { viewModel.dismissRemoteSyncUndo() }
        )
    }

    func undoRemoteMarkerSync() {
        guard selectedTimeline == .home,
            let previousAnchor = homeViewModel.undoRemoteMarkerSync()
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scrollBridge.holdReadingPosition(previousAnchor, for: .home)
        scrollBridge.restoreReadingAnchor(previousAnchor, for: .home)
    }

    func processLiveUpdates(for timeline: TimelineType, viewModel target: TimelineViewModel) {
        guard target.hasReadingState,
            !target.isAwaitingInitialCacheCheck,
            scrollBridge.canPresentUpdates(for: timeline)
        else { return }
        let session = pageSessionStore.session(for: timeline)
        if let jump = target.peekPendingRemoteSyncJump() {
            if scrollBridge.isUserScrolling(timeline) || scrollBridge.isUserDragging(timeline) {
                target.discardPendingRemoteSyncJump()
            } else {
                let canAdoptRemote: Bool
                if jump.requiresRestoredHold {
                    canAdoptRemote = !session.hasRestoredReadingAnchor
                        || scrollBridge.isHoldingRestoredAnchor(for: timeline)
                } else {
                    canAdoptRemote = true
                }

                if !canAdoptRemote {
                    target.discardPendingRemoteSyncJump()
                } else if target.hasUnappliedUpdates {
                    session.hasRestoredReadingAnchor = true
                    scrollBridge.holdReadingPosition(jump.anchor, for: timeline)
                    if scrollBridge.prepareContentUpdate(
                        for: timeline,
                        revision: target.presentationRevision + 1,
                        retainedIDs: target.canonicalStatusIDs,
                        targetAnchor: jump.anchor
                    ) {
                        _ = target.consumePendingRemoteSyncJump()
                        target.applyLiveUpdates()
                        presentUndoIfNeeded(for: jump, on: target)
                        return
                    }
                } else if target.statuses.contains(where: { $0.id == jump.anchor.statusID }) {
                    _ = target.consumePendingRemoteSyncJump()
                    session.hasRestoredReadingAnchor = true
                    scrollBridge.holdReadingPosition(jump.anchor, for: timeline)
                    scrollBridge.restoreReadingAnchor(jump.anchor, for: timeline)
                    presentUndoIfNeeded(for: jump, on: target)
                    return
                }
            }
        }
        if !session.hasRestoredReadingAnchor, !target.statuses.isEmpty {
            session.hasRestoredReadingAnchor = true
            // Back soon after leaving: reopen where the reader was. After a longer absence
            // the timeline starts at the top with the latest posts.
            if TimelineLaunchPolicy.restoresReadingPosition,
                let saved = target.savedReadingAnchor,
                target.statuses.contains(where: { $0.id == saved.statusID }) {
                scrollBridge.holdReadingPosition(saved, for: timeline)
                scrollBridge.restoreReadingAnchor(saved, for: timeline)
                return
            }
            scrollBridge.endRestoreVeil(for: timeline)
        }
        if target.hasUnappliedUpdates {
            let preferredAnchorID = target.pendingPreferredGapAnchorID
            guard scrollBridge.prepareContentUpdate(
                for: timeline,
                revision: target.presentationRevision + 1,
                retainedIDs: target.canonicalStatusIDs,
                preferredAnchorID: preferredAnchorID
            ) else { return }
            _ = target.consumePendingPreferredGapAnchorID()
            target.applyLiveUpdates()
            return // The matching row layout event will finish the transaction.
        }
        if scrollBridge.latestIsVisible(for: timeline, statusID: target.statuses.first?.id,
            revision: target.presentationRevision) {
            target.acknowledgePresentedUpdates(through: target.presentedSequence)
        }
        let visibleAnchors = scrollBridge.readingAnchors(for: timeline)
        if let held = scrollBridge.heldRestoredAnchor(for: timeline) {
            if target.statuses.contains(where: { $0.id == held.statusID }) {
                // Keep the restored anchor untouched until the reader actively scrolls or
                // jumps to the latest; passive layout drift must never overwrite saved progress.
                target.fillRecentGapsIfNeeded(near: Set(visibleAnchors.map(\.statusID)))
                return
            }
            scrollBridge.releaseRestoredAnchorHold(for: timeline)
        }
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
            target.dismissRemoteSyncUndo()
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

    private func presentUndoIfNeeded(
        for jump: TimelineViewModel.PendingRemoteSyncJump,
        on target: TimelineViewModel
    ) {
        guard let previous = jump.previousAnchor,
            previous.statusID != jump.anchor.statusID
        else { return }
        target.presentRemoteSyncUndo(
            previousAnchor: previous,
            syncedStatusID: jump.anchor.statusID,
            autoDismissAfter: UIAccessibility.isVoiceOverRunning ? 10.0 : 5.0
        )
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
    let headerHeight: CGFloat
    let bridge: TimelineScrollBridge
    let onTap: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtTop: Bool
    @State private var compactTimelines: Set<TimelineType> = []
    /// A pull to refresh is in progress: it brings the new posts in itself, so the notice
    /// steps aside instead of flashing a count that the refresh is about to clear.
    @State private var isPullRefreshing = false
    @State private var headerFraction: CGFloat

    init(
        timeline: TimelineType,
        count: Int,
        hasMore: Bool,
        isEnabled: Bool,
        headerHeight: CGFloat,
        bridge: TimelineScrollBridge,
        onTap: @escaping () -> Void
    ) {
        self.timeline = timeline
        self.count = count
        self.hasMore = hasMore
        self.isEnabled = isEnabled
        self.headerHeight = headerHeight
        self.bridge = bridge
        self.onTap = onTap
        _isAtTop = State(initialValue: bridge.isAtTop(timeline))
        _headerFraction = State(initialValue: bridge.currentChromeState.headerFraction)
    }

    private var hasPendingPosts: Bool { count > 0 || hasMore }
    private var isCompact: Bool { compactTimelines.contains(timeline) }
    private var visibleHeaderOffset: CGFloat {
        headerHeight * (1 - min(max(headerFraction, 0), 1))
    }

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
        .padding(.top, visibleHeaderOffset)
        .onReceive(bridge.chromeStateSubject) { nextState in
            let nextFraction = min(max(nextState.headerFraction, 0), 1)
            guard abs(nextFraction - headerFraction) > 0.0005 else { return }
            if nextState.isAnimated && !reduceMotion {
                withAnimation(.snappy(duration: 0.24)) {
                    headerFraction = nextFraction
                }
            } else {
                headerFraction = nextFraction
            }
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

private struct TimelineRemoteSyncUndoOverlay: View {
    let timeline: TimelineType
    let undoState: TimelineViewModel.RemoteSyncUndoState?
    let bottomInset: CGFloat
    let bridge: TimelineScrollBridge
    let onUndo: () -> Void
    let onUserScroll: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if undoState != nil {
                pill
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.bottom, max(bottomInset, 20))
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: undoState != nil)
        .onReceive(bridge.userScrollEvents) { source in
            guard source == timeline, undoState != nil else { return }
            onUserScroll()
        }
        .onChange(of: undoState) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: MoroL10n.Timeline.remoteSyncNotice
                )
            }
        }
    }

    private var pill: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    messageLabel
                    undoButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    messageLabel
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 1, height: 14)
                        .accessibilityHidden(true)
                    undoButton
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .frame(minHeight: 44)
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
    }

    private var messageLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .moroScaledFont(size: 12, weight: .medium)
                .foregroundStyle(Color.white.opacity(0.76))
                .accessibilityHidden(true)
            Text(MoroL10n.Timeline.remoteSyncNotice)
                .font(theme.typography.caption)
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Text(MoroL10n.Timeline.remoteSyncUndo)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MoroL10n.Timeline.remoteSyncNotice), \(MoroL10n.Timeline.remoteSyncUndo)")
        .accessibilityIdentifier("timeline.remoteSyncUndo")
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? theme.colors.surfaceElevated : theme.colors.textPrimary
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
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
