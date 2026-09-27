//
//  NotificationPolicySnapshotStore.swift
//  moro
//
//  Last-known server notification policy, isolated by account session.
//

import Foundation

/// A small configuration snapshot, not disposable media/content cache. It is
/// intentionally stored outside `CacheManager` so clearing app caches does not
/// bring back a blank notification-settings screen.
@MainActor
final class NotificationPolicySnapshotStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = NotificationPolicySnapshotStore()

    struct Session: Equatable {
        let id: String
        fileprivate let generation: UUID
    }

    struct Snapshot: Codable, Equatable {
        var version = 1
        var policy: ServerNotificationPolicy
        var savedAt: Date
    }

    private enum Keys {
        static let snapshots = "notification_policy_snapshots_v1"
    }

    private let userDefaults: UserDefaults
    private var generations: [String: UUID] = [:]

    init(userDefaults: UserDefaults = MoroSharedContainer.sharedUserDefaults()) {
        self.userDefaults = userDefaults
    }

    func session(for id: String) -> Session {
        let generation = generations[id] ?? UUID()
        generations[id] = generation
        return Session(id: id, generation: generation)
    }

    func isCurrent(_ session: Session) -> Bool {
        return generations[session.id] == session.generation
    }

    func load(for session: Session) -> Snapshot? {
        guard generations[session.id] == session.generation,
            let snapshot = loadSnapshots()[session.id], snapshot.version == 1
        else { return nil }
        return snapshot
    }

    @discardableResult
    func save(
        _ policy: ServerNotificationPolicy,
        for session: Session,
        savedAt: Date = Date()
    ) -> Bool {
        guard generations[session.id] == session.generation else { return false }
        var snapshots = loadSnapshots()
        snapshots[session.id] = Snapshot(policy: policy, savedAt: savedAt)
        saveSnapshots(snapshots)
        return true
    }

    /// Remove an unsupported/stale snapshot while keeping the current page's
    /// lease valid so a later retry can persist a newly supported response.
    func clear(for session: Session) {
        guard generations[session.id] == session.generation else { return }
        removeSnapshot(session.id)
    }

    /// Account switching invalidates the old page without deleting its useful
    /// last-known value. A late response from that page can no longer overwrite it.
    func invalidateSession(_ id: String) {
        generations[id] = UUID()
    }

    /// Logout/account removal invalidates outstanding work and deletes the
    /// account-specific configuration snapshot.
    func removeSession(_ id: String) {
        generations[id] = UUID()
        removeSnapshot(id)
    }

    private func loadSnapshots() -> [String: Snapshot] {
        guard let data = userDefaults.data(forKey: Keys.snapshots) else { return [:] }
        return (try? JSONDecoder().decode([String: Snapshot].self, from: data)) ?? [:]
    }

    private func saveSnapshots(_ snapshots: [String: Snapshot]) {
        guard !snapshots.isEmpty else {
            userDefaults.removeObject(forKey: Keys.snapshots)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        userDefaults.set(data, forKey: Keys.snapshots)
    }

    private func removeSnapshot(_ id: String) {
        var snapshots = loadSnapshots()
        snapshots[id] = nil
        saveSnapshots(snapshots)
    }
}
