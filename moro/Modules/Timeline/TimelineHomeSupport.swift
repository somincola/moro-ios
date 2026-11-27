//
//  TimelineHomeSupport.swift
//  moro
//
//  Supporting types for TimelineHomeView: the scroll-elevating header and the
//  SwiftUI preview host. Extracted from TimelineHomeView.
//

import Combine
import SwiftUI

/// A stream-scene header that glides cleanly above the top safe area while scrolling down
/// and follows the finger back in when scrolling up.
///
/// It subscribes through `.onReceive` and stores its chrome state locally, so scrolling
/// re-renders only this small chrome view and never rebuilds the retained pager.
struct ScrollElevatingHeader<Content: View>: View {
    let height: CGFloat
    let backgroundColor: Color
    let dividerColor: Color
    let initialState: TimelineChromeState
    let subject: PassthroughSubject<TimelineChromeState, Never>
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: TimelineChromeState

    init(
        height: CGFloat,
        backgroundColor: Color,
        dividerColor: Color,
        initialState: TimelineChromeState = .expanded,
        subject: PassthroughSubject<TimelineChromeState, Never>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.height = height
        self.backgroundColor = backgroundColor
        self.dividerColor = dividerColor
        self.initialState = initialState
        self.subject = subject
        self.content = content
        _state = State(initialValue: initialState)
    }

    private var clampedFraction: CGFloat {
        min(max(state.headerFraction, 0), 1)
    }

    private var contentOpacity: Double {
        if reduceMotion {
            return Double(1 - clampedFraction)
        }
        return max(0, 1 - Double(clampedFraction) * 1.45)
    }

    private var dividerOpacity: Double {
        let baseOpacity = state.isScrolledFromTop ? 0.85 : 0.2
        return baseOpacity * max(0, 1 - Double(clampedFraction) * 1.15)
    }

    private var isInteractive: Bool {
        clampedFraction < 0.92
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                content()
                    .opacity(contentOpacity)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)
                    .opacity(dividerOpacity)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
            .background(backgroundColor)
            .opacity(reduceMotion ? Double(1 - clampedFraction) : 1)
            .offset(y: reduceMotion ? 0 : -height * clampedFraction)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
            .clipped()
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(!isInteractive)

            // Keep the status bar solid and soften the top viewport edge while the header is hidden.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .background(backgroundColor, ignoresSafeAreaEdges: .top)

                LinearGradient(
                    colors: [backgroundColor, backgroundColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                .opacity(Double(clampedFraction))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onReceive(subject) { nextState in
            guard nextState != state else { return }
            if nextState.isAnimated && !reduceMotion {
                withAnimation(.snappy(duration: 0.24)) {
                    state = nextState
                }
            } else {
                state = nextState
            }
        }
    }
}

/// Lazily creates and retains one `TimelineViewModel` per pinned timeline,
/// keyed by `TimelineType.id`, so the pager keeps each pinned page's state alive
/// across re-renders (mirroring the three fixed `@StateObject` view models).
///
/// Storage is deliberately NOT `@Published`: view models are created on demand during
/// body evaluation, and the pager already re-renders when the pinned set in
/// `AppSettings` changes — publishing from here would only warn about state changes
/// during view updates.
@MainActor
final class PinnedTimelineViewModelStore: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var viewModels: [String: TimelineViewModel] = [:]

    func viewModel(
        for type: TimelineType,
        apiClient: MastodonAPI,
        cacheClientID: String
    ) -> TimelineViewModel {
        if let existing = viewModels[type.id] {
            return existing
        }
        let viewModel = TimelineViewModel(
            apiClient: apiClient,
            timelineType: type,
            cacheClientID: cacheClientID,
            defersLivePresentation: true
        )
        viewModels[type.id] = viewModel
        return viewModel
    }

    /// Drop view models whose timelines are no longer pinned.
    func prune(keeping validTypeIDs: Set<String>) {
        viewModels = viewModels.filter { validTypeIDs.contains($0.key) }
    }

    var allViewModels: [TimelineViewModel] {
        Array(viewModels.values)
    }
}

@MainActor
final class TimelinePageSession: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    var hasRestoredReadingAnchor = false
    private(set) var contentOffsetY: CGFloat = 0
    private(set) var nativeContentOffset: CGPoint?
    private(set) var topVisibleStatusID: String?
    private var visibleStatusIndices: [String: Int] = [:]
    private var isVisibilityFrozen = false

    func recordContentOffset(_ offsetY: CGFloat) {
        contentOffsetY = max(0, offsetY)
    }

    func captureNativeContentOffset(_ offset: CGPoint?) {
        nativeContentOffset = offset
    }

    func updateVisibility(statusID: String, index: Int, isVisible: Bool) {
        guard !isVisibilityFrozen else { return }
        if isVisible {
            visibleStatusIndices[statusID] = index
        } else {
            visibleStatusIndices[statusID] = nil
        }

        if topVisibleStatusID == nil,
            let topVisible = visibleStatusIndices.min(by: { $0.value < $1.value })
        {
            topVisibleStatusID = topVisible.key
        }
    }

    func commitVisibleAnchor(for phase: ScrollPhase) {
        guard phase == .idle, !isVisibilityFrozen else { return }
        if let topVisible = visibleStatusIndices.min(by: { $0.value < $1.value }) {
            topVisibleStatusID = topVisible.key
        }
    }

    func freezeVisibility() {
        isVisibilityFrozen = true
    }

    func resumeVisibilityTracking() {
        visibleStatusIndices.removeAll()
        isVisibilityFrozen = false
    }
}

@MainActor
final class TimelinePageSessionStore: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var sessions: [String: TimelinePageSession] = [:]

    func session(for timeline: TimelineType) -> TimelinePageSession {
        if let existing = sessions[timeline.id] {
            return existing
        }
        let session = TimelinePageSession()
        sessions[timeline.id] = session
        return session
    }

    func prunePinnedSessions(keeping validTimelineIDs: Set<String>) {
        let builtinIDs = Set(TimelineType.builtin.map(\.id))
        sessions = sessions.filter {
            builtinIDs.contains($0.key) || validTimelineIDs.contains($0.key)
        }
    }
}

#Preview {
    TimelineHomePreviewHost()
}

private struct TimelineHomePreviewHost: View {
    @State private var selectedTimeline: TimelineType = .home

    var body: some View {
        let state = AppState()
        let interceptor = AuthInterceptor(tokenProvider: state)
        let client = MastodonClient(authInterceptor: interceptor)

        TimelineHomeView(
            apiClient: client,
            cacheClientID: "preview-session",
            selectedTimeline: $selectedTimeline
        )
        .environmentObject(state)
        .moroTheme(MoroTheme())
    }
}

/// Decides what a fresh launch or background resume does with the saved reading position.
///
/// Controlled by `AppSettings.timelineOpenBehavior`:
/// - `.keepPosition` (default): stay on the saved post on launch & resume; new posts appear in the pill.
/// - `.smartRefresh`: return to the latest after being away longer than the user's configured window.
/// - `.alwaysLatest`: open at the latest on cold launch, and on warm resume after a 2-minute anti-mistouch guard.
nonisolated enum TimelineLaunchPolicy {
    static let restoreWindow: TimeInterval = 30 * 60
    static let alwaysLatestResumeGraceWindow: TimeInterval = 2 * 60
    private static let lastLeftKey = "timeline.lastLeftAt"

    /// Captured once per process, before this launch records its own leaving time.
    static let coldLaunchLastLeftAt: Date? = {
        let raw = UserDefaults.standard.object(forKey: lastLeftKey) as? TimeInterval
        return raw.map(Date.init(timeIntervalSince1970:))
    }()

    /// Timestamp when this process started evaluating launch policy.
    private static let processLaunchDate = Date()

    /// Evaluated once per process, before this launch records its own leaving time.
    /// Respects `UITEST_TIMELINE_RESTORE_WINDOW` when set by UI tests, otherwise reads user settings.
    static let restoresReadingPosition: Bool = {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["UITEST_TIMELINE_RESTORE_WINDOW"]
            .flatMap(TimeInterval.init) {
            return shouldRestore(lastLeftAt: coldLaunchLastLeftAt, now: processLaunchDate, window: override)
        }
        #endif
        let defaults = UserDefaults.standard
        let behaviorRaw = defaults.string(forKey: "timelineOpenBehavior") ?? "keep_position"
        let smartMinutes: Int
        if let stored = defaults.object(forKey: "timelineSmartRefreshMinutes") as? NSNumber {
            smartMinutes = max(30, stored.intValue)
        } else {
            smartMinutes = 60
        }
        return shouldRestoreOnColdLaunch(
            behaviorRawValue: behaviorRaw,
            smartWindow: TimeInterval(smartMinutes * 60),
            lastLeftAt: coldLaunchLastLeftAt,
            now: processLaunchDate
        )
    }()

    static func shouldRestoreOnColdLaunch(
        behaviorRawValue: String,
        smartWindow: TimeInterval,
        lastLeftAt: Date?,
        now: Date
    ) -> Bool {
        switch behaviorRawValue {
        case "keep_position":
            return true
        case "always_latest":
            return false
        case "smart_refresh":
            return shouldRestore(lastLeftAt: lastLeftAt, now: now, window: smartWindow)
        default:
            return true
        }
    }

    static func shouldJumpToLatestOnResume(
        behaviorRawValue: String,
        smartWindow: TimeInterval,
        awayDuration: TimeInterval
    ) -> Bool {
        guard awayDuration >= 0 else { return false }
        switch behaviorRawValue {
        case "keep_position":
            return false
        case "smart_refresh":
            return awayDuration >= smartWindow
        case "always_latest":
            // 2-minute anti-mistouch guard: brief switches (e.g. replying to a message or
            // opening an external link) never yank the reader back to the top.
            return awayDuration >= alwaysLatestResumeGraceWindow
        default:
            return false
        }
    }

    static func shouldRestore(lastLeftAt: Date?, now: Date, window: TimeInterval) -> Bool {
        guard let lastLeftAt else { return false }
        let away = now.timeIntervalSince(lastLeftAt)
        return away >= 0 && away < window
    }

    static func recordLeaving(at date: Date = Date()) {
        _ = coldLaunchLastLeftAt
        _ = restoresReadingPosition // settle this launch's decision before overwriting its input
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastLeftKey)
    }
}
