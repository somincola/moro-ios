//
//  CoalescedRefresh.swift
//  moro
//
//  Runs one refresh at a time for a screen that can be refreshed from several places
//  (pull, foreground, stream events).
//

import Foundation

/// A refresh requested while one is running does not start a second, overlapping request
/// (whose late reply could overwrite the newer one). It joins the running refresh and
/// schedules exactly one more pass, so anything that changed mid-flight is still fetched.
/// Every caller returns once the data is at least as new as its request.
@MainActor
final class CoalescedRefresh {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private var running: Task<Void, Never>?
    private var needsAnotherPass = false

    var isRunning: Bool { running != nil }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        if let running {
            needsAnotherPass = true
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            repeat {
                self?.needsAnotherPass = false
                await operation()
            } while self?.needsAnotherPass == true
            // Cleared in the same main-actor step as the last check, so a request arriving
            // after it starts a new refresh instead of joining one that already finished.
            self?.running = nil
        }
        running = task
        await task.value
    }
}
