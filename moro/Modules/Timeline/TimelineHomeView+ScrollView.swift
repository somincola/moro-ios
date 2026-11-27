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
                    // At least 1pt even without a header (iPhone Duo's system bar): a zero-height
                    // row never lays out its scroll-view resolver, and the pager stays blank.
                    Color.clear
                        .frame(height: max(headerHeight, 1))
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
                        .environment(\.moroPlaybackScope, scrollBridge.playbackScope(for: timelineType))
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
                    isSelected: timelineType == selectedTimeline,
                    isDragging: scrollBridge.isUserDragging(timelineType)
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
            .onChange(of: viewModel.pendingRemoteSyncedAnchor) { _, _ in
                processLiveUpdates(for: timelineType, viewModel: viewModel)
            }
            .onChange(of: viewModel.timelineType) { _, _ in
                updateThreadContexts()
            }
            .onAppear {
                scrollBridge.register(proxy, for: timelineType)
                scrollBridge.updateGeometry(for: timelineType, headerHeight: headerHeight)
                if TimelineLaunchPolicy.restoresReadingPosition, !pageSession.hasRestoredReadingAnchor {
                    scrollBridge.expectReadingRestore(for: timelineType)
                }
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
        switch trigger {
        case .pull: TabRetapRefreshTip.notePullToRefresh()
        case .tabRetap: TabRetapRefreshTip.noteTabRetap()
        default: break
        }
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
            EmptyStateView(spec: spec)
                .frame(minHeight: 340)
        case .error(let spec):
            ErrorStateView(spec: spec)
                .frame(minHeight: 340)
        }
    }

    @ViewBuilder
    func timelineStatusRows(for viewModel: TimelineViewModel, timelineType: TimelineType)
        -> some View
    {
        let pageSession = pageSessionStore.session(for: timelineType)
        // Grouped once per pass instead of scanning gaps or statuses for every row.
        let gapsByAfterID = Dictionary(grouping: viewModel.gaps, by: \.afterID)
        let statusByID = Dictionary(
            viewModel.statuses.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
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

            let rowGaps = gapsByAfterID[status.id] ?? []
            if rowGaps.isEmpty {
                MoroDivider(leadingInset: theme.spacing.timelineDividerInset, height: 0.5)
            } else {
                ForEach(rowGaps) { gap in
                    TimelineGapRow(
                        state: timelineGapRowState(for: gap, in: viewModel),
                        timeSpanText: TimelineGapTimeSpanFormatter.text(
                            afterDate: status.createdAt,
                            beforeDate: statusByID[gap.beforeID]?.createdAt
                        ),
                        accessibilityID: "timeline.gap.\(gap.beforeID)",
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            let direction = scrollBridge.preferredGapFillDirection(
                                for: gap,
                                on: timelineType
                            )
                            Task {
                                await viewModel.loadGap(
                                    id: gap.id,
                                    direction: direction,
                                    initiatedByUser: true
                                )
                            }
                        }
                    )
                }
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
                    message: MoroErrorCopy.message(for: error),
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

    private func timelineGapRowState(
        for gap: TimelineGap,
        in viewModel: TimelineViewModel
    ) -> TimelineGapRow.DisplayState {
        if viewModel.loadingGapIDs.contains(gap.id) {
            return .loading
        }
        if viewModel.failedGapIDs.contains(gap.id) {
            return .failed
        }
        return .idle
    }
}

enum TimelineGapTimeSpanFormatter {
    static let minimumInterval: TimeInterval = 30 * 60

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    static func text(afterDate: Date, beforeDate: Date?) -> String? {
        guard let beforeDate else { return nil }
        let interval = afterDate.timeIntervalSince(beforeDate)
        guard interval >= minimumInterval,
            let formatted = formatter.string(from: interval),
            !formatted.isEmpty
        else { return nil }
        return MoroL10n.Timeline.gapTimeSpan(formatted)
    }
}

private struct TimelineGapRow: View {
    enum DisplayState: Equatable {
        case idle
        case loading
        case failed
    }

    let state: DisplayState
    let timeSpanText: String?
    let accessibilityID: String
    let onTap: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            MoroDivider(height: 0.5)
            Button(action: onTap) {
                content
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(theme.colors.surfaceSubtle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state == .loading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityIdentifier(accessibilityID)
            MoroDivider(height: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) {
                primaryRow
                if let timeSpanText {
                    Text(timeSpanText)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            HStack(spacing: 6) {
                primaryRow
                if let timeSpanText {
                    Text("·")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                    Text(timeSpanText)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var primaryRow: some View {
        HStack(spacing: theme.spacing.xs) {
            switch state {
            case .idle:
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .moroScaledFont(size: 12, weight: .medium)
                    .foregroundStyle(theme.colors.textSecondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.textSecondary)
            case .failed:
                Image(systemName: "arrow.clockwise")
                    .moroScaledFont(size: 12, weight: .medium)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Text(primaryLabelText)
                .font(theme.typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
    }

    private var primaryLabelText: String {
        switch state {
        case .idle:
            return MoroL10n.Timeline.loadGap
        case .loading:
            return MoroL10n.Timeline.gapLoading
        case .failed:
            return MoroL10n.Timeline.gapRetry
        }
    }

    private var accessibilityLabelText: String {
        guard let timeSpanText else { return primaryLabelText }
        return "\(primaryLabelText), \(timeSpanText)"
    }
}
