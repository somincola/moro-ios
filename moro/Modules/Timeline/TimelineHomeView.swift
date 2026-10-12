//
//  TimelineHomeView.swift
//  moro
//
//  Home timeline with real data fetching, pull-to-refresh, and infinite scroll.
//  Supports timeline switching (Home/Local/Federated).
//

import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct TimelineHomeView: View {
    // MARK: - Independent ViewModels for each timeline
    @StateObject var homeViewModel: TimelineViewModel
    @StateObject var localViewModel: TimelineViewModel
    @StateObject var federatedViewModel: TimelineViewModel

    @StateObject var interactionService: PostInteractionService
    @Environment(\.moroTheme) var theme
    @Environment(\.moroSceneDescriptor) var sceneDescriptor
    @Environment(\.cacheManager) var cacheManager
    @Environment(\.appRouter) var router
    @Environment(\.selectedTabScrollToTop) var selectedTabScrollToTop
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var appState: AppState
    @StateObject var actionSurface = PostActionSurfaceCenter()

    /// StreamWatcher for real-time updates
    var streamWatcher = StreamWatcher.shared

    /// Detection manager for policy-based new post detection
    @StateObject var detectionManager = TimelineDetectionManager.shared

    /// Settings for banner visibility control
    @StateObject var settings = AppSettings.shared

    /// Lazily-built view models for pinned timelines (lists).
    @StateObject var pinnedTimelineStore = PinnedTimelineViewModelStore()

    /// Scroll proxies, header visibility and per-timeline at-top flags — shared by
    /// reference so they survive the pager's per-timeline UIHostingController boundary.
    @StateObject var scrollBridge = TimelineScrollBridge()
    @StateObject var pageSessionStore = TimelinePageSessionStore()

    let apiClient: MastodonAPI
    /// Per-account cache/persistence key (`activeSessionID` or "no-active-session");
    /// also scopes which pinned timelines this account shows.
    let cacheClientID: String
    let onAvatarTap: (() -> Void)?
    let onTimelineSelectionChange: ((TimelineType) -> Void)?
    /// Optional observer for consumers that coordinate other chrome with the timeline header.
    let onChromeFraction: ((CGFloat) -> Void)?
    /// False while a detail/profile route is pushed over the timeline. The timeline remains
    /// mounted as the UIKit navigation root, but must not keep publishing hidden scroll geometry.
    let isActive: Bool

    /// Bottom inset (= the shell's tab bar height incl. safe area) applied to the scroll content, so
    /// the last post clears the overlaid tab bar while the timeline still fills edge to edge — and
    /// the strip the tab bar vacates on scroll is filled by content, not a blank band.
    let bottomContentInset: CGFloat
    @StateObject var postMenuActionCenter: PostMenuActionCenter

    /// Thread contexts for timeline statuses
    @State var threadContexts: [String: TimelineThreadContext] = [:]

    /// Selected timeline type
    @Binding var selectedTimeline: TimelineType

    /// Track if each timeline has been loaded
    @State var hasLoadedHome = false
    @State var hasLoadedLocal = false
    @State var hasLoadedFederated = false
    /// Loaded pinned timelines, keyed by `TimelineType.id`.
    @State var loadedPinnedTimelineIDs: Set<String> = []
    @State var announcementBadgeTask: Task<Void, Never>?
    @State var startupDeferredTask: Task<Void, Never>?
    @State var lastAnnouncementRefreshAt: Date = .distantPast
    @State var lastInactiveAt: Date?
    /// The root header grows for larger content sizes while keeping its normal compact height.
    @ScaledMetric(relativeTo: .body) var scaledHeaderHeight: CGFloat = 48
    var headerHeight: CGFloat { min(max(scaledHeaderHeight, 48), 72) }
    let announcementRefreshCooldown: TimeInterval = 12
    let minimumPullRefreshIndicatorDuration: TimeInterval = 0.65
    let pullRefreshReservedHeight: CGFloat = 40
    let pullRefreshTriggerDistance: CGFloat = 40
    let startupStreamDelayNanoseconds: UInt64 = 2_600_000_000
    let startupMarkerDelayAfterStreamNanoseconds: UInt64 = 2_200_000_000
    let startupMarkerBackoffOnInteractionNanoseconds: UInt64 = 1_800_000_000

    /// Pinned timelines for the active account.
    var pinnedTimelineTypes: [TimelineType] {
        return settings.pinnedTimelineLists(for: cacheClientID)
            .map { .list(id: $0.id, title: $0.title) }
    }

    func pinnedViewModel(for type: TimelineType) -> TimelineViewModel {
        pinnedTimelineStore.viewModel(
            for: type,
            apiClient: apiClient,
            cacheClientID: cacheClientID
        )
    }

    /// Current active ViewModel based on selected timeline
    var viewModel: TimelineViewModel {
        switch selectedTimeline {
        case .home: return homeViewModel
        case .local: return localViewModel
        case .federated: return federatedViewModel
        case .list: return pinnedViewModel(for: selectedTimeline)
        }
    }

    init(
        apiClient: MastodonAPI,
        cacheClientID: String = "active-session",
        selectedTimeline: Binding<TimelineType> = .constant(.home),
        onAvatarTap: (() -> Void)? = nil,
        onTimelineSelectionChange: ((TimelineType) -> Void)? = nil,
        onChromeFraction: ((CGFloat) -> Void)? = nil,
        isActive: Bool = true,
        bottomContentInset: CGFloat = 0,
        homeViewModel: TimelineViewModel? = nil
    ) {
        self.apiClient = apiClient
        self.cacheClientID = cacheClientID
        _selectedTimeline = selectedTimeline
        self.onAvatarTap = onAvatarTap
        self.onTimelineSelectionChange = onTimelineSelectionChange
        self.onChromeFraction = onChromeFraction
        self.isActive = isActive
        self.bottomContentInset = bottomContentInset
        _postMenuActionCenter = StateObject(
            wrappedValue: PostMenuActionCenter(apiClient: apiClient))
        _homeViewModel = StateObject(
            wrappedValue: homeViewModel ?? TimelineViewModel(
                apiClient: apiClient,
                timelineType: .home,
                cacheClientID: cacheClientID,
                defersLivePresentation: true
            ))
        _localViewModel = StateObject(
            wrappedValue: TimelineViewModel(
                apiClient: apiClient,
                timelineType: .local,
                cacheClientID: cacheClientID,
                defersLivePresentation: true
            ))
        _federatedViewModel = StateObject(
            wrappedValue: TimelineViewModel(
                apiClient: apiClient,
                timelineType: .federated,
                cacheClientID: cacheClientID,
                defersLivePresentation: true
            ))
        _interactionService = StateObject(
            wrappedValue: PostInteractionService(apiClient: apiClient))
    }

    // MARK: - Computed Properties

    func threadContext(for status: Status) -> TimelineThreadContext {
        // Timeline list view: always return .none
        // Thread lines and "上接嘟文串" are only shown in detail view (StatusDetailView)
        // In timeline list, we always show "Replying to xxx" header, never thread lines
        return .none
    }

    func timelineHeaderSafeAnchorID(for statusID: String) -> String {
        "timeline-header-safe-\(statusID)"
    }

    func updateThreadContexts() {
        // Timeline list view: no thread context analysis needed
        // Thread context is only used in detail view (StatusDetailView) where we fetch full thread
        threadContexts = [:]
    }

    func syncDetectionTopID(for timeline: TimelineType) {
        let topID: String?
        let dimension: TimelineDimension

        switch timeline {
        case .home:
            topID = homeViewModel.detectionBaselineID
            dimension = .following
        case .local:
            topID = localViewModel.detectionBaselineID
            dimension = .local
        case .federated:
            topID = federatedViewModel.detectionBaselineID
            dimension = .federated
        case .list:
            // Pinned timelines have no detection dimension.
            return
        }

        guard let topID else { return }
        detectionManager.updateLastKnownTopID(topID, for: dimension)
    }

    func hasFinishedInitialLoad(for timeline: TimelineType) -> Bool {
        switch timeline {
        case .home:
            return hasLoadedHome
        case .local:
            return hasLoadedLocal
        case .federated:
            return hasLoadedFederated
        case .list:
            return loadedPinnedTimelineIDs.contains(timeline.id)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // The scroll content owns a fixed header spacer; the header itself stays visible.
            timelinePager

            ScrollElevatingHeader(
                height: headerHeight,
                backgroundColor: sceneCanvasColor,
                dividerColor: theme.colors.borderSubtle,
                subject: scrollBridge.chromeFractionSubject
            ) {
                floatingHeader
            }

            // Pinned models live in a retained store, so the notice observes the
            // active model directly as well as the three built-in StateObjects.
            TimelineObservedPage(viewModel: viewModel) { topIndicator }
        }
        .onChange(of: hasLocalModal) { _, modal in
            scrollBridge.setActive(isActive && scenePhase == .active && !modal)
        }
        .background(sceneCanvasColor)
        // Extend content + background under the bottom safe area.
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            scrollBridge.resumePresentation(for: selectedTimeline)
            scrollBridge.setActive(isActive && scenePhase == .active && !hasLocalModal)
            onTimelineSelectionChange?(selectedTimeline)
        }
        .task {
            // ── Phase 1: Critical Path (T=0) ──
            // Only timeline API; no WebSocket, no side-requests.
            let sourceModels: [TimelineType: TimelineViewModel] = [
                .home: homeViewModel, .local: localViewModel, .federated: federatedViewModel]
            detectionManager.configure(apiClient: apiClient, scopeID: cacheClientID,
                refreshTimeline: { timeline in
                    guard let target = sourceModels[timeline] else { return nil }
                    await target.refresh(trigger: .foreground)
                    return target.detectionBaselineID
                })
            detectionManager.setActiveDimension(.following)
            StartupPerformanceTracker.shared.markTimelineBootstrapProfile(
                tier: homeViewModel.bootstrapTierLabel,
                summary: homeViewModel.bootstrapProfileSummary
            )

            homeViewModel.currentAccountID = appState.currentAccount?.id
            localViewModel.currentAccountID = appState.currentAccount?.id
            federatedViewModel.currentAccountID = appState.currentAccount?.id
            await homeViewModel.loadInitial()
            StartupPerformanceTracker.shared.markTimelineDataReady(
                count: homeViewModel.statuses.count
            )
            hasLoadedHome = true
            refreshAnnouncementBadge(initialDelay: false)

            // Establish detection baseline (following only).
            syncDetectionTopID(for: .home)
            detectionManager.startDetection()

            // ── Phase 2/3: Post-First-Paint low priority work ──
            scheduleDeferredStartupTasks()
        }
        .onReceive(scrollBridge.layoutEvents) { timeline in
            guard timeline == selectedTimeline else { return }
            processLiveUpdates(for: timeline, viewModel: viewModel)
        }
        .onReceive(detectionManager.pages) { event in
            guard event.scopeID == cacheClientID else { return }
            let target: TimelineViewModel
            switch event.timeline {
            case .home: target = homeViewModel
            case .local: target = localViewModel
            case .federated: target = federatedViewModel
            case .list: target = pinnedViewModel(for: event.timeline)
            }
            target.currentAccountID = appState.currentAccount?.id
            target.receiveDetectedPage(event.page, sinceID: event.sinceID)
            syncDetectionTopID(for: event.timeline)
        }
        .onChange(of: isActive) { _, active in
            scrollBridge.setActive(active && scenePhase == .active && !hasLocalModal)
            if active {
                scrollBridge.resumePresentation(for: selectedTimeline)
            }
            detectionManager.setActiveDimension(active ? detectionDimension(for: selectedTimeline) : nil)
            if active, viewModel.statuses.isEmpty {
                let target = viewModel
                let timeline = selectedTimeline
                Task {
                    await target.loadInitial()
                    syncDetectionTopID(for: timeline)
                    detectionManager.startDetection()
                }
            }
            if !active {
                viewModel.cancelBackgroundTasks()
                if let anchor = scrollBridge.readingAnchors(for: selectedTimeline).first {
                    viewModel.saveReadingAnchor(anchor)
                }
            }
        }
        .task(id: activeListPollingKey) {
            guard let _ = activeListPollingKey else { return }
            let target = viewModel
            while !Task.isCancelled {
                if case .loaded = target.initialLoadState,
                    Date().timeIntervalSince(target.lastLatestCheckAt ?? .distantPast) >= 60 {
                    await target.refresh(trigger: .foreground)
                }
                do { try await Task.sleep(for: .seconds(90)) } catch { return }
            }
        }
        .onChange(of: streamWatcher.connectionState) { old, new in
            guard new == .connected, old != .connected, hasLoadedHome,
                scenePhase == .active, detectionManager.isConfigured(for: cacheClientID) else { return }
            Task { await detectionManager.checkForNewItems(dimension: .following, force: true) }
        }
        .onReceive(streamWatcher.sourcedEvents) { message in
            if case .update = message.event, !message.canInsertIntoHome { return }
            handleStreamEvent(message.event)
        }
        .onReceive(FeedCoordinator.shared.updates) { update in
            handleFeedCoordinatorUpdate(update)
        }
        .onChange(of: selectedTimeline) { oldValue, newValue in
            // Only process if timeline type actually changed
            guard oldValue != newValue else { return }

            // Stop the departing timeline's deferred fill so it no longer mutates an
            // off-screen view model (and writes cache) after we've navigated away —
            // that runaway append was the source of the climbing memory on switches.
            switch oldValue {
            case .home: homeViewModel.cancelBackgroundTasks()
            case .local: localViewModel.cancelBackgroundTasks()
            case .federated: federatedViewModel.cancelBackgroundTasks()
            case .list: pinnedViewModel(for: oldValue).cancelBackgroundTasks()
            }

            let wasAlreadyLoaded = hasFinishedInitialLoad(for: newValue)
            let targetViewModel = viewModel
            targetViewModel.currentAccountID = appState.currentAccount?.id

            // Load the new timeline if not already loaded
            Task {
                switch newValue {
                case .home:
                    if !hasLoadedHome {
                        await homeViewModel.loadInitial()
                        hasLoadedHome = true
                    }
                case .local:
                    if !hasLoadedLocal {
                        await localViewModel.loadInitial()
                        hasLoadedLocal = true
                    }
                case .federated:
                    if !hasLoadedFederated {
                        await federatedViewModel.loadInitial()
                        hasLoadedFederated = true
                    }
                case .list:
                    if !loadedPinnedTimelineIDs.contains(newValue.id) {
                        await pinnedViewModel(for: newValue).loadInitial()
                        loadedPinnedTimelineIDs.insert(newValue.id)
                    }
                }
                guard selectedTimeline == newValue else { return }
                if wasAlreadyLoaded {
                    await targetViewModel.resumeCachedContentIfNeeded()
                }
                syncDetectionTopID(for: newValue)
                let dimension = detectionDimension(for: newValue)
                detectionManager.setActiveDimension(dimension)
                if let dimension {
                    if wasAlreadyLoaded {
                        await detectionManager.checkForNewItems(dimension: dimension)
                    }
                }
            }
            scrollBridge.prepareForTimelineSwitch()
            onTimelineSelectionChange?(newValue)
        }
        .onChange(of: pinnedTimelineTypes) { _, newPinned in
            // Unpin / rename / refund while a pinned page is selected: fall back to
            // Home (the pager itself already swaps the visible controller safely).
            if case .list = selectedTimeline, !newPinned.contains(selectedTimeline) {
                selectedTimeline = .home
            }
            let validIDs = Set(newPinned.map(\.id))
            pinnedTimelineStore.prune(keeping: validIDs)
            pageSessionStore.prunePinnedSessions(keeping: validIDs)
            loadedPinnedTimelineIDs.formIntersection(validIDs)
        }
        .onChange(of: selectedTabScrollToTop) { _, newValue in
            // Handle tab tap scroll-to-top event
            guard newValue == MainTab.home.hashValue else { return }

            // Check if current timeline is at top
            let isAtTop = scrollBridge.isAtTop(selectedTimeline)

            if isAtTop {
                refreshCurrentTimelineFromTab()
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                loadDetectedPosts(scrollToTop: true, providesFeedback: false)
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            scrollBridge.setActive(isActive && newValue == .active && !hasLocalModal)
            switch newValue {
            case .active:
                guard hasLoadedHome else { return }
                refreshAnnouncementBadge(initialDelay: false)
                detectionManager.startDetection()
                if let token = appState.authToken {
                    streamWatcher.configure(
                        baseURL: AppEnvironment.apiBaseURL,
                        accessToken: token
                    )
                    streamWatcher.addStream(.user)
                }

                let inactiveAt = lastInactiveAt
                lastInactiveAt = nil
                guard let inactiveAt,
                    Date().timeIntervalSince(inactiveAt) >= 60,
                    let dimension = detectionDimension(for: selectedTimeline)
                else { return }

                Task {
                    await detectionManager.checkForNewItems(
                        dimension: dimension,
                        force: true
                    )
                }

            case .inactive, .background:
                let models = [homeViewModel, localViewModel, federatedViewModel] + pinnedTimelineStore.allViewModels
                for model in models { model.cancelBackgroundTasks() }
                Task { for model in models where model.hasReadingState { await model.flushCacheWrites() } }
                if lastInactiveAt == nil {
                    lastInactiveAt = Date()
                }
            @unknown default:
                break
            }
        }
        .onDisappear {
            scrollBridge.setActive(false)
            startupDeferredTask?.cancel()
            announcementBadgeTask?.cancel()
        }
        // Boost/quote sheet + confirm-boost / delete-post alerts attach at the
        // body root rather than inside the scroll view's modifier chain — that
        // nested attachment was racing with navigation transitions and made
        // sheet/alert bindings flicker when the user pushed/popped status detail.
        .sheet(item: $actionSurface.boostDialogStatus) { status in
            let quoteInfo = QuoteButtonInfo.forStatus(
                status,
                currentUserID: appState.currentAccount?.id
            )
            BoostOrQuoteDialog(
                status: status,
                isBoosted: status.reblogged,
                canQuote: quoteInfo.isEnabled,
                quoteButtonTitle: quoteInfo.title,
                quoteButtonSubtitle: quoteInfo.subtitle,
                onBoost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onUnboost: {
                    Task {
                        await interactionService.toggleBoost(status, askFirst: false)
                    }
                },
                onQuote: {
                    actionSurface.startQuote(from: status)
                },
                onDismiss: {
                    actionSurface.dismissBoostDialog()
                }
            )
        }
        .alert(
            item: Binding(
                get: { interactionService.activeAlert },
                set: { _ in interactionService.activeAlert = nil }
            )
        ) { alert in
            switch alert {
            case .confirmBoost(let didConfirm):
                return Alert(
                    title: Text(MoroL10n.Timeline.confirmBoostTitle),
                    message: Text(MoroL10n.Timeline.confirmBoostMessage),
                    primaryButton: .default(Text(MoroL10n.Timeline.confirmBoostAction)) {
                        didConfirm(true)
                    },
                    secondaryButton: .cancel(Text(MoroL10n.Common.cancel)) {
                        didConfirm(false)
                    }
                )
            }
        }
        .alert(
            MoroL10n.ComposeDrafts.deleteConfirmTitle,
            isPresented: Binding(
                get: { actionSurface.deleteRequest != nil },
                set: {
                    if !$0 { actionSurface.clearDeleteRequest() }
                }
            )
        ) {
            Button(
                actionSurface.deleteRequest?.shouldRedraft == true
                    ? MoroL10n.ComposeDrafts.deleteAndRedraftAction
                    : MoroL10n.ComposeDrafts.deleteAction,
                role: .destructive
            ) {
                if let request = actionSurface.deleteRequest {
                    handlers.performDelete(request.status, redraft: request.shouldRedraft)
                }
                actionSurface.clearDeleteRequest()
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {
                actionSurface.clearDeleteRequest()
            }
        } message: {
            Text(MoroL10n.ComposeDrafts.deleteConfirmMessage)
        }
        .fullScreenCover(item: $actionSurface.composeContext) { wrapper in
            ComposeView(
                context: wrapper.context,
                apiClient: apiClient,
                currentUserID: appState.currentAccount?.id,
                initialDraft: wrapper.draft,
                onDismiss: { actionSurface.composeContext = nil }
            ) { _ in }
            .environmentObject(appState)
        }
        .sheet(item: $actionSurface.reportStatus) { status in
            ReportView(
                status: status,
                apiClient: apiClient,
                onDismiss: { actionSurface.dismissReport() }
            )
        }
    }

    private var hasLocalModal: Bool {
        actionSurface.composeContext != nil || actionSurface.boostDialogStatus != nil
            || actionSurface.reportStatus != nil || actionSurface.deleteRequest != nil
            || interactionService.activeAlert != nil
    }

    private var activeListPollingKey: String? {
        guard isActive, scenePhase == .active, case .list = selectedTimeline else { return nil }
        return "\(cacheClientID):\(selectedTimeline.id)"
    }

    var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .content).backgroundColor(in: theme)
    }

    @ViewBuilder
    var timelinePager: some View {
        #if os(iOS)
            TimelinePagerHost(
                selection: $selectedTimeline,
                pages: builtinPagerPages + pinnedPagerPages,
                onTransitionStarted: freezeTimelinePosition,
                onPagePresented: restorePresentedTimelinePosition
            )
        #else
            TabView(selection: $selectedTimeline) {
                timelineScrollView(viewModel: homeViewModel, timelineType: .home)
                    .tag(TimelineType.home)

                timelineScrollView(viewModel: localViewModel, timelineType: .local)
                    .tag(TimelineType.local)

                timelineScrollView(viewModel: federatedViewModel, timelineType: .federated)
                    .tag(TimelineType.federated)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    @MainActor
    private func freezeTimelinePosition(_ timeline: TimelineType) {
        let session = pageSessionStore.session(for: timeline)
        session.captureNativeContentOffset(scrollBridge.nativeContentOffset(for: timeline))
        session.freezeVisibility()
        scrollBridge.setFrozen(true, for: timeline)
    }

    @MainActor
    private func restorePresentedTimelinePosition(_ timeline: TimelineType) {
        let session = pageSessionStore.session(for: timeline)
        let savedOffset = session.contentOffsetY
        let nativeContentOffset = session.nativeContentOffset
        let statusID = session.topVisibleStatusID
        let shouldRestore = savedOffset > 1 && statusID != nil

        // Register the actual displayed page synchronously. Only layout/offset
        // restoration is deferred; selection onChange must not invalidate it.
        let presentation = scrollBridge.beginPresentation(for: timeline)
        session.freezeVisibility()
        Task { @MainActor in
            defer {
                if scrollBridge.isCurrentPresentation(presentation) {
                    session.resumeVisibilityTracking()
                    scrollBridge.finishPresentation(presentation)
                }
            }
            await Task.yield()
            guard selectedTimeline == timeline,
                scrollBridge.isCurrentPresentation(presentation) else { return }
            let chromeFraction = scrollBridge.setPresentedTimeline(timeline)
            onChromeFraction?(chromeFraction)
            if let nativeContentOffset,
                scrollBridge.restoreNativeContentOffset(nativeContentOffset, for: timeline)
            {
                await Task.yield()
            } else if shouldRestore, let statusID {
                let targetID = chromeFraction < 0.5
                    ? timelineHeaderSafeAnchorID(for: statusID)
                    : statusID
                scrollBridge.restoreScrollPosition(timeline, targetID: targetID)
                await Task.yield()
            }
            // The matching transaction's defer releases the page even when there
            // is no saved anchor or native scroll view yet. A superseded task
            // cannot unfreeze a newer presentation of the same timeline.
        }
    }

    #if os(iOS)
        private var pagerPageConfigurationID: String {
            [
                isActive ? "active" : "inactive",
                String(Int(bottomContentInset.rounded())),
            ].joined(separator: ":")
        }

        private var builtinPagerPages: [TimelinePagerPage] {
            [
                .init(
                    type: .home,
                    configurationID: pagerPageConfigurationID,
                    view: AnyView(
                        TimelineObservedPage(viewModel: homeViewModel) {
                            timelineScrollView(viewModel: homeViewModel, timelineType: .home)
                        }
                    )
                ),
                .init(
                    type: .local,
                    configurationID: pagerPageConfigurationID,
                    view: AnyView(
                        TimelineObservedPage(viewModel: localViewModel) {
                            timelineScrollView(viewModel: localViewModel, timelineType: .local)
                        }
                    )
                ),
                .init(
                    type: .federated,
                    configurationID: pagerPageConfigurationID,
                    view: AnyView(
                        TimelineObservedPage(viewModel: federatedViewModel) {
                            timelineScrollView(
                                viewModel: federatedViewModel,
                                timelineType: .federated
                            )
                        }
                    )
                ),
            ]
        }

        /// One pager page per pinned timeline, appended after the built-in three.
        private var pinnedPagerPages: [TimelinePagerPage] {
            pinnedTimelineTypes.map { type in
                let pageViewModel = pinnedViewModel(for: type)
                return TimelinePagerPage(
                    type: type,
                    configurationID: pagerPageConfigurationID,
                    view: AnyView(
                        TimelineObservedPage(viewModel: pageViewModel) {
                            timelineScrollView(viewModel: pageViewModel, timelineType: type)
                        }
                    )
                )
            }
        }
    #endif

    // MARK: - Interactions

    // MARK: - Post Interaction Handlers

    var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService,
            actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter,
            apiClient: apiClient,
            currentUserID: appState.currentAccount?.id,
            router: router,
            onRemoveStatus: { id in viewModel.removeStatus(id: id) }
        )
    }

}
