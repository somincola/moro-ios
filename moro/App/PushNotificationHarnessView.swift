#if DEBUG
import SwiftUI
import UIKit
import UserNotifications

/// Themes the harness from the effective color scheme, as the app root does, so the
/// UIKit shell (tab bar, account switcher) matches the SwiftUI content in dark mode.
struct PushNotificationHarnessRoot: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PushNotificationHarnessView()
            .moroTheme(MoroTheme(colorScheme: colorScheme, accent: .monochrome))
    }
}

/// Runs notification opening through the production shell with an isolated transport.
struct PushNotificationHarnessView: View {
    @StateObject private var appState = Self.makeAppState()
    @State private var activeSessionID = "push-a"
    @State private var notificationScheduled = false
    @State private var cacheCleared = false
    private let clientA = PushNotificationFixtureProtocol.makeClient(session: "push-a")
    private let clientB = PushNotificationFixtureProtocol.makeClient(session: "push-b")
    private let scenario = ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] ?? "post"

    // StateObject evaluates this once per harness lifetime. A SwiftUI view init
    // can run repeatedly and must not enqueue the same notification again.
    private static func makeAppState() -> AppState {
        let state = AppState()
        if ProcessInfo.processInfo.environment["UITEST_PRESERVE_NOTIFICATION_SNAPSHOT"] != "1" {
            NotificationSnapshotStore.shared.removeSession("push-a")
            NotificationSnapshotStore.shared.removeSession("push-b")
        }
        state.currentAccount = PushNotificationFixtureProtocol.viewer
        if isSwitcherScenario {
            seedSwitcherAvatars()
            state.currentAccount = switcherSessions.first?.account
        }
        let scenario = ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] ?? "post"
        if scenario == "inbox" {
            AppSettings.shared.notificationPolicy = .anyone
            AppSettings.shared.receiveMentionsAndReplies = true
            AppSettings.shared.receiveFavourites = true
            AppSettings.shared.receiveBoosts = true
        }
        if scenario != "system", scenario != "inbox" {
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
            onSwitchAccount: { id in
                activeSessionID = id
                if Self.isSwitcherScenario {
                    appState.currentAccount = Self.switcherSessions.first { $0.id == id }?.account
                }
            }, onRemoveAccount: { _ in },
            onAccountAuthenticated: { _, _, _ in }
        )
        .id(activeSessionID)
        .environmentObject(appState)
        .overlay(alignment: .topTrailing) {
            if ProcessInfo.processInfo.environment["UITEST_SNAPSHOT_CONTROLS"] == "1" {
                Button(cacheCleared ? "Cache cleared" : "Clear media cache") {
                    Task {
                        await NotificationSnapshotStore.shared.flushPendingWrites()
                        await StorageManagementStore.shared.clear()
                        cacheCleared = true
                    }
                }
                .accessibilityIdentifier("inbox.testClearCache")
                .padding(.top, 56)
            }
        }
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
        // The account switcher tests need distinguishable accounts.
        if Self.isSwitcherScenario { return Self.switcherSessions }
        return ["push-a", "push-b"].map {
            StoredAccountSession(id: $0, account: PushNotificationFixtureProtocol.viewer,
                instanceURLString: "https://\($0).push-fixture.invalid", tokenStorageKey: "unused-push-test-key", lastUsedAt: Date())
        }
    }
}

extension PushNotificationHarnessView {
    static var isSwitcherScenario: Bool {
        ProcessInfo.processInfo.environment["UITEST_SWITCHER_ACCOUNTS"] == "1"
    }

    private static let switcherAccounts: [(id: String, username: String, name: String, hue: CGFloat)] = [
        ("push-a", "viewer", "Viewer", 0.58), ("push-b", "sora", "Sora", 0.93), ("push-c", "kai", "Kai Lin", 0.36),
    ]

    private static func switcherAvatarURL(_ id: String) -> URL {
        URL(string: "https://avatars.push-fixture.invalid/\(id).png")!
    }

    static var switcherSessions: [StoredAccountSession] {
        switcherAccounts.enumerated().map { index, item in
            let avatar = switcherAvatarURL(item.id).absoluteString
            let account = Account(id: "switcher-\(item.id)", username: item.username, acct: item.username,
                displayName: item.name, note: "", avatar: avatar, avatarStatic: avatar, header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 0)
            return StoredAccountSession(id: item.id, account: account,
                instanceURLString: "https://\(item.id).push-fixture.invalid", tokenStorageKey: "unused-push-test-key",
                lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60))
        }
    }

    /// Distinct, offline avatars (a tinted disc with an initial) so animations can be judged.
    static func seedSwitcherAvatars() {
        let size = CGSize(width: 160, height: 160)
        for item in switcherAccounts {
            let image = UIGraphicsImageRenderer(size: size).image { context in
                let colors = [
                    UIColor(hue: item.hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                    UIColor(hue: item.hue, saturation: 0.75, brightness: 0.7, alpha: 1).cgColor,
                ] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    context.cgContext.drawLinearGradient(gradient, start: .zero,
                        end: CGPoint(x: size.width, y: size.height), options: [])
                }
                let initial = String(item.name.prefix(1)) as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 76, weight: .bold), .foregroundColor: UIColor.white,
                ]
                let textSize = initial.size(withAttributes: attributes)
                initial.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                    withAttributes: attributes)
            }
            ImageCache.shared.setImage(image, for: switcherAvatarURL(item.id))
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
        if url.path == "/api/v1/notifications",
            ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_OFFLINE"] == "1" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
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
            // UITEST_NOTIFICATIONS_UNREAD opens Inbox with a badge (a prioritized refresh).
            let unread = ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_UNREAD"].flatMap(Int.init)
            payload = ["count": unread ?? 0]
        } else if url.path == "/api/v1/notifications" {
            if isMessageScenario {
                payload = [["id": "200", "type": "mention", "created_at": "2026-09-10T01:00:00Z",
                    "account": account, "status": status]]
            } else if ProcessInfo.processInfo.environment["UITEST_PUSH_SCENARIO"] == "inbox" {
                payload = Self.inboxNotifications(for: url)
            } else {
                payload = []
            }
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
        let deliver = { [self] in
            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        // UITEST_NOTIFICATIONS_DELAY slows the newest notifications page (initial load and
        // refreshes, not older pages) so a test can watch the refresh in progress.
        if url.path == "/api/v1/notifications", !url.absoluteString.contains("max_id"),
            let delay = ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_DELAY"].flatMap(Double.init) {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
        } else {
            deliver()
        }
    }

    private static func inboxNotifications(for url: URL) -> [[String: Any]] {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let types = query.filter { $0.name == "types[]" }.compactMap(\.value)
        let maxID = query.first { $0.name == "max_id" }?.value.flatMap(Int.init)
        let sinceID = query.first { $0.name == "since_id" }?.value.flatMap(Int.init)
        let limit = query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 30

        func notification(_ id: Int, type: String, text: String, isDirect: Bool = false,
            replyTo: String? = nil) -> [String: Any] {
            var status = DirectMessagesFixtureProtocol.status("inbox-post-\(id)", author: "push-author",
                content: "<p>\(text)</p>", replyTo: replyTo)
            status["visibility"] = isDirect ? "direct" : "public"
            return ["id": String(id), "type": type, "created_at": "2026-09-10T01:00:00Z",
                "account": DirectMessagesFixtureProtocol.account("push-author"), "status": status]
        }

        let groupFirstPage = ProcessInfo.processInfo.environment[
            "UITEST_NOTIFICATIONS_GROUPED"] == "1"
        var items = (301...330).reversed().map {
            notification(
                $0,
                type: groupFirstPage ? "favourite" : "update",
                text: "Recent activity \($0)"
            )
        }
        if ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_UPDATED"] == "1" {
            items.insert(notification(331, type: "update", text: "New activity after restart"), at: 0)
        }
        items += [
            notification(200, type: "mention", text: "Private reply", isDirect: true, replyTo: "inbox-post-199"),
            notification(199, type: "mention", text: "Private initial mention", isDirect: true),
            notification(190, type: "reblog", text: "Boosted post"),
        ]
        if let sinceID {
            let id = sinceID + 1
            if types == ["mention"] {
                items.append(notification(id, type: "mention", text: "New mention \(id)"))
            } else if types.isEmpty {
                items.append(notification(id, type: "update", text: "New activity \(id)"))
            }
        }
        items += (149...180).reversed().map {
            notification($0, type: "favourite", text: "Favourite page item \($0)")
        }
        if ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_GROUPED"] == "1" {
            items = items.map { item in
                var item = item
                let type = item["type"] as? String
                let id = Int(item["id"] as? String ?? "") ?? 0
                if type == "favourite", id >= 151 {
                    item["group_key"] = "grouped-favourites"
                }
                return item
            }
        }
        return Array(items.filter { item in
            let id = Int(item["id"] as? String ?? "") ?? 0
            return (types.isEmpty || types.contains(item["type"] as? String ?? ""))
                && (maxID.map { id < $0 } ?? true)
                && (sinceID.map { id > $0 } ?? true)
        }.prefix(limit))
    }
}
#endif
