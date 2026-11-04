//
//  AutoRefreshSchedule.swift
//  moro
//
//  When a page's automatic refresh (opening it, switching to its tab, foregrounding) runs.
//

import Foundation

/// Decides whether an automatic refresh is due. Only routine checks consult it: a signal
/// (push, streaming, a rising unread count) or the reader's own refresh always runs.
///
/// - Content younger than `ttl` is fresh and isn't asked for again.
/// - After automatic refreshes fail, the next waits progressively longer
///   (`backoffSteps`); one success or one refresh the reader asked for resets that.
/// - While offline nothing is due; a check skipped then is owed, and runs once the
///   connection is back (`isDue` stays true until a refresh is recorded).
struct AutoRefreshSchedule: Equatable, Sendable {
    static let backoffSteps: [TimeInterval] = [30, 60, 120, 300]

    let ttl: TimeInterval
    private(set) var lastSuccess: Date?
    private(set) var consecutiveFailures = 0
    private(set) var lastFailure: Date?
    private(set) var owesCatchUp = false

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// How long after `lastFailure` the next automatic refresh may run, or nil when the
    /// last refresh didn't fail.
    var backoffDelay: TimeInterval? {
        guard consecutiveFailures > 0 else { return nil }
        return Self.backoffSteps[min(consecutiveFailures, Self.backoffSteps.count) - 1]
    }

    func isDue(now: Date = Date(), isOffline: Bool) -> Bool {
        guard !isOffline else { return false }
        if owesCatchUp { return true }
        if let backoffDelay, let lastFailure {
            return now.timeIntervalSince(lastFailure) >= backoffDelay
        }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= ttl
    }

    /// Asks whether a check is due right now, remembering one skipped for being offline.
    mutating func shouldRefresh(now: Date = Date(), isOffline: Bool) -> Bool {
        if isOffline {
            owesCatchUp = true
            return false
        }
        return isDue(now: now, isOffline: false)
    }

    mutating func recordSuccess(at now: Date = Date()) {
        lastSuccess = now
        consecutiveFailures = 0
        lastFailure = nil
        owesCatchUp = false
    }

    /// Only automatic failures lengthen the wait; the reader's own failed refresh already
    /// told them, and their next attempt should not be held back.
    mutating func recordFailure(at now: Date = Date(), automatic: Bool) {
        owesCatchUp = false
        if automatic {
            consecutiveFailures += 1
            lastFailure = now
        } else {
            resetBackoff()
        }
    }

    mutating func resetBackoff() {
        consecutiveFailures = 0
        lastFailure = nil
    }
}
