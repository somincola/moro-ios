import SwiftUI

extension TimelineHomeView {
    var isCurrentTimelineAtTop: Bool { scrollBridge.isAtTop(selectedTimeline) }
    var currentDetectionCount: Int { viewModel.newPostCount }

    @ViewBuilder
    var topIndicator: some View {
        VStack {
            if settings.timelineInAppNewPostBannerEnabled, !isCurrentTimelineAtTop,
                currentDetectionCount > 0 || viewModel.newPostsHaveMore {
                Button {
                    loadDetectedPosts(scrollToTop: true, providesFeedback: true)
                } label: {
                    MoroNoticePill(icon: "arrow.up", text: newPostsNoticeText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeline.newPosts")
                .frame(maxWidth: 280)
                .padding(.horizontal, theme.spacing.m)
            } else if showsTopRefreshIndicator {
                MoroNoticePill(icon: "arrow.trianglehead.2.clockwise", text: MoroL10n.Timeline.refreshing)
                    .frame(maxWidth: 280)
            }
            Spacer()
        }
        .padding(.top, headerHeight + 8)
    }

    private var newPostsNoticeText: String {
        if currentDetectionCount > 99 { return MoroL10n.Timeline.newPostsMany }
        if viewModel.newPostsHaveMore {
            return currentDetectionCount > 0
                ? MoroL10n.Timeline.newPostsAtLeast(currentDetectionCount)
                : MoroL10n.Timeline.hasNewPosts
        }
        return MoroL10n.Timeline.newPosts(currentDetectionCount)
    }

    var showsTopRefreshIndicator: Bool {
        guard case .refreshing(let trigger) = viewModel.refreshState else { return false }
        return trigger == .tabRetap || trigger == .compose
    }

    func refreshCurrentTimelineFromTab() {
        let timeline = selectedTimeline
        let target = viewModel
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            let result = await target.refresh(trigger: .tabRetap)
            guard selectedTimeline == timeline else { return }
            if result.succeeded {
                processLiveUpdates(for: timeline, viewModel: target)
                syncDetectionTopID(for: timeline)
            } else if case .failure = result {
                AppFeedbackCenter.shared.showError(MoroL10n.Timeline.loadFailed)
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
        if let anchor = scrollBridge.readingAnchors(for: timeline).first {
            target.saveReadingAnchor(anchor)
            if timeline == .home, target.currentTopVisibleStatusID != anchor.statusID {
                target.currentTopVisibleStatusID = anchor.statusID
            }
        }
        target.fillRecentGapsIfNeeded()
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
