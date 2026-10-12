import Foundation
import Testing
@testable import moro

@Suite(.serialized)
@MainActor
struct PushSettingsSyncTests {
    @Test func quickChangesSyncAfterCallerReturnsAndPreserveOtherAlerts() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        let settings = AppSettings(userDefaults: defaults)
        let api = MockMastodonAPI()
        let original = PushSubscription.Alerts(status: true, poll: true, update: true, adminSignUp: true, adminReport: true)
        api.fetchPushSubscriptionHandler = { subscription(original) }
        var updates = [PushSubscription.Alerts]()
        var policies = [String?]()
        api.updatePushSubscriptionHandler = { alerts, policy in
            updates.append(alerts)
            policies.append(policy)
            return subscription(alerts, policy: policy)
        }
        func editAndReturn() {
            settings.receiveMentionsAndReplies = false
            store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
            settings.receiveBoosts = false
            settings.receiveNewFollowers = false
            settings.notificationPolicy = .followers
            store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
        }
        editAndReturn()
        try await finish(store, accountKey: "a")
        #expect(updates.count == 1)
        #expect(policies == ["follower"])
        let saved = try #require(updates.first)
        #expect(!saved.mention && !saved.reblog && !saved.follow && !saved.followRequest)
        #expect(saved.status && saved.poll && saved.update && saved.adminSignUp && saved.adminReport)
        #expect(!store.failedSettings.contains("a"))
    }

    @Test func editDuringRequestEventuallySavesLatestChoice() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        let settings = AppSettings(userDefaults: defaults)
        let api = MockMastodonAPI()
        api.fetchPushSubscriptionHandler = { subscription(.standardDefaults) }
        var received = [Bool]()
        api.updatePushSubscriptionHandler = { alerts, policy in
            received.append(alerts.mention)
            if received.count == 1 {
                settings.receiveMentionsAndReplies = true
                store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
                try await Task.sleep(for: .milliseconds(20))
            }
            return subscription(alerts, policy: policy)
        }
        settings.receiveMentionsAndReplies = false
        store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
        try await finish(store, accountKey: "a")
        #expect(received == [false, true])
    }

    @Test func failureRetainsChoiceAndRestartRetriesOnlyPendingAccount() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(userDefaults: defaults)
        settings.receiveFavourites = false
        let api = MockMastodonAPI()
        api.fetchPushSubscriptionHandler = { subscription(.standardDefaults) }
        var attempts = 0
        api.updatePushSubscriptionHandler = { alerts, policy in
            attempts += 1
            if attempts == 1 { throw MockMastodonAPI.MockError.forcedFailure }
            #expect(!alerts.favourite)
            return subscription(alerts, policy: policy)
        }
        let first = PushSubscriptionCoordinator(userDefaults: defaults)
        first.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
        try await finish(first, accountKey: "a")
        #expect(first.failedSettings.contains("a"))
        #expect(!AppSettings(userDefaults: defaults).receiveFavourites)

        let restarted = PushSubscriptionCoordinator(userDefaults: defaults)
        restarted.resumeSettings(apiClient: api, sessionKey: "b")
        #expect(restarted.savingSettings.isEmpty)
        restarted.resumeSettings(apiClient: api, sessionKey: "a")
        try await finish(restarted, accountKey: "a")
        #expect(attempts == 2)
        #expect(restarted.failedSettings.isEmpty)
        let completed = PushSubscriptionCoordinator(userDefaults: defaults)
        completed.resumeSettings(apiClient: api, sessionKey: "a")
        #expect(completed.savingSettings.isEmpty)
    }

    @Test func failedFetchBeforeSubscriptionLoadsIsRetryable() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        let settings = AppSettings(userDefaults: defaults)
        let api = MockMastodonAPI()
        var fetches = 0
        var saves = 0
        api.fetchPushSubscriptionHandler = {
            fetches += 1
            if fetches == 1 { throw URLError(.notConnectedToInternet) }
            return subscription(.standardDefaults)
        }
        api.updatePushSubscriptionHandler = { alerts, policy in
            saves += 1
            return subscription(alerts, policy: policy)
        }
        store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
        try await finish(store, accountKey: "a")
        #expect(store.failedSettings.contains("a"))
        #expect(saves == 0)
        store.resumeSettings(apiClient: api, sessionKey: "a")
        try await finish(store, accountKey: "a")
        #expect(fetches == 2 && saves == 1)
        #expect(store.failedSettings.isEmpty)
    }

    @Test func accountsKeepIndependentPendingValuesAndSignOutDiscardsUnsentChanges() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        let settings = AppSettings(userDefaults: defaults)
        let apiA = MockMastodonAPI()
        let apiB = MockMastodonAPI()
        var savedA = [Bool]()
        var savedB = [Bool]()
        apiA.fetchPushSubscriptionHandler = { subscription(.standardDefaults) }
        apiB.fetchPushSubscriptionHandler = { subscription(.standardDefaults) }
        apiA.updatePushSubscriptionHandler = { alerts, policy in
            savedA.append(alerts.mention)
            return subscription(alerts, policy: policy)
        }
        apiB.updatePushSubscriptionHandler = { alerts, policy in
            savedB.append(alerts.mention)
            return subscription(alerts, policy: policy)
        }
        settings.receiveMentionsAndReplies = false
        store.saveSettings(.init(settings: settings), apiClient: apiA, accountKey: "a")
        settings.receiveMentionsAndReplies = true
        store.saveSettings(.init(settings: settings), apiClient: apiB, accountKey: "b")
        try await finish(store, accountKey: "a")
        try await finish(store, accountKey: "b")
        #expect(savedA == [false] && savedB == [true])
        store.saveSettings(.init(settings: settings), apiClient: apiA, accountKey: "a")
        store.removeSettings(for: "a")
        try await Task.sleep(for: .milliseconds(650))
        #expect(savedA == [false])
        let restarted = PushSubscriptionCoordinator(userDefaults: defaults)
        restarted.resumeSettings(apiClient: apiA, sessionKey: "a")
        #expect(restarted.savingSettings.isEmpty)
    }

    @Test func openingWithoutEditsDoesNotRewriteServerPreferences() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        store.resumeSettings(apiClient: MockMastodonAPI(), sessionKey: "a")
        #expect(store.savingSettings.isEmpty)
        #expect(store.failedSettings.isEmpty)
        let settings = AppSettings(userDefaults: defaults)
        for (policy, expected) in [(AppSettings.NotificationPolicy.anyone, "all"), (.followers, "follower"), (.followed, "following"), (.noone, "none")] {
            settings.notificationPolicy = policy
            #expect(PushSubscriptionCoordinator.Preferences(settings: settings).policy == expected)
        }
    }

    @Test func queuedClientKeepsTransportAndCredentialsAfterAccountSwitch() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        PushSettingsURLProtocol.clear()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushSettingsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let state = AppState()
        state.authToken = "account-a"
        let client = MastodonClient(baseURL: URL(string: "https://push-fixture.invalid")!,
            session: session, authInterceptor: AuthInterceptor(tokenProvider: state))
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        store.saveSettings(.init(settings: AppSettings(userDefaults: defaults)), apiClient: client, accountKey: "a")
        state.authToken = "account-b"
        try await finish(store, accountKey: "a")
        #expect(store.failedSettings.isEmpty)
        #expect(PushSettingsURLProtocol.headers == ["Bearer account-a", "Bearer account-a"])
        _ = try await client.fetchPushSubscription()
        #expect(PushSettingsURLProtocol.headers.last == "Bearer account-b")
    }

    @Test func subscriptionRecreationCannotOverwriteAConcurrentSettingsSave() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PushSubscriptionCoordinator(userDefaults: defaults)
        let settings = AppSettings(userDefaults: defaults)
        let api = MockMastodonAPI()
        var server = subscription(.standardDefaults)
        var saves = 0
        api.fetchPushSubscriptionHandler = { server }
        api.updatePushSubscriptionHandler = { alerts, policy in
            saves += 1
            server = subscription(alerts, policy: policy)
            return server
        }
        api.createPushSubscriptionHandler = { alerts, policy in
            settings.receiveMentionsAndReplies = false
            store.saveSettings(.init(settings: settings), apiClient: api, accountKey: "a")
            try await finish(store, accountKey: "a")
            #expect(!server.alerts.mention)
            server = subscription(alerts, policy: policy)
            return server
        }
        await store.ensureSubscription(apiClient: api, sessionKey: "a", deviceToken: "00ff")
        try await finish(store, accountKey: "a")
        #expect(saves == 2)
        #expect(!server.alerts.mention)
        #expect(store.failedSettings.isEmpty)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "PushSettingsSyncTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func subscription(_ alerts: PushSubscription.Alerts, policy: String? = "all") -> PushSubscription {
        PushSubscription(id: 1, endpoint: "https://relay.example/a", serverKey: nil, alerts: alerts, policy: policy)
    }

    private func finish(_ store: PushSubscriptionCoordinator, accountKey: String) async throws {
        for _ in 0..<200 {
            if !store.savingSettings.contains(accountKey) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Push settings sync did not finish")
    }
}

private final class PushSettingsURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var capturedHeaders = [String]()
    static var headers: [String] { lock.withLock { capturedHeaders } }
    static func clear() { lock.withLock { capturedHeaders.removeAll() } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "push-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.capturedHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        let data = Data(#"{"id":1,"alerts":{"mention":true,"status":false,"reblog":true,"follow":true,"follow_request":true,"favourite":true,"poll":true,"update":false,"admin.sign_up":false,"admin.report":false},"policy":"all"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
