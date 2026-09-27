//
//  TimelineHomeSupport.swift
//  moro
//
//  Supporting types for TimelineHomeView: the scroll-elevating header and the
//  SwiftUI preview host. Extracted from TimelineHomeView.
//

import Combine
import SwiftUI

/// A stream-scene header that keeps its position and color family while scrolling. The scroll
/// fraction only strengthens the lower boundary, communicating elevation without making the
/// primary feed controls disappear.
///
/// It subscribes through `.onReceive` and stores the fraction locally, so scrolling re-renders
/// only this small chrome view and never rebuilds the retained pager.
struct ScrollElevatingHeader<Content: View>: View {
    let height: CGFloat
    let backgroundColor: Color
    let dividerColor: Color
    let subject: PassthroughSubject<CGFloat, Never>
    @ViewBuilder var content: () -> Content

    @State private var fraction: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            content()

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
                .opacity(Double(0.2 + 0.8 * fraction))
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
        .background(backgroundColor)
        .onReceive(subject) { newFraction in
            guard abs(newFraction - fraction) > 0.0005 else { return }
            fraction = min(max(newFraction, 0), 1)
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
