//
//  StatusDetailPerformanceTracker.swift
//  moro
//
//  Unified debug metrics for status detail warmup and first-screen latency.
//

import Foundation

@MainActor
final class StatusDetailPerformanceTracker {
    static let shared = StatusDetailPerformanceTracker()
    private static let enableDebugLogging = false

    enum FirstScreenPath: String {
        case cacheHit = "cache-hit"
        case prefetchHit = "prefetch-hit"
        case coldOpen = "cold-open"
        case failed = "failed"
    }

    private init() {}

    func recordWarmup(
        source: String,
        statusID: String,
        before: StatusDetailPrefetchCoordinator.WarmupState,
        after: StatusDetailPrefetchCoordinator.WarmupState,
        elapsedMillis: Double
    ) {
        debugLog(
            "warmup source=\(source) id=\(statusID) before=\(before.rawValue) after=\(after.rawValue) elapsed=\(formatElapsed(elapsedMillis))"
        )
    }

    func recordFirstScreen(
        statusID: String,
        path: FirstScreenPath,
        warmupState: StatusDetailPrefetchCoordinator.WarmupState,
        elapsedMillis: Double
    ) {
        debugLog(
            "first-screen id=\(statusID) path=\(path.rawValue) warmup=\(warmupState.rawValue) elapsed=\(formatElapsed(elapsedMillis))"
        )
    }

    private func formatElapsed(_ millis: Double) -> String {
        String(format: "%.0fms", millis)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
            AppLogger.performanceLog(
                "⏱️ [DetailPerf] \(message)",
                enabled: Self.enableDebugLogging || AppLogger.isPerformanceEnabled
            )
        #endif
    }
}
