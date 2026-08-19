//
//  StartupPerformanceTracker.swift
//  moro
//
//  Unified debug metrics for app cold start and account identity backfill.
//

import Foundation

@MainActor
final class StartupPerformanceTracker {
    static let shared = StartupPerformanceTracker()
    nonisolated static let timelineFirstContentReadyNotification = Notification.Name(
        "moro.startup.timelineFirstContentReady"
    )

    private var launchStartAt: CFAbsoluteTime?
    private var mainDestinationAt: CFAbsoluteTime?
    private var cachedSessionAppliedAt: CFAbsoluteTime?
    private var identityRefreshStartedAt: CFAbsoluteTime?
    private var timelineDataReadyAt: CFAbsoluteTime?
    private var timelineFirstContentAt: CFAbsoluteTime?
    private var timelineBootstrapLogged = false

    private init() {}

    func markLaunchStartIfNeeded(reason: String) {
        guard launchStartAt == nil else { return }
        launchStartAt = CFAbsoluteTimeGetCurrent()
        debugLog("launch-start reason=\(reason)")
    }

    func markCachedSessionApplied(sessionID: String?) {
        cachedSessionAppliedAt = CFAbsoluteTimeGetCurrent()
        let elapsed = elapsedFromLaunch()
        debugLog(
            "cached-session-applied session=\(sessionID ?? "unknown") elapsed=\(formatElapsed(elapsed))"
        )
    }

    func markMainDestinationShownIfNeeded() {
        guard mainDestinationAt == nil else { return }
        mainDestinationAt = CFAbsoluteTimeGetCurrent()
        let elapsed = elapsedFromLaunch()
        debugLog("main-destination-shown elapsed=\(formatElapsed(elapsed))")
    }

    func markTimelineFirstContentReady(count: Int, source: String = "unknown") {
        guard timelineFirstContentAt == nil else { return }
        timelineFirstContentAt = CFAbsoluteTimeGetCurrent()
        let elapsed = elapsedFromLaunch()
        debugLog(
            "timeline-first-content count=\(count) source=\(source) elapsed=\(formatElapsed(elapsed))"
        )
        NotificationCenter.default.post(name: Self.timelineFirstContentReadyNotification, object: nil)
    }

    func markTimelineDataReady(count: Int) {
        guard timelineDataReadyAt == nil else { return }
        timelineDataReadyAt = CFAbsoluteTimeGetCurrent()
        let elapsed = elapsedFromLaunch()
        debugLog("timeline-data-ready count=\(count) elapsed=\(formatElapsed(elapsed))")
    }

    func markTimelineBootstrapProfile(tier: String, summary: String) {
        guard !timelineBootstrapLogged else { return }
        timelineBootstrapLogged = true
        debugLog("timeline-bootstrap tier=\(tier) \(summary)")
    }

    func markIdentityRefreshStarted(trigger: String) {
        identityRefreshStartedAt = CFAbsoluteTimeGetCurrent()
        debugLog("identity-refresh-start trigger=\(trigger)")
    }

    func markIdentityRefreshFinished(trigger: String, success: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        let refreshElapsed: Double
        if let started = identityRefreshStartedAt {
            refreshElapsed = (now - started) * 1000
        } else {
            refreshElapsed = 0
        }
        identityRefreshStartedAt = nil

        let fromLaunch = elapsedFromLaunch(reference: now)
        let fromCached: Double
        if let cachedSessionAppliedAt {
            fromCached = (now - cachedSessionAppliedAt) * 1000
        } else {
            fromCached = 0
        }

        debugLog(
            "identity-refresh-finish trigger=\(trigger) success=\(success) elapsed=\(formatElapsed(refreshElapsed)) from-launch=\(formatElapsed(fromLaunch)) from-cache=\(formatElapsed(fromCached))"
        )
    }

    var hasTimelineFirstContentReady: Bool {
        timelineFirstContentAt != nil
    }

    func waitForTimelineFirstContentReady(timeout: TimeInterval) async {
        if timelineFirstContentAt != nil { return }

        let timeoutNanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(
                    named: Self.timelineFirstContentReadyNotification
                ) {
                    break
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }

            _ = await group.next()
            group.cancelAll()
        }
    }

    func reset() {
        launchStartAt = nil
        mainDestinationAt = nil
        cachedSessionAppliedAt = nil
        identityRefreshStartedAt = nil
        timelineDataReadyAt = nil
        timelineFirstContentAt = nil
        timelineBootstrapLogged = false
    }

    private func elapsedFromLaunch(reference now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Double {
        guard let launchStartAt else { return 0 }
        return (now - launchStartAt) * 1000
    }

    private func formatElapsed(_ millis: Double) -> String {
        String(format: "%.0fms", millis)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
            AppLogger.performanceLog("⏱️ [StartupPerf] \(message)")
        #endif
    }
}
