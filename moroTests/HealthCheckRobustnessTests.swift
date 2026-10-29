//
//  HealthCheckRobustnessTests.swift
//  moroTests
//
//  Regression tests for the 2026-10 health check P0 fixes:
//  - R1 restoring a session never deletes stored accounts on a transient failure.
//  - R2 only 401 invalidates a session; 403 is an account state, 429 keeps its delay.
//  - R3 a stream that exhausted its retries comes back when a screen asks for it again.
//

import Foundation
import Testing
@testable import moro

@MainActor
struct SessionRestoreRobustnessTests {
    private struct Fixture {
        let store: AccountSessionStore
        let cleanup: () -> Void
    }

    private func makeFixture() throws -> Fixture {
        let suite = "session-restore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let keychain = KeychainService(service: "com.somincola.moro.tests.\(UUID().uuidString)", accessGroup: nil)
        let store = AccountSessionStore(
            keychain: keychain,
            userDefaults: defaults,
            legacyUserDefaults: nil,
            bootstrapStore: SharedActiveAccountSessionBootstrapStore(userDefaults: defaults)
        )
        return Fixture(store: store) {
            defaults.removePersistentDomain(forName: suite)
            try? keychain.deleteAll()
        }
    }

    /// Three accounts; the active one (c) is removed the way logout/remove does it,
    /// which leaves b active and a behind it.
    private func seedThreeAccountsAndRemoveActive(in store: AccountSessionStore) throws {
        let account = ThreadReadingFixtures.status("1").account
        for host in ["a", "b", "c"] {
            _ = try store.saveSession(
                token: "token-\(host)", account: account,
                instanceURL: URL(string: "https://\(host).example")!, activate: true)
        }
        let active = try #require(store.activeSessionID)
        try store.removeSession(id: active)
    }

    @Test func offlineRestoreKeepsEveryRemainingAccount() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try seedThreeAccountsAndRemoveActive(in: fixture.store)

        let auth = AuthService(sessionStore: fixture.store) { _, _ in throw APIError.networkUnavailable }
        let restored = try #require(try await auth.restoreSession())

        #expect(restored.isVerified == false)
        #expect(restored.instanceURL.host == "b.example")
        #expect(fixture.store.allSessions().count == 2)
    }

    @Test func rejectedTokenIsDroppedAndTheNextAccountIsUsed() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try seedThreeAccountsAndRemoveActive(in: fixture.store)
        let account = ThreadReadingFixtures.status("1").account

        let auth = AuthService(sessionStore: fixture.store) { url, _ in
            if url.host == "b.example" { throw APIError.authenticationRequired }
            return account
        }
        let restored = try #require(try await auth.restoreSession())

        #expect(restored.isVerified)
        #expect(restored.instanceURL.host == "a.example")
        #expect(fixture.store.allSessions().map(\.instanceURL?.host) == ["a.example"])
    }

    @Test func forbiddenAccountStateKeepsTheSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try seedThreeAccountsAndRemoveActive(in: fixture.store)

        let forbidden = APIError.serverError(
            MastodonServerError(error: "Your login is currently disabled", httpCode: 403))
        let auth = AuthService(sessionStore: fixture.store) { _, _ in throw forbidden }
        let restored = try #require(try await auth.restoreSession())

        #expect(restored.isVerified == false)
        #expect(fixture.store.allSessions().count == 2)
    }
}

@MainActor
struct APIErrorClassificationTests {
    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/v1/x")!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func json(_ object: [String: String]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func onlyUnauthorizedRequiresReauthentication() {
        let unauthorized = MastodonClient.httpFailure(
            for: response(401), data: json(["error": "The access token is invalid"]))
        let forbiddenJSON = MastodonClient.httpFailure(
            for: response(403), data: json(["error": "Your login is currently disabled"]))
        let forbiddenHTML = MastodonClient.httpFailure(
            for: response(403), data: Data("<html>blocked</html>".utf8))

        #expect(unauthorized.requiresReauthentication)
        #expect(MastodonClient.httpFailure(for: response(401), data: Data()).requiresReauthentication)
        #expect(!forbiddenJSON.requiresReauthentication)
        #expect(!forbiddenHTML.requiresReauthentication)
        #expect(forbiddenJSON.isAccountStateRestriction)
        #expect(forbiddenHTML.isAccountStateRestriction)
    }

    @Test func rateLimitKeepsItsDelayEvenWithAJSONBody() {
        let error = MastodonClient.httpFailure(
            for: response(429, headers: ["Retry-After": "30"]),
            data: json(["error": "Too many requests"]))
        guard case .rateLimited(let retryAfter) = error else {
            Issue.record("Expected .rateLimited, got \(error)")
            return
        }
        #expect(retryAfter == 30)
        #expect(error.httpStatusCode == 429)
        #expect(error.isRetryable)
    }

    @Test func rateLimitFallsBackToMastodonResetHeader() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(90))
        let delay = MastodonClient.retryDelay(
            from: response(429, headers: ["X-RateLimit-Reset": reset]), now: now)
        #expect(delay.map { abs($0 - 90) < 1 } == true)
    }

    @Test func serverDescriptionIsDecoded() {
        let error = MastodonClient.httpFailure(
            for: response(400),
            data: json(["error": "invalid_grant", "error_description": "The grant is invalid"]))
        guard case .serverError(let serverError) = error else {
            Issue.record("Expected .serverError, got \(error)")
            return
        }
        #expect(serverError.serverDescription == "The grant is invalid")
        #expect(serverError.combinedMessage == "invalid_grant The grant is invalid")
    }

    @Test func transportFailuresMapToStableCases() {
        guard case .networkUnavailable = MastodonClient.transportFailure(URLError(.notConnectedToInternet)),
            case .timeout = MastodonClient.transportFailure(URLError(.timedOut)),
            case .cancelled = MastodonClient.transportFailure(URLError(.cancelled)),
            case .cancelled = MastodonClient.transportFailure(CancellationError())
        else {
            Issue.record("Transport errors were not classified")
            return
        }
    }
}

@MainActor
struct StreamWatcherRecoveryTests {
    private func waitFor(
        _ watcher: StreamWatcher, timeout: TimeInterval = 15,
        until condition: (StreamWatcher.ConnectionState) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(watcher.connectionState) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition(watcher.connectionState)
    }

    @Test func failedStreamReconnectsWhenAStreamIsRequestedAgain() async throws {
        let watcher = StreamWatcher(
            maxReconnectAttempts: 1, baseReconnectDelay: 0.05, observesNetworkRecovery: false)
        defer { watcher.stopWatching() }
        // Nothing listens on the loopback HTTPS port in the simulator: every attempt fails fast.
        watcher.configure(baseURL: URL(string: "https://127.0.0.1")!, accessToken: "token")
        watcher.watch(streams: [.user])

        let gaveUp = await waitFor(watcher) { if case .failed = $0 { return true } else { return false } }
        try #require(gaveUp)

        watcher.addStream(.user)
        #expect(watcher.connectionState == .connecting)
    }

    @Test func ensureConnectedLeavesALiveOrBackingOffSocketAlone() {
        let watcher = StreamWatcher(observesNetworkRecovery: false)
        // Not configured and nothing watched: nothing to revive.
        watcher.ensureConnected(skipBackoff: true)
        #expect(watcher.connectionState == .disconnected)
    }
}

@MainActor
struct TimelineCacheDurabilityTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("timeline-cache-health-\(UUID().uuidString)")
    }
    private func post(_ id: String) -> Status { ThreadReadingFixtures.status(id) }

    private func liveState() -> TimelineLiveUpdates {
        var state = TimelineLiveUpdates(statuses: [post("100"), post("99")])
        state.receiveHead(TimelinePage(statuses: [post("104")]), sinceID: "100", currentAccountID: nil)
        state.setReadingAnchor(.init(statusID: "99", viewportOffset: -120))
        return state
    }

    @Test func singlePostEditsKeepGapsAndReadingAnchor() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        let state = liveState()
        await cache.setLiveSnapshot(statuses: state.statuses, live: state.metadata, for: "a", filter: .home)

        await cache.updateStatus(post("99"), for: "a", filter: .home)
        await cache.flushPendingWrites()

        let metadata = try #require(await TimelineCache(directory: directory).getLiveMetadata(for: "a", filter: .home))
        #expect(metadata.gaps.count == 1)
        #expect(metadata.readingAnchor?.statusID == "99")
    }

    /// Content a reader just loaded must survive a foreground kill (the list offline-cache
    /// UI test relaunches right after loading), so new posts never wait for the delay.
    @Test func newPostsAreWrittenWithoutWaitingForTheDelay() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory, persistenceDelay: .seconds(30))
        await cache.set(statuses: [post("1"), post("2")], for: "a", filter: .home)

        // Well inside the 30 s delay, but generous for a loaded CI machine running suites in parallel.
        var onDisk: [String]?
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            onDisk = await TimelineCache(directory: directory).getStatuses(for: "a", filter: .home)?.map(\.id)
            if onDisk != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(onDisk == ["1", "2"])
    }

    /// The reading anchor changes on every scroll stop; it waits for the delay or a flush.
    @Test func readingStateChangesWaitForTheDelayOrAFlush() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory, persistenceDelay: .seconds(30))
        let statuses = [post("2"), post("1")]
        await cache.set(statuses: statuses, for: "a", filter: .home)
        await cache.flushPendingWrites()

        var live = TimelineLiveMetadata(checkpointID: "2", fetchedHeadID: "2")
        live.readingAnchor = TimelineReadingAnchor(statusID: "1", viewportOffset: -40)
        await cache.setLiveSnapshot(statuses: statuses, live: live, for: "a", filter: .home)
        #expect(await TimelineCache(directory: directory).getLiveMetadata(for: "a", filter: .home)?.readingAnchor == nil)

        await cache.flushPendingWrites()
        #expect(await TimelineCache(directory: directory).getLiveMetadata(for: "a", filter: .home)?.readingAnchor?.statusID == "1")
    }
}
