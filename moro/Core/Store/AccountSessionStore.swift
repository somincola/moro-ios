//
//  AccountSessionStore.swift
//  moro
//
//  Multi-account session persistence backed by UserDefaults + Keychain.
//

import Foundation
import WidgetKit

struct StoredAccountSession: Identifiable, Codable, Equatable {
    let id: String
    var account: Account
    var instanceURLString: String
    var tokenStorageKey: String
    var lastUsedAt: Date

    var instanceURL: URL? {
        URL(string: instanceURLString)
    }

    var instanceHost: String {
        instanceURL?.host ?? instanceURLString
    }
}

struct ActiveAccountSessionPayload {
    let session: StoredAccountSession
    let token: String
    let instanceURL: URL
}

struct SharedActiveAccountSessionSnapshot: Codable, Equatable {
    let sessionID: String
    let account: Account
    let instanceURLString: String
    let tokenStorageKey: String
    let updatedAt: Date

    var instanceURL: URL? {
        URL(string: instanceURLString)
    }
}

final class SharedActiveAccountSessionBootstrapStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = SharedActiveAccountSessionBootstrapStore(
        userDefaults: MoroSharedContainer.sharedUserDefaults()
    )

    private enum Keys {
        static let snapshot = "shared_active_account_session_snapshot_v1"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func load() -> SharedActiveAccountSessionSnapshot? {
        guard let data = userDefaults.data(forKey: Keys.snapshot) else { return nil }
        return try? decoder.decode(SharedActiveAccountSessionSnapshot.self, from: data)
    }

    func save(payload: ActiveAccountSessionPayload, updatedAt: Date = Date()) {
        let snapshot = SharedActiveAccountSessionSnapshot(
            sessionID: payload.session.id,
            account: payload.session.account,
            instanceURLString: payload.instanceURL.absoluteString,
            tokenStorageKey: payload.session.tokenStorageKey,
            updatedAt: updatedAt
        )
        save(snapshot)
    }

    func save(_ snapshot: SharedActiveAccountSessionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: Keys.snapshot)
        reloadWidgets()
    }

    func clear() {
        userDefaults.removeObject(forKey: Keys.snapshot)
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.overview)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.quickActions)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.profileCard)
    }
}

final class AccountSessionStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private enum Keys {
        static let sessions = "stored_account_sessions"
        static let activeSessionID = "active_account_session_id"
        static let legacyAccessToken = "access_token"
        static let legacyInstanceURL = "instance_url"
    }

    private let keychain: KeychainService
    private let userDefaults: UserDefaults
    private let legacyUserDefaults: UserDefaults?
    private let bootstrapStore: SharedActiveAccountSessionBootstrapStore
    private let notificationSnapshots: NotificationSnapshotStore
    private let notificationPolicySnapshots: NotificationPolicySnapshotStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init(keychain: KeychainService = KeychainService()) {
        self.init(
            keychain: keychain,
            userDefaults: MoroSharedContainer.sharedUserDefaults(),
            legacyUserDefaults: .standard,
            bootstrapStore: .shared
        )
    }

    init(
        keychain: KeychainService,
        userDefaults: UserDefaults,
        legacyUserDefaults: UserDefaults? = nil,
        bootstrapStore: SharedActiveAccountSessionBootstrapStore = .shared,
        notificationSnapshots: NotificationSnapshotStore? = nil,
        notificationPolicySnapshots: NotificationPolicySnapshotStore? = nil
    ) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.legacyUserDefaults = legacyUserDefaults
        self.bootstrapStore = bootstrapStore
        self.notificationSnapshots = notificationSnapshots ?? .shared
        self.notificationPolicySnapshots = notificationPolicySnapshots ?? .shared
        migrateLegacyDefaultsIfNeeded()
        syncSharedBootstrapSnapshot()
    }

    var activeSessionID: String? {
        userDefaults.string(forKey: Keys.activeSessionID)
    }

    func allSessions() -> [StoredAccountSession] {
        let sessions = loadSessions()
        return sessions.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    @discardableResult
    func saveSession(
        token: String,
        account: Account,
        instanceURL: URL,
        activate: Bool
    ) throws -> StoredAccountSession {
        var sessions = loadSessions()
        let instanceURLString = instanceURL.absoluteString
        let existingIndex = sessions.firstIndex {
            $0.account.id == account.id && $0.instanceURLString == instanceURLString
        }

        let now = Date()
        let savedSession: StoredAccountSession

        if let existingIndex {
            var session = sessions[existingIndex]
            session.account = account
            session.lastUsedAt = now
            sessions[existingIndex] = session
            savedSession = session
        } else {
            let sessionID = UUID().uuidString
            let tokenStorageKey = "access_token_session_\(sessionID)"
            let session = StoredAccountSession(
                id: sessionID,
                account: account,
                instanceURLString: instanceURLString,
                tokenStorageKey: tokenStorageKey,
                lastUsedAt: now
            )
            sessions.append(session)
            savedSession = session
        }

        try keychain.save(token, forKey: savedSession.tokenStorageKey)
        saveSessions(sessions)

        if activate {
            try setActiveSession(id: savedSession.id)
        } else if savedSession.id == activeSessionID {
            syncSharedBootstrapSnapshot()
        }

        return savedSession
    }

    func payload(forSessionID id: String) throws -> ActiveAccountSessionPayload? {
        guard let session = loadSessions().first(where: { $0.id == id }) else {
            return nil
        }
        guard let token = try keychain.get(forKey: session.tokenStorageKey) else {
            return nil
        }
        guard let instanceURL = session.instanceURL else {
            return nil
        }

        return ActiveAccountSessionPayload(session: session, token: token, instanceURL: instanceURL)
    }

    func activePayload() throws -> ActiveAccountSessionPayload? {
        guard let activeSessionID else { return nil }
        return try payload(forSessionID: activeSessionID)
    }

    func setActiveSession(id: String) throws {
        guard var session = loadSessions().first(where: { $0.id == id }) else {
            return
        }
        guard let token = try keychain.get(forKey: session.tokenStorageKey) else {
            throw KeychainError.unhandledError(status: errSecItemNotFound)
        }
        guard let instanceURL = session.instanceURL else { return }

        if let previous = activeSessionID, previous != id {
            notificationSnapshots.invalidateSession(previous)
            notificationPolicySnapshots.invalidateSession(previous)
        }
        userDefaults.set(id, forKey: Keys.activeSessionID)

        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            session.lastUsedAt = Date()
            sessions[index] = session
            saveSessions(sessions)
        }

        try keychain.save(token, forKey: Keys.legacyAccessToken)
        try keychain.save(instanceURL.absoluteString, forKey: Keys.legacyInstanceURL)
        AppEnvironment.invalidateInstanceURL()

        bootstrapStore.save(
            payload: ActiveAccountSessionPayload(
                session: session,
                token: token,
                instanceURL: instanceURL
            ),
            updatedAt: session.lastUsedAt
        )
    }

    func updateActiveAccount(_ account: Account) {
        guard let activeSessionID else { return }
        var sessions = loadSessions()
        guard let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].account = account
        saveSessions(sessions)
        syncSharedBootstrapSnapshot()
    }

    func removeSession(id: String) throws {
        PushSubscriptionCoordinator.shared.removeSettings(for: id)
        notificationSnapshots.removeSession(id)
        notificationPolicySnapshots.removeSession(id)
        var sessions = loadSessions()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        let removed = sessions.remove(at: index)
        try? keychain.delete(forKey: removed.tokenStorageKey)
        saveSessions(sessions)

        let wasActive = (id == activeSessionID)
        if !wasActive { return }

        if let nextActive = sessions.sorted(by: { $0.lastUsedAt > $1.lastUsedAt }).first {
            try setActiveSession(id: nextActive.id)
        } else {
            userDefaults.removeObject(forKey: Keys.activeSessionID)
            try? keychain.delete(forKey: Keys.legacyAccessToken)
            try? keychain.delete(forKey: Keys.legacyInstanceURL)
            AppEnvironment.invalidateInstanceURL()
            bootstrapStore.clear()
        }
    }

    func clearAllSessions() {
        let sessions = loadSessions()
        for session in sessions {
            PushSubscriptionCoordinator.shared.removeSettings(for: session.id)
            notificationSnapshots.removeSession(session.id)
            notificationPolicySnapshots.removeSession(session.id)
            try? keychain.delete(forKey: session.tokenStorageKey)
        }
        userDefaults.removeObject(forKey: Keys.sessions)
        userDefaults.removeObject(forKey: Keys.activeSessionID)
        try? keychain.delete(forKey: Keys.legacyAccessToken)
        try? keychain.delete(forKey: Keys.legacyInstanceURL)
        AppEnvironment.invalidateInstanceURL()
        bootstrapStore.clear()
    }

    func sharedBootstrapSnapshot() -> SharedActiveAccountSessionSnapshot? {
        bootstrapStore.load()
    }

    private func loadSessions() -> [StoredAccountSession] {
        guard let data = userDefaults.data(forKey: Keys.sessions) else { return [] }
        return (try? decoder.decode([StoredAccountSession].self, from: data)) ?? []
    }

    private func saveSessions(_ sessions: [StoredAccountSession]) {
        guard let data = try? encoder.encode(sessions) else { return }
        userDefaults.set(data, forKey: Keys.sessions)
    }

    private func migrateLegacyDefaultsIfNeeded() {
        guard let legacyUserDefaults,
              legacyUserDefaults !== userDefaults else {
            return
        }

        let currentHasSessions = userDefaults.data(forKey: Keys.sessions) != nil
        let currentHasActiveSession = userDefaults.object(forKey: Keys.activeSessionID) != nil
        guard !currentHasSessions, !currentHasActiveSession else { return }

        let legacySessions = legacyUserDefaults.data(forKey: Keys.sessions)
        let legacyActiveSessionID = legacyUserDefaults.string(forKey: Keys.activeSessionID)
        guard legacySessions != nil || legacyActiveSessionID != nil else { return }

        if let legacySessions {
            userDefaults.set(legacySessions, forKey: Keys.sessions)
            legacyUserDefaults.removeObject(forKey: Keys.sessions)
        }

        if let legacyActiveSessionID {
            userDefaults.set(legacyActiveSessionID, forKey: Keys.activeSessionID)
            legacyUserDefaults.removeObject(forKey: Keys.activeSessionID)
        }
    }

    private func syncSharedBootstrapSnapshot() {
        guard let activeSessionID else {
            bootstrapStore.clear()
            return
        }

        guard let payload = try? payload(forSessionID: activeSessionID) else {
            bootstrapStore.clear()
            return
        }

        bootstrapStore.save(payload: payload, updatedAt: payload.session.lastUsedAt)
    }
}
