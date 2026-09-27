import CryptoKit
import Foundation
import os

/// Reading continuity, not disposable media cache. Settings cache clearing must
/// neither count nor delete these bounded, account-scoped snapshots.
@MainActor
final class NotificationSnapshotStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = NotificationSnapshotStore()

    nonisolated struct Session: Equatable {
        let id: String
        fileprivate let generation: UUID
    }

    nonisolated struct Snapshot: Codable {
        var version = 1
        var notifications: [NotificationItem]
        var newestID: String?
        var olderCursor: String?
        var hasMore: Bool
        var relationships: [String: Relationship]
        var savedAt: Date

        func bounded(to limit: Int) -> Self {
            var result = self
            var seen: Set<String> = []
            let unique = notifications.filter { seen.insert($0.id).inserted }
            result.notifications = Array(unique.prefix(limit))
            if unique.count > limit {
                // The on-disk tail is shorter than the in-memory history.
                result.olderCursor = result.notifications.last?.id
                result.hasMore = true
            }
            let accountIDs = Set(result.notifications.map { $0.account.id })
            result.relationships = relationships.filter { accountIDs.contains($0.key) }
            return result
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotificationReadingState", isDirectory: true)
    }

    private let disk: NotificationSnapshotDisk
    private let maximumItems: Int
    private var generations: [String: UUID] = [:]
    private var removedIDs: [String: Set<String>] = [:]
    private var pendingWrite: Task<Void, Never>?

    init(directory: URL? = nil, maximumItems: Int = 200) {
        disk = NotificationSnapshotDisk(directory: directory ?? Self.defaultDirectory)
        self.maximumItems = max(1, maximumItems)
    }

    func session(for id: String) -> Session {
        let generation = generations[id] ?? UUID()
        generations[id] = generation
        return Session(id: id, generation: generation)
    }

    func isCurrent(_ session: Session) -> Bool {
        generations[session.id] == session.generation
    }

    func load(for session: Session, scope: MastodonNotificationScope) async -> Snapshot? {
        guard isCurrent(session) else { return nil }
        await pendingWrite?.value
        guard isCurrent(session),
            var snapshot = await disk.load(sessionID: session.id, scope: scope.rawValue),
            isCurrent(session), snapshot.version == 1
        else { return nil }
        snapshot.notifications.removeAll { removedIDs[session.id, default: []].contains($0.id) }
        return snapshot.bounded(to: maximumItems)
    }

    @discardableResult
    func save(_ snapshot: Snapshot, for session: Session, scope: MastodonNotificationScope) -> Task<Void, Never>? {
        guard isCurrent(session) else { return nil }
        var snapshot = snapshot
        snapshot.notifications.removeAll { removedIDs[session.id, default: []].contains($0.id) }
        let bounded = snapshot.bounded(to: maximumItems)
        let disk = disk
        return enqueue { await disk.save(bounded, sessionID: session.id, scope: scope.rawValue) }
    }

    @discardableResult
    func removeNotifications(_ ids: Set<String>, for session: Session) -> Task<Void, Never>? {
        guard isCurrent(session) else { return nil }
        removedIDs[session.id, default: []].formUnion(ids)
        let disk = disk
        let scopes = MastodonNotificationScope.allCases.map(\.rawValue)
        return enqueue {
            for scope in scopes {
                guard var snapshot = await disk.load(sessionID: session.id, scope: scope) else { continue }
                snapshot.notifications.removeAll { ids.contains($0.id) }
                await disk.save(snapshot, sessionID: session.id, scope: scope)
            }
        }
    }

    /// Invalidate synchronously, then delete after all earlier writes. A late
    /// response from a removed account cannot recreate its private content.
    @discardableResult
    func removeSession(_ id: String) -> Task<Void, Never> {
        invalidateSession(id)
        removedIDs[id] = nil
        let disk = disk
        return enqueue { await disk.removeSession(id) }
    }

    /// Account switching ends the old feed's ownership without deleting its snapshot.
    func invalidateSession(_ id: String) {
        generations[id] = UUID()
    }

    func flushPendingWrites() async {
        await pendingWrite?.value
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pendingWrite
        let task = Task {
            await previous?.value
            await operation()
        }
        pendingWrite = task
        return task
    }
}

/// File I/O and encoding are serialized off the UI actor. The owner orders
/// operations explicitly rather than assuming actor tasks execute FIFO.
private actor NotificationSnapshotDisk {
    let directory: URL
    private let logger = Logger(subsystem: "com.moro", category: "NotificationReadingState")

    init(directory: URL) { self.directory = directory }

    func load(sessionID: String, scope: String) -> NotificationSnapshotStore.Snapshot? {
        guard let data = try? Data(contentsOf: fileURL(sessionID: sessionID, scope: scope)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotificationSnapshotStore.Snapshot.self, from: data)
    }

    func save(_ snapshot: NotificationSnapshotStore.Snapshot, sessionID: String, scope: String) {
        do {
            var folder = accountDirectory(sessionID)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL(sessionID: sessionID, scope: scope),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Could not save notification reading snapshot")
        }
    }

    func removeSession(_ id: String) {
        let folder = accountDirectory(id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do { try FileManager.default.removeItem(at: folder) }
        catch { logger.error("Could not remove notification reading snapshot") }
    }

    private func accountDirectory(_ id: String) -> URL {
        let key = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key, isDirectory: true)
    }

    private func fileURL(sessionID: String, scope: String) -> URL {
        accountDirectory(sessionID).appendingPathComponent(scope + ".json")
    }
}
