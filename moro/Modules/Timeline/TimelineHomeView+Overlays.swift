//
//  TimelineHomeView+Overlays.swift
//  moro
//
//  Top new-posts/refresh indicator — extracted from TimelineHomeView as an extension (pure relocation, no behaviour change).
//

import SwiftUI

extension TimelineHomeView {
    // MARK: - Top Indicator

    /// Helper computed property to check if current timeline is at top
    var isCurrentTimelineAtTop: Bool {
        scrollBridge.isAtTop(selectedTimeline)
    }

    @ViewBuilder
    var topIndicator: some View {
        VStack {
            if settings.timelineInAppNewPostBannerEnabled
                && currentDetectionCount > 0
                && isNewPostsIndicatorVisible
            {
                Button {
                    loadDetectedPosts(scrollToTop: true, providesFeedback: true)
                } label: {
                    MoroNoticePill(
                        icon: isLoadingDetectedPosts ? "arrow.trianglehead.2.clockwise" : "arrow.up",
                        text: isLoadingDetectedPosts
                            ? MoroL10n.Timeline.refreshing
                            : currentDetectionCount > 99
                                ? MoroL10n.Timeline.newPostsMany
                                : MoroL10n.Timeline.newPosts(currentDetectionCount)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingDetectedPosts)
                .frame(maxWidth: 280)
                .padding(.horizontal, theme.spacing.m)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if showsTopRefreshIndicator {
                MoroNoticePill(
                    icon: "arrow.trianglehead.2.clockwise",
                    text: MoroL10n.Timeline.refreshing
                )
                .frame(maxWidth: 280)
                .padding(.horizontal, theme.spacing.m)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.top, headerHeight + 8)
        .animation(.easeInOut(duration: 0.2), value: isNewPostsIndicatorVisible)
    }

    var showsTopRefreshIndicator: Bool {
        guard case .refreshing(let trigger) = viewModel.refreshState else { return false }
        switch trigger {
        case .tabRetap, .foreground, .compose:
            return true
        case .pull, .newPosts:
            return false
        }
    }

    func refreshCurrentTimelineFromTab() {
        let timeline = selectedTimeline
        let targetViewModel = viewModel
        let detectionSnapshot = detectionDimension(for: timeline).map {
            detectionManager.snapshot(for: $0)
        }
        guard !targetViewModel.isRefreshing else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            let result = await targetViewModel.refresh(trigger: .tabRetap)
            switch result {
            case .success:
                targetViewModel.clearPendingStatuses()
                if let detectionSnapshot {
                    detectionManager.resolve(detectionSnapshot)
                }
                syncDetectionTopID(for: timeline)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                AppFeedbackCenter.shared.showError(MoroL10n.Timeline.loadFailed)
            case .cancelled:
                break
            }
        }
    }

    func updateNewPostsIndicator(for count: Int) {
        guard count > 0 else {
            hideNewPostsIndicator()
            return
        }

        if isCurrentTimelineAtTop {
            hideNewPostsIndicator()
            loadDetectedPosts(scrollToTop: false, providesFeedback: false)
        } else if settings.timelineInAppNewPostBannerEnabled {
            showNewPostsIndicator()
        } else {
            hideNewPostsIndicator()
        }
    }

    func showNewPostsIndicator() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isNewPostsIndicatorVisible = true
        }
    }

    func hideNewPostsIndicator() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isNewPostsIndicatorVisible = false
        }
    }

    func loadDetectedPosts(scrollToTop: Bool, providesFeedback: Bool) {
        guard !isLoadingDetectedPosts,
            let dimension = detectionDimension(for: selectedTimeline)
        else { return }

        let timeline = selectedTimeline
        let detectedCount = detectionManager.newItemsCounts[dimension] ?? 0
        let detectionSnapshot = detectionManager.snapshot(for: dimension)
        let targetViewModel = viewModel
        guard detectedCount > 0 else { return }

        isLoadingDetectedPosts = true
        hideNewPostsIndicator()

        Task { @MainActor in
            let succeeded = await targetViewModel.fetchNewStatuses(
                force: true,
                providesFeedback: providesFeedback
            )
            if succeeded {
                detectionManager.resolve(detectionSnapshot)
            }

            isLoadingDetectedPosts = false
            guard selectedTimeline == timeline else {
                updateNewPostsIndicator(for: currentDetectionCount)
                return
            }

            if succeeded {
                syncDetectionTopID(for: timeline)
                if scrollToTop {
                    scrollBridge.resetChrome()
                    onChromeFraction?(0)
                    withAnimation {
                        scrollBridge.scrollToTop(timeline)
                    }
                }
                updateNewPostsIndicator(
                    for: detectionManager.newItemsCounts[dimension] ?? 0
                )
            } else if settings.timelineInAppNewPostBannerEnabled {
                showNewPostsIndicator()
            }
        }
    }

    func detectionDimension(for timeline: TimelineType) -> TimelineDimension? {
        switch timeline {
        case .home: return .following
        case .local: return .local
        case .federated: return .federated
        case .list: return nil
        }
    }

    /// Unified detection count for the currently selected timeline dimension
    var currentDetectionCount: Int {
        guard let dimension = detectionDimension(for: selectedTimeline) else { return 0 }
        return detectionManager.newItemsCounts[dimension] ?? 0
    }

}
