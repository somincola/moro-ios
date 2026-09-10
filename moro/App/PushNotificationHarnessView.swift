#if DEBUG
import SwiftUI
import UserNotifications

/// Runs notification opening through the production shell with an isolated transport.
struct PushNotificationHarnessView: View {
    @StateObject private var appState = Self.makeAppState()
    @State private var activeSessionID = "push-a"
    @State private var notificationScheduled = false
    private let clientA = PushNotificationFixtureProtocol.makeClient(session: "push-a")
    private let clientB = PushNotificationFixtureProtocol.makeClient(session: "push-b")
    private let scenario = ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] ?? "post"

    // StateObject evaluates this once per harness lifetime. A SwiftUI view init
    // can run repeatedly and must not enqueue the same notification again.
    private static func makeAppState() -> AppState {
        let state = AppState()
        state.currentAccount = PushNotificationFixtureProtocol.viewer
        let scenario = ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] ?? "post"
        if scenario != "system" {
            let payload: [AnyHashable: Any]
            switch scenario {
            case "malformed": payload = ["x": "push-a", "notification_id": NSNull(), "p": "ciphertext"]
            case "link": payload = ["x": "push-a", "url": "https://remote.example/@person/123"]
            case "removed-account": payload = ["x": "removed", "notification_id": "post"]
            case "other-account": payload = ["x": "push-b", "notification_id": "post"]
            default: payload = ["x": "push-a", "notification_id": scenario]
            }
            PushRegistrationCenter.shared.handleResponse(
                PushNotificationPayload(userInfo: payload),
                actionIdentifier: UNNotificationDefaultActionIdentifier, completionHandler: {})
        }
        return state
    }

    var body: some View {
        MainTabView(
            apiClient: activeSessionID == "push-a" ? clientA : clientB,
            onLogout: {}, accountSessions: sessions, activeSessionID: activeSessionID,
            onSwitchAccount: { activeSessionID = $0 }, onRemoveAccount: { _ in },
            onAccountAuthenticated: { _, _, _ in }
        )
        .id(activeSessionID)
        .environmentObject(appState)
        .overlay(alignment: .top) {
            if scenario == "system" {
                Button(notificationScheduled ? "Notification scheduled" : "Schedule test notification") {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        guard (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true else { return }
                        let content = UNMutableNotificationContent()
                        content.title = "Moro push routing test"
                        content.body = "Open the target post"
                        content.userInfo = ["x": "push-a", "notification_id": "post"]
                        do {
                            try await center.add(UNNotificationRequest(
                                identifier: "moro.push-routing-fixture", content: content,
                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
                            notificationScheduled = true
                        } catch {}
                    }
                }
                .accessibilityIdentifier("push.schedule")
                .disabled(notificationScheduled)
                .padding(.top, 50)
            }
        }
    }

    private var sessions: [StoredAccountSession] {
        ["push-a", "push-b"].map {
            StoredAccountSession(id: $0, account: PushNotificationFixtureProtocol.viewer,
                instanceURLString: "https://\($0).push-fixture.invalid", tokenStorageKey: "unused-push-test-key", lastUsedAt: Date())
        }
    }
}

private final class PushNotificationFixtureToken: AuthTokenProvider {
    var authToken: String? { "push-fixture-token" }
}

private final class PushNotificationFixtureProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static func makeClient(session: String) -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: "https://\(session).push-fixture.invalid")!,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: PushNotificationFixtureToken()))
    }

    static var viewer: Account {
        Account(id: "push-viewer", username: "viewer", acct: "viewer", displayName: "Viewer", note: "",
            avatar: "", avatarStatic: "", header: "", headerStatic: "", followersCount: 0, followingCount: 0, statusesCount: 0)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let account = DirectMessagesFixtureProtocol.account("push-author")
        let isMessageScenario = ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] == "messages"
        var status = DirectMessagesFixtureProtocol.status("push-post", author: "push-author", content: "<p>Push target post on \(url.host ?? "")</p>")
        status["visibility"] = isMessageScenario ? "direct" : "public"
        let payload: Any
        var code = 200
        if url.path == "/api/v1/conversations", isMessageScenario {
            payload = [["id": "push-conversation", "unread": false,
                "accounts": [account], "last_status": status]]
        } else if url.path == "/api/v1/notifications/unread_count" {
            payload = ["count": 0]
        } else if url.path.hasPrefix("/api/v1/notifications/") {
            if url.lastPathComponent == "missing" {
                code = 404; payload = ["error": "Not found"]
            } else {
                payload = ["id": url.lastPathComponent, "type": "mention", "created_at": "2026-09-10T01:00:00Z", "account": account, "status": status]
            }
        } else if url.path.hasSuffix("/context") {
            payload = ["ancestors": [], "descendants": []]
        } else if url.path.hasPrefix("/api/v1/statuses/") {
            payload = status
        } else if url.path.hasSuffix("/search") {
            payload = ["accounts": [], "hashtags": [], "statuses": [status]]
        } else if url.path.hasSuffix("/markers") {
            payload = [:]
        } else if url.path.contains("/instance") {
            code = 404; payload = ["error": "No fixture metadata"]
        } else {
            payload = []
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
#endif
