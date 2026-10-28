//
//  TimelineHomeView+ScrollView.swift
//  moro
//
//  Per-timeline scroll view + loading states — extracted from TimelineHomeView as an extension (pure relocation, no behaviour change).
//

import SwiftUI
import UIKit
import Combine

extension TimelineHomeView {
    // MARK: - Timeline ScrollView (Independent for each timeline)

    @ViewBuilder
    func timelineScrollView(viewModel: TimelineViewModel, timelineType: TimelineType)
        -> some View
    {
        let pageSession = pageSessionStore.session(for: timelineType)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Scrollable spacer reserving room for the floating header. Being part of
                    // the content (not a fixed/animated inset), it scrolls away naturally and the
                    // content fills from the top — no layout jump or scroll feedback (= no jitter).
                    Color.clear
                        .frame(height: headerHeight)
                        .id("timeline-top")
                        .background(
                            TimelineScrollViewResolver(
                                timeline: timelineType,
                                bridge: scrollBridge
                            )
                        )

                    TimelinePullRefreshSlot(
                        maxHeight: pullRefreshReservedHeight,
                        subject: scrollBridge.pullRefreshSubject(for: timelineType),
                        bridge: scrollBridge,
                        timeline: timelineType
                    )

                    timelinePrimaryContent(for: viewModel, timelineType: timelineType)
                }
                .scrollTargetLayout()
                .moroReadableColumn()
                // Clear the compact footer, including the device bottom safe area. The timeline
                // remains edge to edge, while its final row stays fully reachable above the footer.
                .padding(.bottom, bottomContentInset + theme.spacing.s)
            }
            // Reliable scroll tracking (iOS 18+). The old GeometryReader + preference +
            // named coordinate space didn't fire inside the pager's per-timeline hosting
            // controller, so the header never hid. contentOffset.y grows positive scrolling
            // down; negate it to match the "minY-style" offset the header logic expects.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offsetY in
                guard isActive else { return }
                scrollBridge.updateGeometry(for: timelineType, headerHeight: headerHeight)
                if scrollBridge.isPresented(timelineType) {
                    pageSession.recordContentOffset(offsetY)
                }
                let crossedThreshold = scrollBridge.updatePullRefreshDistance(
                    max(0, -offsetY),
                    threshold: pullRefreshTriggerDistance,
                    for: timelineType,
                    isSelected: timelineType == selectedTimeline
                )
                if crossedThreshold {
                    MoroRefreshFeedback.armed()
                }
                handleScrollOffset(-offsetY, for: timelineType)
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                scrollBridge.updatePhase(newPhase, for: timelineType)
                if scrollBridge.isPresented(timelineType) {
                    pageSession.commitVisibleAnchor(for: newPhase)
                }
                guard isActive else { return }
                guard didReleasePull(oldPhase: oldPhase, newPhase: newPhase) else { return }
                startPullRefreshIfNeeded(
                    viewModel: viewModel,
                    timelineType: timelineType
                )
            }
            .onChange(of: viewModel.statuses.count) { _, _ in
                updateThreadContexts()
            }
            .onChange(of: viewModel.liveRevision) { _, _ in
                processLiveUpdates(for: timelineType, viewModel: viewModel)
            }
            .onChange(of: viewModel.timelineType) { _, _ in
                updateThreadContexts()
            }
            .onAppear {
                scrollBridge.register(proxy, for: timelineType)
                scrollBridge.updateGeometry(for: timelineType, headerHeight: headerHeight)
            }
        }
    }

    func didReleasePull(oldPhase: ScrollPhase, newPhase: ScrollPhase) -> Bool {
        ScrollPhase.releasedTouch(from: oldPhase, to: newPhase)
    }

    @MainActor
    func startPullRefreshIfNeeded(
        viewModel: TimelineViewModel,
        timelineType: TimelineType
    ) {
        guard scrollBridge.commitPullRefresh(
            for: timelineType,
            threshold: pullRefreshTriggerDistance,
            isSelected: timelineType == selectedTimeline
        ) else { return }

        Task { @MainActor in
            await performPullRefresh(
                viewModel: viewModel,
                timelineType: timelineType
            )
        }
    }

    /// Shared by a released pull and a tab re-tap at the top: both pin the same slot first.
    @MainActor
    func performPullRefresh(
        viewModel: TimelineViewModel,
        timelineType: TimelineType,
        trigger: TimelineViewModel.RefreshTrigger = .pull
    ) async {
        let indicatorStart = Date()
        let detectionSnapshot = detectionDimension(for: timelineType).map {
            detectionManager.snapshot(for: $0)
        }
        let result = await viewModel.refresh(trigger: trigger)

        switch result {
        case .success(let insertedCount, let replacedTimeline):
            if let detectionSnapshot {
                detectionManager.resolve(detectionSnapshot)
            }
            syncDetectionTopID(for: timelineType)
            // Confirm only when something arrived; "nothing new" just collapses the slot.
            MoroRefreshFeedback.deliver(.succeeded,
                confirmsSuccess: insertedCount > 0 || replacedTimeline)
        case .failure:
            MoroRefreshFeedback.deliver(.failed)
        case .cancelled:
            MoroRefreshFeedback.deliver(.cancelled)
        }

        let elapsed = Date().timeIntervalSince(indicatorStart)
        let remaining = minimumPullRefreshIndicatorDuration - elapsed
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        let savedAnchor = viewModel.savedReadingAnchor.flatMap { anchor in
            viewModel.statuses.contains { $0.id == anchor.statusID } ? anchor : nil
        }
        scrollBridge.finishPullRefresh(
            for: timelineType,
            preserving: savedAnchor,
            revision: viewModel.presentationRevision
        )
        if selectedTimeline == timelineType {
            processLiveUpdates(for: timelineType, viewModel: viewModel)
        }
    }

    private struct TimelinePullRefreshSlot: View {
        let maxHeight: CGFloat
        let subject: CurrentValueSubject<TimelinePullRefreshVisualState, Never>
        let bridge: TimelineScrollBridge
        let timeline: TimelineType

        @Environment(\.moroTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var state = TimelinePullRefreshVisualState.idle

        private var progress: CGFloat {
            min(max(state.distance / max(state.threshold, 1), 0), 1)
        }

        private var slotHeight: CGFloat {
            state.isPinned ? maxHeight : max(state.distance, 0)
        }

        private var entryProgress: CGFloat {
            min(max(state.distance / max(maxHeight, 1), 0), 1)
        }

        private var iconOpacity: Double {
            min(max(Double(entryProgress), 0), 1)
        }

        private var iconOffset: CGFloat {
            let centeredY = (maxHeight - 28) / 2
            return state.isRefreshing ? centeredY : -18 + (centeredY + 18) * entryProgress
        }

        var body: some View {
            ZStack(alignment: .top) {
                HStack {
                    Spacer()
                    indicator
                    Spacer()
                }
                .offset(y: iconOffset)
            }
            .frame(height: slotHeight)
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height <= 0.5 { bridge.pullRefreshSlotDidCollapse(for: timeline) }
            }
            .onAppear {
                if slotHeight <= 0.5 { bridge.pullRefreshSlotDidCollapse(for: timeline) }
            }
            .onReceive(subject) { nextState in
                if isExpandingFromRest(to: nextState) {
                    // A tab re-tap pins the slot with no pull before it: open it smoothly
                    // so the rows visibly make room, like a released pull.
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { state = nextState }
                } else if isCollapsing(to: nextState) {
                    // The slot is off screen while reading. An immediate layout
                    // lets the bridge restore the anchor once, without animating
                    // the entire timeline upward under the reader.
                    let atTop = bridge.isAtTop(timeline)
                    var transaction = Transaction(animation: atTop ? .easeOut(duration: 0.24) : nil)
                    transaction.disablesAnimations = !atTop
                    withTransaction(transaction) { state = nextState }
                } else {
                    state = nextState
                }
            }
            .animation(.easeOut(duration: 0.16), value: state.isRefreshing)
        }

        private func isExpandingFromRest(to nextState: TimelinePullRefreshVisualState) -> Bool {
            !state.isPinned && state.distance <= 0 && nextState.isPinned
        }

        private func isCollapsing(to nextState: TimelinePullRefreshVisualState) -> Bool {
            state.isPinned
                && !nextState.isPinned
                && !nextState.isRefreshing
                && nextState.distance <= 0
        }

        @ViewBuilder
        private var indicator: some View {
            MoroPetalSpinner(
                progress: progress,
                isAnimating: state.isRefreshing,
                style: .timeline,
                tint: .twoTone(active: theme.colors.textSecondary, inactive: theme.colors.borderSubtle)
            )
            .opacity(iconOpacity)
            .scaleEffect(0.78 + 0.22 * entryProgress)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    func timelinePrimaryContent(
        for viewModel: TimelineViewModel, timelineType: TimelineType
    )
        -> some View
    {
        switch timelineContentState(for: viewModel, timelineType: timelineType) {
        case .loading:
            timelineLoadingRows
        case .loaded:
            if case .list = timelineType, case .failed = viewModel.refreshState {
                TimelineCachedContentNotice { Task { await viewModel.refresh() } }
            }
            timelineStatusRows(for: viewModel, timelineType: timelineType)
        case .empty(let spec):
            timelineStateCard(
                icon: spec.icon,
                title: spec.title,
                message: spec.message,
                actionTitle: spec.actionTitle,
                action: spec.action
            )
        case .error(let spec):
            timelineStateCard(
                icon: "exclamationmark.triangle",
                title: spec.title,
                message: spec.message,
                actionTitle: spec.action == nil ? nil : spec.actionTitle,
                action: spec.action
            )
        }
    }

    @ViewBuilder
    func timelineStatusRows(for viewModel: TimelineViewModel, timelineType: TimelineType)
        -> some View
    {
        let pageSession = pageSessionStore.session(for: timelineType)
        // Grouped once per pass instead of filtering every gap for every row.
        let retryGapsByAfterID = Dictionary(
            grouping: viewModel.gaps.filter { viewModel.failedGapIDs.contains($0.id) },
            by: \.afterID
        )

        ForEach(viewModel.statuses.indexed(), id: \.element.id) { index, status in
            let context = threadContext(for: status)
            let prefetchWindowSize = 2
            let canRunPrefetch = hasFinishedInitialLoad(for: timelineType)
            let isNearBottom = viewModel.statuses.count - index <= 3
            TimelinePostRow(
                status: status,
                threadContext: context,
                translationAPIClient: apiClient,
                accountCache: viewModel.accountCache,
                actions: handlers.buildPostActions(
                    for: status,
                    onPollVote: { pollID, choices in
                        await viewModel.votePoll(pollID: pollID, choices: choices)
                    }
                )
            )
            .id(status.id)
            .background(TimelineRowAnchor(statusID: status.id, timeline: timelineType,
                revision: viewModel.presentationRevision, bridge: scrollBridge))
            .accessibilityIdentifier("timeline.row.\(status.id)")
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: 1)
                    .offset(y: -headerHeight)
                    .id(timelineHeaderSafeAnchorID(for: status.id))
            }
            .onScrollVisibilityChange(threshold: 0.05) { isVisible in
                guard scrollBridge.isPresented(timelineType) else { return }
                pageSession.updateVisibility(
                    statusID: status.id,
                    index: index,
                    isVisible: isVisible
                )

            }
            .onAppear {
                if timelineType == .home,
                    selectedTimeline == .home,
                    index == 0
                {
                    StartupPerformanceTracker.shared.markTimelineFirstContentReady(
                        count: viewModel.statuses.count,
                        source: "first-cell-appear"
                    )
                }

                if canRunPrefetch, timelineType == .home, scrollBridge.hasScrolledHome,
                    index < prefetchWindowSize, selectedTimeline == timelineType
                {
                    Task(priority: .utility) {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        guard selectedTimeline == timelineType else { return }
                        await StatusDetailPrefetchCoordinator.shared.prefetchStatusAndQuoteIfNeeded(
                            for: status.displayStatus,
                            apiClient: apiClient,
                            threadCache: cacheManager.threadCache,
                            accountCache: cacheManager.accountCache
                        )
                    }
                }

                if isNearBottom, viewModel.hasMore
                {
                    Task {
                        await viewModel.loadMore(triggeredByStatusID: status.id)
                    }
                }
            }

            MoroDivider(leadingInset: theme.spacing.timelineDividerInset, height: 0.5)

            // Unverified intervals are resolved quietly. Only a failed request
            // needs an action in the timeline; its appearance is anchor-preserved.
            ForEach(retryGapsByAfterID[status.id] ?? []) { gap in
                Button {
                    Task { await viewModel.loadGap(id: gap.id) }
                } label: {
                    HStack(spacing: theme.spacing.s) {
                        if viewModel.loadingGapIDs.contains(gap.id) { ProgressView() }
                        Text(MoroL10n.Timeline.gapRetry)
                    }
                    .font(theme.typography.caption)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.textSecondary)
                .disabled(viewModel.loadingGapIDs.contains(gap.id))
                .accessibilityIdentifier("timeline.gap.\(gap.beforeID)")
            }
        }

        if case .loadingMore = viewModel.loadingState {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, theme.spacing.m)
                Spacer()
            }
        } else if viewModel.loadMoreFailed {
            PaginationFooter(
                isLoadingMore: false,
                didFail: true,
                onRetry: { Task { await viewModel.loadMore() } }
            )
            .accessibilityIdentifier("timeline.pagination.retry")
        } else if !viewModel.hasMore && !viewModel.statuses.isEmpty {
            HStack {
                Spacer()
                Text(MoroL10n.Timeline.noMore)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.vertical, theme.spacing.m)
                Spacer()
            }
        }
    }

    @ViewBuilder
    var timelineLoadingRows: some View {
        ForEach(0..<6, id: \.self) { _ in
            HStack(alignment: .top, spacing: theme.spacing.m) {
                Circle()
                    .fill(theme.colors.skeleton)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.colors.skeleton)
                        .frame(width: 122, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.colors.skeleton)
                        .frame(height: 11)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.colors.skeleton)
                        .frame(width: 190, height: 11)
                }
            }
            .padding(.horizontal, theme.spacing.timelinePadding)
            .padding(.vertical, theme.spacing.timelineVertical)

            MoroDivider()
                .padding(.leading, theme.spacing.timelinePadding)
        }
    }

    func timelineStateCard(
        icon: String,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            MoroSectionTextBlock(
                title: title,
                message: message,
                icon: icon,
                tint: theme.colors.textTertiary
            )

            if let actionTitle, let action {
                MoroButton(title: actionTitle, kind: .secondary, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, theme.spacing.timelinePadding)
        .padding(.vertical, 42)
    }

    @ViewBuilder
    func timelineContextCard(for timelineType: TimelineType, viewModel: TimelineViewModel)
        -> some View
    {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: timelineType.icon)
                    .moroScaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(theme.colors.primary500.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: theme.spacing.micro) {
                    Text(timelineType.localizedTitle)
                        .font(theme.typography.subtitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(timelineType.description)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer()

                Text(MoroL10n.Timeline.statusCount(viewModel.statuses.count))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            HStack(spacing: theme.spacing.hairline) {
                timelineMetaChip(icon: "dot.radiowaves.left.and.right", text: MoroL10n.Timeline.streamConnected)
                if currentDetectionCount > 0 {
                    timelineMetaChip(
                        icon: "arrow.up.circle", text: MoroL10n.Timeline.pendingCheck(currentDetectionCount))
                }
                if viewModel.hasMore {
                    timelineMetaChip(icon: "chevron.down", text: MoroL10n.Timeline.canLoadMore)
                }
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .moroCardSurface(cornerRadius: 12, tone: .subtle)
    }

    @ViewBuilder
    func timelineMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: icon)
                .moroScaledFont(size: 10, weight: .semibold)
            Text(text)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, theme.spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(theme.colors.surfaceBase)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }

    func timelineContentState(for viewModel: TimelineViewModel, timelineType: TimelineType)
        -> ContentState
    {
        if viewModel.statuses.isEmpty, !hasLoadedTimeline(timelineType) {
            return .loading(.timeline)
        }
        if viewModel.statuses.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.timeline)
        }
        if viewModel.statuses.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Timeline.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Timeline.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    }
                ))
        }
        if viewModel.statuses.isEmpty {
            return .empty(emptyStateSpec(for: timelineType, viewModel: viewModel))
        }
        return .loaded
    }

    func hasLoadedTimeline(_ timelineType: TimelineType) -> Bool {
        switch timelineType {
        case .home:
            return hasLoadedHome
        case .local:
            return hasLoadedLocal
        case .federated:
            return hasLoadedFederated
        case .list:
            return loadedPinnedTimelineIDs.contains(timelineType.id)
        }
    }

    func emptyStateSpec(for timelineType: TimelineType, viewModel: TimelineViewModel)
        -> EmptyStateSpec
    {
        switch timelineType {
        case .home:
            return EmptyStateSpec(
                icon: "person.2",
                title: MoroL10n.Timeline.emptyHomeTitle,
                message: MoroL10n.Timeline.emptyHomeMessage,
                actionTitle: MoroL10n.Timeline.refresh,
                action: {
                    Task { await viewModel.refresh() }
                }
            )
        case .local:
            return EmptyStateSpec(
                icon: "building.2",
                title: MoroL10n.Timeline.emptyLocalTitle,
                message: MoroL10n.Timeline.emptyLocalMessage,
                actionTitle: MoroL10n.Timeline.refresh,
                action: {
                    Task { await viewModel.loadInitial() }
                }
            )
        case .federated:
            return EmptyStateSpec(
                icon: "globe",
                title: MoroL10n.Timeline.emptyFederatedTitle,
                message: MoroL10n.Timeline.emptyFederatedMessage,
                actionTitle: MoroL10n.Timeline.refresh,
                action: {
                    Task { await viewModel.loadInitial() }
                }
            )
        case .list:
            return EmptyStateSpec(
                icon: "list.bullet.rectangle",
                title: MoroL10n.Lists.timelineEmptyTitle,
                message: MoroL10n.Lists.timelineEmptyMessage,
                actionTitle: MoroL10n.Timeline.refresh,
                action: {
                    Task { await viewModel.loadInitial() }
                }
            )
        }
    }

    // MARK: - Timeline Loading

    func loadTimeline(type: TimelineType) async {
        // Update timeline type in view model
        viewModel.timelineType = type
        // Clear existing statuses and load new timeline
        viewModel.clearStatuses()
        await viewModel.loadInitial()
    }

}
