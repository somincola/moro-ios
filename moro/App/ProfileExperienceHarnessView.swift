#if DEBUG
import SwiftUI

/// Exercises production profile screens without sending writes to a real account.
struct ProfileExperienceHarnessView: View {
    @StateObject private var coordinator = RootTabCoordinator(selectedTab: .me)
    @StateObject private var appState: AppState
    @State private var showsSettings = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let client = ProfileFixtureProtocol.makeClient()
    private static let accountKey = "ui-profile-experience"

    init() {
        _appState = StateObject(wrappedValue: Self.makeState())
    }

    private static func makeState() -> AppState {
        if ProcessInfo.processInfo.environment["UITEST_PROFILE_ANIMATED_MEDIA"] == "1" {
            ProfileMediaFixture.prepare()
        }
        let state = AppState()
        state.currentAccount = ProfileFixtureProtocol.account(
            id: ProcessInfo.processInfo.environment["UITEST_OTHER_PROFILE"] == "1" ? "fixture-viewer" : nil)
        state.authToken = "profile-fixture-token"
        state.isAuthenticated = true
        ProfilePresentationPreferences.shared.setShowsFeaturedTags(
            ProcessInfo.processInfo.environment["UITEST_PROFILE_TAGS_DISABLED"] != "1",
            accountKey: accountKey)
        return state
    }

    var body: some View {
        // Use the app's real UIKit navigation container. A standalone SwiftUI
        // NavigationStack can hide navigationDestination compatibility failures.
        MainShellContainerRepresentable(
            coordinator: coordinator,
            theme: theme,
            unreadInboxCount: 0,
            currentUserAvatarURL: nil,
            contentVersion: Self.accountKey,
            homeView: AnyView(EmptyView()),
            exploreView: AnyView(EmptyView()),
            inboxView: AnyView(EmptyView()),
            meView: routedView(
                AnyView(ProfileView(account: ProfileFixtureProtocol.account(), onLogout: {}, apiClient: client)),
                router: coordinator.meRouter),
            routeView: { route, router in
                routedView(
                    AppRouteViewFactory(apiClient: client, appState: appState, cacheManager: .shared)
                        .view(for: route), router: router)
            }
        )
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .environmentObject(appState)
        .environment(\.activeAccountKey, Self.accountKey)
        .environment(\.moroMediaPrefs, MoroMediaPreferences(
            autoplayGIFs: ProcessInfo.processInfo.environment["UITEST_PROFILE_AUTOPLAY_OFF"] != "1"))
        .moroTheme(theme)
        .sheet(isPresented: $showsSettings) {
            SettingsSheetView(apiClient: client)
                .environmentObject(appState)
                .moroTheme(theme)
                .moroSheetSurface(detents: [.large], cornerRadius: 20)
        }
    }

    private var theme: MoroTheme {
        MoroTheme(
            colorScheme: ProcessInfo.processInfo.environment["UITEST_COLOR_SCHEME"] == "dark" ? .dark : .light,
            dynamicTypeSize: dynamicTypeSize)
    }

    private func routedView(_ content: AnyView, router: AppRouter) -> AnyView {
        AnyView(content
            .environment(\.settingsPresentationAction, { showsSettings = true })
            .environment(\.appRouter, router)
            .environment(\.activeAccountKey, Self.accountKey)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.mastodonAPIClient, client)
            .environmentObject(router)
            .environmentObject(appState)
            .moroTheme(theme))
    }
}

private final class ProfileFixtureToken: AuthTokenProvider {
    var authToken: String? { "profile-fixture-token" }
}

final class ProfileFixtureProtocol: URLProtocol, @unchecked Sendable {
    private var pushResponseTask: Task<Void, Never>?
    private static let lock = NSLock()
    private static let legacy = ProcessInfo.processInfo.environment["UITEST_PROFILE_LEGACY"] == "1"
    private static let compactInfo = ProcessInfo.processInfo.environment["UITEST_PROFILE_COMPACT_INFO"] == "1"
    // Keep persisted instance limits isolated between test app launches.
    private static let instanceURL = URL(string: "https://\(UUID().uuidString.lowercased()).profile-fixture.invalid")!
    private static var profile: [String: Any] = [
        "id": "fixture-profile", "display_name": "Moro Tester",
        "note": "Building for the open web.\nhttps://example.com/a/long/path?first=1&second=2",
        "fields": [
            ["name": "Website", "value": "https://example.com/a/long/path?first=1&second=2"],
            ["name": "About", "value": "Independent developer 👋"],
            ["name": "Garden", "value": "A space for small, thoughtful things."],
        ],
        "show_media": true, "show_media_replies": true,
        "show_featured": true,
        "hide_collections": ProcessInfo.processInfo.environment["UITEST_PROFILE_HIDE_COLLECTIONS"] == "1",
    ]
    private static var tags: [[String: Any]] = ProcessInfo.processInfo.environment["UITEST_PROFILE_EMPTY_TAGS"] == "1" ? [] : [
        ["id": "tag-app", "name": "app", "statuses_count": "2"],
        ["id": "tag-daily", "name": "daily", "statuses_count": "1"],
    ]
    private static var pushSaveAttempts = 0
    /// Visitor-mode relationship. Unset keeps the historical empty `/relationships` reply.
    private static let relationshipMode = ProcessInfo.processInfo.environment["UITEST_PROFILE_RELATIONSHIP"]
    private static var relationship: [String: Any] = [
        "id": "fixture-profile", "following": relationshipMode == "following", "followed_by": false,
        "blocking": false, "blocked_by": false, "muting": false, "muting_notifications": false,
        "requested": false, "domain_blocking": false, "endorsed": false, "notifying": false,
    ]
    private static var pushSubscription: [String: Any] = [
        "id": 1, "endpoint": "https://relay-fixture.invalid/push", "policy": "all",
        "alerts": ["mention": true, "status": false, "reblog": true, "follow": true,
            "follow_request": true, "favourite": true, "poll": true, "update": false,
            "admin.sign_up": false, "admin.report": false],
    ]
    private static var notificationPolicy: [String: Any] = [
        "for_not_following": "accept", "for_not_followers": "filter",
        "for_new_accounts": "filter", "for_private_mentions": "drop",
        "for_limited_accounts": "filter", "for_bots": "drop",
        "summary": ["pending_requests_count": 0, "pending_notifications_count": 0],
    ]

    @MainActor static func makeClient() -> MastodonClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return MastodonClient(baseURL: instanceURL,
            session: URLSession(configuration: configuration),
            authInterceptor: AuthInterceptor(tokenProvider: ProfileFixtureToken()))
    }

    static func account(id: String? = nil) -> Account {
        lock.withLock {
            var payload = accountPayload()
            if let id { payload["id"] = id }
            return try! JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: payload))
        }
    }

    private static func accountPayload() -> [String: Any] {
        var payload = profile
        payload.merge([
            "username": "moro", "acct": "moro", "avatar": "", "avatar_static": "",
            "header": "", "header_static": "", "followers_count": 10, "following_count": 5,
            "statuses_count": 3, "url": "https://profile-fixture.invalid/@moro",
            "source": ["note": profile["note"]!, "fields": profile["fields"]!, "privacy": "public"],
        ]) { _, new in new }
        if compactInfo {
            payload["note"] = "<p>Indie developer and creator of Moro for Mastodon.</p><p>Building thoughtful products for the open web.</p><p>Happy to be here—nice to meet you all! 👋</p>"
            payload["fields"] = [
                ["name": "X", "value": "<a href=\"https://x.com/hey_akie\">x.com/hey_akie</a>"],
                ["name": "blog", "value": "<a href=\"https://somlar.com\">somlar.com</a>", "verified_at": "2026-09-27T00:00:00.000Z"],
            ]
            payload["statuses_count"] = 598
            payload["following_count"] = 86
            payload["followers_count"] = 70
        }
        if legacy { for key in ["show_media", "show_media_replies", "show_featured"] { payload.removeValue(forKey: key) } }
        if let avatar = ProcessInfo.processInfo.environment["UITEST_PROFILE_AVATAR_URL"] {
            payload["avatar"] = avatar
            payload["avatar_static"] = avatar
        }
        if ProcessInfo.processInfo.environment["UITEST_PROFILE_MEDIA"] == "1" {
            for (key, file) in [("avatar", "avatar"), ("avatar_static", "avatar"), ("header", "header"), ("header_static", "header")] {
                payload[key] = "https://profile-fixture.invalid/\(file).png"
            }
        }
        if ProcessInfo.processInfo.environment["UITEST_PROFILE_ANIMATED_MEDIA"] == "1" {
            payload["avatar"] = ProfileMediaFixture.avatarURL.absoluteString
            payload["avatar_static"] = ProfileMediaFixture.staticAvatarURL.absoluteString
            payload["header"] = ProfileMediaFixture.headerURL.absoluteString
            payload["header_static"] = ProfileMediaFixture.staticHeaderURL.absoluteString
        }
        return payload
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path.hasSuffix("/relationships") == true,
           let delay = ProcessInfo.processInfo.environment["UITEST_PROFILE_RELATIONSHIP_DELAY"].flatMap(Double.init) {
            pushResponseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.completeLoading()
            }
            return
        }
        if request.url?.path == "/api/v1/push/subscription", request.httpMethod == "GET",
           ProcessInfo.processInfo.environment["UITEST_SETTINGS_PUSH_SYNC"] == "1" {
            pushResponseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.completeLoading()
            }
            return
        }
        completeLoading()
    }

    private func completeLoading() {
        do {
            let (code, payload) = Self.lock.withLock { Self.response(request) }
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() { pushResponseTask?.cancel() }

    private static func response(_ request: URLRequest) -> (Int, Any) {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { query.first { $0.name == name }?.value }
        if path == "/api/v1/mutes" || path == "/api/v1/blocks" {
            var managed = accountPayload()
            managed.merge(["id": "fixture-governance", "username": "managed", "acct": "managed",
                           "display_name": "Managed account"]) { _, new in new }
            return (200, [managed])
        }
        if path.hasSuffix("/unmute") || path.hasSuffix("/unblock") {
            let id = path.split(separator: "/").dropLast().last.map(String.init) ?? "fixture-governance"
            return (200, ["id": id, "following": false, "followed_by": false,
                          "blocking": false, "blocked_by": false, "muting": false,
                          "muting_notifications": false, "requested": false,
                          "domain_blocking": false, "endorsed": false, "notifying": false])
        }
        if path == "/api/v2/filters" {
            return (200, [["id": "fixture-filter", "title": "Spoiler filter", "context": ["home"],
                           "expires_at": NSNull(), "filter_action": "warn",
                           "keywords": [["id": "fixture-keyword", "keyword": "spoiler", "whole_word": true]]]])
        }
        if path.hasPrefix("/api/v2/filters/"), method == "DELETE" { return (200, [:]) }
        if path == "/api/v1/domain_blocks" {
            return (200, method == "GET" ? ["blocked.example.invalid"] : [])
        }
        if path == "/api/v1/push/subscription" {
            if method == "PUT" {
                pushSaveAttempts += 1
                if pushSaveAttempts == 1, ProcessInfo.processInfo.environment["UITEST_PUSH_SAVE_FAILS_ONCE"] == "1" {
                    return (503, ["error": "Fixture sync failure"])
                }
                if let update = try? JSONSerialization.jsonObject(with: body(request)) as? [String: Any],
                   let data = update["data"] as? [String: Any] {
                    pushSubscription.merge(data) { _, new in new }
                }
            }
            return (200, pushSubscription)
        }
        if path == "/api/v2/notifications/policy" {
            if method == "PUT", let update = try? JSONSerialization.jsonObject(with: body(request)) as? [String: Any] {
                notificationPolicy.merge(update) { _, new in new }
            }
            return (200, notificationPolicy)
        }
        if path == "/api/v1/profile" {
            if legacy { return (404, ["error": "Not found"]) }
            if method == "PATCH", let update = try? JSONSerialization.jsonObject(with: body(request)) as? [String: Any] {
                profile.merge(update) { _, new in new }
            }
            return (200, profile)
        }
        if path.hasSuffix("/update_credentials") {
            let fields = multipartFields(request)
            for key in ["display_name", "note"] { if let value = fields[key] { profile[key] = value } }
            if let value = fields["hide_collections"] { profile["hide_collections"] = value == "true" }
            if fields.keys.contains(where: { $0.hasPrefix("fields_attributes[") }) {
                var updated: [[String: String]] = []
                for index in 0..<10 {
                    if let name = fields["fields_attributes[\(index)][name]"],
                       let value = fields["fields_attributes[\(index)][value]"] {
                        updated.append(["name": name, "value": value])
                    }
                }
                profile["fields"] = updated
            }
            return (200, accountPayload())
        }
        if path.hasSuffix("/featured_tags/suggestions") {
            return (200, [["name": "swift", "url": "https://profile-fixture.invalid/tags/swift"]])
        }
        if path.hasSuffix("/featured_tags") {
            if method == "POST", let values = try? JSONSerialization.jsonObject(with: body(request)) as? [String: String], let name = values["name"] {
                let tag: [String: Any] = ["id": "tag-\(name)", "name": name, "statuses_count": "0"]
                tags.append(tag)
                return (200, tag)
            }
            return (200, tags)
        }
        if path.contains("/featured_tags/"), method == "DELETE" {
            if ProcessInfo.processInfo.environment["UITEST_PROFILE_DELETE_FAILS"] == "1" {
                return (503, ["error": "Could not remove this tag. Try again."])
            }
            tags.removeAll { $0["id"] as? String == url.lastPathComponent }
            return (200, [:])
        }
        if path.hasSuffix("/relationships") { return (200, relationshipMode == nil ? [] : [relationship]) }
        if relationshipMode != nil, method == "POST", path.hasSuffix("/follow") {
            let options = (try? JSONSerialization.jsonObject(with: body(request))) as? [String: Any] ?? [:]
            relationship["following"] = true
            if let notify = options["notify"] as? Bool { relationship["notifying"] = notify }
            return (200, relationship)
        }
        if relationshipMode != nil, method == "POST", path.hasSuffix("/unfollow") {
            relationship["following"] = false
            relationship["notifying"] = false
            return (200, relationship)
        }
        if path.hasSuffix("/followers") || path.hasSuffix("/following") {
            var connection = accountPayload()
            connection["id"] = "fixture-connection"
            connection["username"] = "connection"
            connection["acct"] = "connection"
            connection["display_name"] = "Connection Tester"
            return (200, [connection])
        }
        if path.hasSuffix("/statuses") {
            if parameter("only_media") == "true" { return (200, []) }
            if parameter("exclude_replies") == "false", parameter("pinned") != "true" {
                if ProcessInfo.processInfo.environment["UITEST_PROFILE_NO_REPLIES"] == "1" {
                    let cursor = Int(parameter("max_id") ?? "1000") ?? 1000
                    return (200, (1...20).map { post(String(cursor - $0)) })
                }
                if parameter("max_id") == nil { return (200, (200..<220).map { post(String($0)) }) }
                var reply = post("90")
                reply["in_reply_to_id"] = "88"
                reply["content"] = "<p>Reply from the second page</p>"
                return (200, [reply])
            }
            if parameter("max_id") != nil { return (200, []) }
            let selected = parameter("tagged")
            let ids = parameter("pinned") == "true" ? ["100"] : ["100", "99", "98"]
            return (200, ids.filter { selected == nil || ($0 == "98" ? "daily" : "app") == selected }.map { post($0) })
        }
        if path.hasSuffix("/context") { return (200, ["ancestors": [], "descendants": []]) }
        if path.contains("/statuses/") { return (200, post(url.lastPathComponent)) }
        if path.contains("/accounts/") { return (200, accountPayload()) }
        if path.hasSuffix("/instance") {
            let fieldValueLimit = ProcessInfo.processInfo.environment["UITEST_PROFILE_LOWER_FIELD_LIMIT"] == "1" ? 20 : 255
            return (200, ["domain": "profile-fixture.invalid", "title": "Profile fixture", "version": "4.7.1",
                          "configuration": ["accounts": ["max_profile_fields": 4, "max_featured_tags": 10,
                                                         "profile_field_value_limit": fieldValueLimit]]])
        }
        return (200, [])
    }

    private static func post(_ id: String) -> [String: Any] {
        ["id": id, "content": "<p>\(id == "100" ? "Pinned app post" : id == "99" ? "Latest app post" : "Daily garden post")</p>",
         "created_at": "2026-09-05T10:00:00.000Z", "account": accountPayload(),
         "media_attachments": [], "favourites_count": 0, "reblogs_count": 0, "replies_count": 0,
         "visibility": "public", "sensitive": false, "spoiler_text": ""]
    }

    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func multipartFields(_ request: URLRequest) -> [String: String] {
        guard let boundary = request.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: "boundary=").last else { return [:] }
        var fields: [String: String] = [:]
        for part in String(decoding: body(request), as: UTF8.self).components(separatedBy: "--\(boundary)") {
            guard let split = part.range(of: "\r\n\r\n"),
                  let start = part[..<split.lowerBound].range(of: "name=\"")?.upperBound,
                  let end = part[start...].firstIndex(of: "\"") else { continue }
            let value = String(part[split.upperBound...])
            // CRLF is one extended grapheme cluster in Swift String.
            fields[String(part[start..<end])] = value.hasSuffix("\r\n") ? String(value.dropLast()) : value
        }
        return fields
    }
}
#endif
