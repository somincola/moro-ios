#if DEBUG
import SDWebImage
import SwiftUI

/// Store assets use the production shell and screens with fictional, offline data.
///
/// `STORE_SHOWCASE=1` switches to the richer showcase fixtures: content in the app's
/// language, several signed-in accounts for the switcher, and the theme from settings.
/// `STORE_SCENE` picks the screen: `main` (default), `display` or `editProfile`. On `main`,
/// `STORE_TAB` (`home`, `explore`, `inbox`, `me`) picks the tab and `STORE_THREAD` (a post
/// index, 0–3) opens that post's thread: in the second column on iPhone Duo's wide display,
/// as a pushed page elsewhere.
struct AppStoreScreenshotHarnessView: View {
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var ready = false
    /// `STORE_THREAD`'s post, loaded through the client (its dates need the API decoder).
    @State private var showcaseThread: Status?
    private let client = AppStoreScreenshotProtocol.makeClient()

    private var showcase: Bool { AppStoreScreenshotProtocol.showcase }
    private var scene: String { ProcessInfo.processInfo.environment["STORE_SCENE"] ?? "main" }

    var body: some View {
        Group {
            if ready {
                switch scene {
                case "display":
                    NavigationStack { DisplaySettingsView() }
                case "editProfile":
                    NavigationStack {
                        EditProfileView(apiClient: client, currentAccount: appState.currentAccount)
                    }
                    .environmentObject(appState)
                default:
                    MainTabView(apiClient: client, onLogout: {}, accountSessions: sessions,
                        activeSessionID: showcase ? sessions.first?.id : "app-store-screenshots",
                        onSwitchAccount: { _ in }, onRemoveAccount: { _ in },
                        onAccountAuthenticated: { _, _, _ in }, showcaseStart: showcaseStart)
                        .environmentObject(appState)
                }
            } else {
                ProgressView().task {
                    if showcase {
                        // Every launch starts from the fixtures: no posts or notifications cached
                        // by an earlier run, which may have been in another language.
                        for id in sessions.map(\.id) {
                            await NotificationSnapshotStore.shared.removeSession(id).value
                        }
                        await CacheManager.shared.timelineCache.clearAllCaches()
                        CacheManager.shared.threadCache.invalidateAll()
                        CacheManager.shared.accountCache.clear()
                    }
                    await AppStoreScreenshotProtocol.cacheIllustrations()
                    appState.currentAccount = AppStoreScreenshotProtocol.decodedAccount(0)
                    appState.isAuthenticated = true
                    AppSettings.shared.notificationPolicy = .anyone
                    if let color = ProcessInfo.processInfo.environment["STORE_THEME_COLOR"]
                        .flatMap(MoroThemeColor.init(rawValue:)) {
                        settings.themeColor = color
                    }
                    if let index = ProcessInfo.processInfo.environment["STORE_THREAD"].flatMap(Int.init),
                        (0...3).contains(index)
                    {
                        showcaseThread = try? await client.fetchStatusDetail(id: String(900 - index))
                    }
                    ready = true
                }
            }
        }
        .moroTheme(showcase ? MoroTheme(colorScheme: colorScheme, accent: settings.accentStyle,
                                        themeColor: settings.themeColor,
                                        customThemeColor: settings.customThemeColor,
                                        postFontSize: settings.postFontSize) : MoroTheme())
    }

    private var showcaseStart: ShowcaseStart? {
        let tab = ProcessInfo.processInfo.environment["STORE_TAB"].flatMap(MainTab.init(rawValue:))
        guard tab != nil || showcaseThread != nil else { return nil }
        return ShowcaseStart(tab: tab ?? .home, status: showcaseThread)
    }

    /// The signed-in accounts the switcher offers, each on its own server.
    private var sessions: [StoredAccountSession] {
        guard showcase else { return [] }
        let hosts = ["moro.social", "m.cmx.im", "mastodon.social"]
        return hosts.indices.compactMap { index in
            guard let account = AppStoreScreenshotProtocol.decodedAccount(index) else { return nil }
            return StoredAccountSession(id: "store-session-\(index)", account: account,
                instanceURLString: "https://\(hosts[index])", tokenStorageKey: "store-token-\(index)",
                lastUsedAt: Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 3600))
        }
    }
}

private final class AppStoreScreenshotToken: AuthTokenProvider {
    var authToken: String? { "offline-screenshot-token" }
}

private final class AppStoreScreenshotProtocol: URLProtocol, @unchecked Sendable {
    private static let base = "https://moro-screenshots.invalid"
    static var showcase: Bool { ProcessInfo.processInfo.environment["STORE_SHOWCASE"] == "1" }
    /// Showcase content follows the app's language; Chinese gets its own fixtures.
    static var chinese: Bool { showcase && (Locale.preferredLanguages.first ?? "").hasPrefix("zh") }

    private static var names: [String] {
        chinese ? ["林知夏", "陈屿", "苏晚", "周默", "许诺", "唐一舟", "白芷", "程野"]
            : ["Alex Rivers", "Luna Park", "Sam Chen", "Mira Stone", "Nora Hale", "Theo Grant", "Ivy Lane", "Kai Morgan"]
    }
    private static var tagNames: [String] {
        if usesPhotos {
            return chinese ? ["摄影", "猫", "咖啡", "读书"] : ["Photography", "Cats", "Coffee", "Books"]
        }
        return chinese ? ["摄影", "插画", "自然", "读书"] : ["Photography", "Art", "Nature", "Books"]
    }

    // MARK: Showcase photos

    /// Licensed photos for the showcase (see `screenshots/app-store/showcase-assets/CREDITS.md`),
    /// read straight from the checkout so they never ship inside the app: this works in the
    /// simulator, where the app can read the Mac's files. `STORE_ASSETS` overrides the folder.
    /// Without it (a device, or no checkout) the showcase falls back to drawn illustrations.
    private static let photosDirectory: URL? = {
        let url = ProcessInfo.processInfo.environment["STORE_ASSETS"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("screenshots/app-store/showcase-assets")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    static var usesPhotos: Bool { showcase && photosDirectory != nil }

    private static let avatarPhotos = ["avatar-0-corgi.jpg", "avatar-1-cat.jpg", "avatar-2-shiba.jpg", "avatar-3-hiker.jpg",
        "post-3-city-sunset.jpg", "header-0-sea.jpg", "post-2-reading-corner.jpg", "post-2-latte.jpg"]
    private static let headerPhotos = ["header-0-sea.jpg", "post-1-cat-sunlight.jpg", "post-2-latte.jpg", "post-3-city-sunset.jpg",
        "post-3-city-sunset.jpg", "header-0-sea.jpg", "post-2-reading-corner.jpg", "post-2-latte.jpg"]

    /// Versioned by file size, so a replaced photo never comes back from the image cache.
    private static func photoURL(_ name: String) -> String {
        "\(base)/photos/\(name)?v=\(photoVersions[name] ?? 0)"
    }

    private static let photoVersions: [String: Int] = {
        guard let directory = photosDirectory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [:] }
        var versions: [String: Int] = [:]
        for name in names {
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            versions[name] = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        }
        return versions
    }()

    /// A post's photos: file, width, height and alt text (Chinese, English).
    private static func postPhotos(_ index: Int) -> [(String, Int, Int, String, String)] {
        switch index {
        case 0: return [("post-0-mountain.jpg", 1600, 1067, "晨雾在山峰间散开，峰顶被日出照亮。",
                          "Morning mist clearing between mountain peaks lit by the sunrise.")]
        case 1: return [("post-1-cat-sunlight.jpg", 1600, 1067, "一只橘猫蜷在沙发上，正好躺在窗外照进来的一块阳光里。",
                          "An orange cat curled up on the couch, right in a patch of sunlight from the window.")]
        case 2: return [("post-2-latte.jpg", 1600, 1065, "木桌上一杯拉了爱心的卡布奇诺。",
                          "A cappuccino with heart latte art on a wooden table."),
                         ("post-2-reading-corner.jpg", 1600, 2400, "咖啡店角落，书架、绿植和一张小桌。",
                          "A corner of the café with bookshelves, plants and a small table.")]
        default: return [("post-3-city-sunset.jpg", 1600, 1067, "傍晚的街道，夕阳从两栋楼之间的树后照过来。",
                           "An evening street, the sunset shining through a tree between two buildings.")]
        }
    }

    /// Posts spread over the last day, so times read as recent.
    private static func recentDate(minutesAgo: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
    }

    static func decodedAccount(_ index: Int) -> Account? {
        try? JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: account(index)))
    }

    private static func tagURL(_ name: String) -> String {
        "\(base)/tags/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)"
    }
    /// Accounts 4–7 only appear in Explore's directory and search in photos mode.
    private static let handles = ["alex", "luna", "sam", "mira", "nora", "theo", "ivy", "kai"]

    /// Showcase posts are numbered down from 900 (`status(0)` is "900").
    static func statusIndex(forID id: String) -> Int? {
        guard let number = Int(id), (0...3).contains(900 - number) else { return nil }
        return 900 - number
    }

    /// A reply in a showcase thread, from the account at `index`.
    private static func reply(_ index: Int, to statusID: String) -> [String: Any] {
        let copy: [String]
        if usesPhotos {
            switch statusIndex(forID: statusID) ?? 0 {
            case 1: copy = chinese ? ["<p>这个睡姿我家猫也会，阳光在哪它就在哪。😂</p>", "<p>橘猫的快乐就是这么简单。☀️</p>"]
                : ["<p>Mine does the exact same sunbeam shuffle. 😂</p>", "<p>The simple joys of an orange cat. ☀️</p>"]
            case 2: copy = chinese ? ["<p>求店名！周末想去坐坐。</p>", "<p>书墙那张好有氛围，想在那里待一下午。📚</p>"]
                : ["<p>Name of the café, please! Going this weekend.</p>", "<p>That book wall. I could spend a whole afternoon there. 📚</p>"]
            case 3: copy = chinese ? ["<p>下班路上的小确幸。🌇</p>", "<p>这个光线太好了，像电影里的一帧。</p>"]
                : ["<p>Little joys on the way home. 🌇</p>", "<p>That light. It looks like a still from a film.</p>"]
            default: copy = chinese ? ["<p>太美了！下次带上我，我负责带热咖啡。☕️</p>", "<p>这张可以直接当壁纸了，是哪座山？</p>"]
                : ["<p>Stunning! Take me next time, I'll bring the hot coffee. ☕️</p>", "<p>This could be a wallpaper. Which mountain is it?</p>"]
            }
        } else {
            copy = chinese
                ? ["<p>楼下的猫在窗台上晒太阳，我看了好一会儿。☀️</p>", "<p>朋友寄来一张手写明信片，字有点歪，但很可爱。✉️</p>"]
                : ["<p>The neighbor's cat napping in a sunny window. I watched for a while. ☀️</p>",
                   "<p>A handwritten postcard from a friend, crooked letters and all. ✉️</p>"]
        }
        // The replier is never the post's author: shift by the post's index.
        let author = usesPhotos ? ((statusIndex(forID: statusID) ?? 0) + index) % 4 : index
        return ["id": "\(statusID)-\(index)", "content": copy[(index - 1) % copy.count], "account": account(author),
                "in_reply_to_id": statusID, "in_reply_to_account_id": account(0)["id"] ?? "",
                "created_at": usesPhotos ? recentDate(minutesAgo: 20 + index * 7) : "2026-09-30T02:00:00.000Z",
                "media_attachments": [] as [Any],
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": 6 - index, "reblogs_count": 0, "replies_count": 0,
                "language": chinese ? "zh" : "en"]
    }
    private static let emojiCharacters = Array("😀😄😁😆🥹😊🙂😉😍🥰😘😋😎🤩🥳🤗🤔😴😮😌🙃😇🫶💜🌿🌸🌻🌷🍀🌱🌈✨")

    private static var customEmojis: [CustomEmoji] {
        emojiCharacters.indices.map { index in
            let url = URL(string: "\(base)/emoji-\(index).png")!
            return CustomEmoji(shortcode: "garden_\(index + 1)", url: url, staticURL: url,
                visibleInPicker: true, category: index < 24 ? "Mood" : "Nature")
        }
    }
    private static let colors: [UIColor] = [
        UIColor(red: 0.47, green: 0.40, blue: 0.67, alpha: 1),
        UIColor(red: 0.33, green: 0.53, blue: 0.45, alpha: 1),
        UIColor(red: 0.78, green: 0.52, blue: 0.35, alpha: 1),
        UIColor(red: 0.42, green: 0.56, blue: 0.70, alpha: 1),
    ]

    @MainActor static func makeClient() -> MastodonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]
        return MastodonClient(baseURL: URL(string: base)!, session: URLSession(configuration: config),
            authInterceptor: AuthInterceptor(tokenProvider: AppStoreScreenshotToken()))
    }

    private static func avatarURL(_ index: Int) -> String {
        usesPhotos ? photoURL(avatarPhotos[index]) : "\(base)/avatar-\(index).png"
    }

    private static func headerURL(_ index: Int) -> String {
        usesPhotos ? photoURL(headerPhotos[index]) : "\(base)/landscape.png"
    }

    /// Each showcase account's bio (the profile's own note stays the original first one).
    private static func note(_ index: Int) -> String {
        guard usesPhotos, index > 0 else {
            return chinese ? "<p>记录小小的冒险和好的对话，也给自己留一点生长的空间。🌿</p>"
                : "<p>Small adventures, good conversations, and a little room to grow. 🌿</p>"
        }
        return chinese
            ? ["", "<p>两只猫的铲屎官，偶尔拍拍窗外。🐈</p>", "<p>咖啡、旧书店和周末的城市散步。☕️</p>", "<p>徒步、露营，在路上的人。⛰️</p>",
               "<p>城市夜跑、日落和一杯热拿铁。🌇</p>", "<p>海边长大，喜欢拍潮汐和渔船。🌊</p>",
               "<p>独立书店店员，每周推荐一本书。📚</p>", "<p>咖啡烘焙师，记录每一杯的味道。☕️</p>"][index]
            : ["", "<p>Staff to two cats. Occasionally photographs the window. 🐈</p>",
               "<p>Coffee, used bookshops and weekend city walks. ☕️</p>", "<p>Hiking, camping, usually somewhere on a trail. ⛰️</p>",
               "<p>Night runs, city sunsets, and a warm latte. 🌇</p>", "<p>Grew up by the sea. I photograph tides and fishing boats. 🌊</p>",
               "<p>Indie bookshop clerk. One book recommendation a week. 📚</p>", "<p>Coffee roaster, noting how every cup tastes. ☕️</p>"][index]
    }

    static func account(_ index: Int) -> [String: Any] {
        ["id": "store-\(index)", "username": handles[index], "acct": handles[index],
         "display_name": names[index],
         "note": note(index),
         "avatar": avatarURL(index), "avatar_static": avatarURL(index),
         "header": headerURL(index), "header_static": headerURL(index),
         "followers_count": usesPhotos ? [1284, 562, 318, 905, 742, 1168, 486, 823][index] : 128,
         "following_count": usesPhotos ? [216, 143, 98, 187, 203, 176, 132, 214][index] : 86,
         "statuses_count": usesPhotos ? [672, 1530, 241, 388, 529, 864, 317, 658][index] : 42,
         "url": "\(base)/@\(handles[index])", "show_media": true, "show_featured": true,
         "fields": chinese
             ? [["name": "关于", "value": "摄影与日常发现"], ["name": "社区", "value": "开放的社交网络"]]
             : [["name": "About", "value": "Photographs & everyday discoveries"],
                ["name": "Community", "value": "The open social web"]],
         "source": ["privacy": "public", "language": chinese ? "zh" : "en",
                    "note": chinese ? "记录小小的冒险和好的对话，也给自己留一点生长的空间。🌿"
                        : "Small adventures, good conversations, and a little room to grow. 🌿",
                    "fields": chinese
                        ? [["name": "关于", "value": "摄影与日常发现"], ["name": "社区", "value": "开放的社交网络"]]
                        : [["name": "About", "value": "Photographs & everyday discoveries"],
                           ["name": "Community", "value": "The open social web"]]]]
    }

    private static func status(_ index: Int) -> [String: Any] {
        if usesPhotos { return photoStatus(index) }
        let copy = chinese ? [
            "<p>雨后的早晨，空气很新鲜。🌿</p><p>今天有什么让你笑了一下？ <a href='\(tagURL("摄影"))'>#摄影</a></p>",
            "<p>给书、植物和咖啡收拾出了一个小角落。☕️</p><p>最好的发现，常常就在身边。</p>",
            "<p>开放的网络像一场对话，一条一条认真地写。</p><p>很高兴在这里遇到同频的人。✨</p>",
            "<p>傍晚散步时画的速写，给小事留一点空间。🎨</p>",
        ] : [
            "<p>A little fresh air, a slower morning. 🌿</p><p>What made you smile today? <a href='\(base)/tags/Photography'>#Photography</a></p>",
            "<p>Made a small corner for books, plants, and good coffee. ☕️</p><p>Sometimes the best discoveries are close to home.</p>",
            "<p>The open web feels like a conversation, one thoughtful post at a time.</p><p>Happy to find my people here. ✨</p>",
            "<p>A sketch from my evening walk. Making space for the little things. 🎨</p>",
        ]
        let media: [[String: Any]] = index == 0 ? [[
            "id": "store-photo", "type": "image", "url": "\(base)/landscape.png",
            "preview_url": "\(base)/landscape.png", "description": chinese ? "日出时分安静山野的原创插画。" : "An original illustration of a quiet landscape at sunrise.",
            "meta": ["original": ["width": 1200, "height": 720]],
        ]] : []
        var result: [String: Any] = ["id": String(900 - index), "content": copy[index], "account": account(index),
                "created_at": "2026-09-30T01:00:00.000Z", "media_attachments": media,
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": 24 - index * 4, "reblogs_count": 3, "replies_count": 5,
                "bookmarked": index == 1, "language": chinese ? "zh" : "en"]
        if ProcessInfo.processInfo.arguments.contains("LOCALIZATION_AUDIT") {
            if index == 1 { result["spoiler_text"] = "Offline content warning" }
            if index == 2 {
                result["filtered"] = ["First rule", "Second rule"].map { ["filter": ["title": $0]] }
            }
            if index == 3 {
                var quoted = status(0)
                quoted["poll"] = ["id": "offline-poll", "expired": false, "multiple": false,
                    "votes_count": 0, "options": [["title": "One"], ["title": "Two"]]]
                result["quote"] = ["state": "accepted", "quoted_status": quoted]
            }
        }
        return result
    }

    /// The showcase's everyday posts, each with its photos.
    private static func photoStatus(_ index: Int) -> [String: Any] {
        let copy = chinese ? [
            "<p>周末进山看日出，五点出发，雾散开的那一刻觉得早起都值了。⛰️</p><p><a href='\(tagURL("摄影"))'>#摄影</a></p>",
            "<p>家里这位今天的全部工作：跟着阳光挪窝。☀️🐈</p>",
            "<p>楼下新开了家咖啡店，拉花是爱心，角落里还有一整面书墙。周末有地方待了。☕️📚</p>",
            "<p>下班路上，夕阳刚好卡在两栋楼中间，停下来看了一会儿。🌇</p>",
        ] : [
            "<p>Up at five for a mountain sunrise. The moment the mist cleared made the early alarm worth it. ⛰️</p><p><a href='\(tagURL("Photography"))'>#Photography</a></p>",
            "<p>Today's full job description for this one: follow the sunbeam around the couch. ☀️🐈</p>",
            "<p>A new café opened downstairs. Heart latte art and a whole wall of books in the corner. Weekend plans: sorted. ☕️📚</p>",
            "<p>On the walk home the sunset slipped right between two buildings. Stopped for a minute to watch. 🌇</p>",
        ]
        let media: [[String: Any]] = postPhotos(index).enumerated().map { offset, photo in
            ["id": "store-photo-\(index)-\(offset)", "type": "image", "url": photoURL(photo.0),
             "preview_url": photoURL(photo.0), "description": chinese ? photo.3 : photo.4,
             "meta": ["original": ["width": photo.1, "height": photo.2]]]
        }
        return ["id": String(900 - index), "content": copy[index], "account": account(index),
                "created_at": recentDate(minutesAgo: [38, 95, 180, 310][index]), "media_attachments": media,
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": [48, 126, 31, 22][index], "reblogs_count": [12, 34, 5, 3][index],
                "replies_count": [6, 18, 4, 2][index],
                "bookmarked": index == 1, "language": chinese ? "zh" : "en"]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let payload: Any
        var code = 200
        if path.hasSuffix("/custom_emojis") {
            payload = Self.customEmojis.map {
                ["shortcode": $0.shortcode, "url": $0.url.absoluteString,
                 "static_url": $0.staticURL.absoluteString, "visible_in_picker": true,
                 "category": $0.category ?? "Mood"] as [String: Any]
            }
        } else if path.hasSuffix("/verify_credentials") || path.hasSuffix("/accounts/store-0") {
            payload = Self.account(0)
        } else if path.contains("/instance") {
            code = 404; payload = ["error": "Offline screenshot fixture"]
        } else if path.hasSuffix("/profile") {
            let source = (Self.account(0)["source"] as? [String: Any]) ?? [:]
            payload = ["id": "store-0", "display_name": Self.names[0],
                       "note": source["note"] ?? "", "fields": source["fields"] ?? [],
                       "show_media": true, "show_featured": true]
        } else if path.hasSuffix("/unread_count") {
            payload = ["count": 0]
        } else if path.hasSuffix("/notifications") {
            let types = query.filter { $0.name == "types[]" }.compactMap(\.value)
            let items: [[String: Any]]
            if Self.usesPhotos {
                // Replies, likes and boosts on the sunrise post, and a new follower.
                let rows: [(String, Int, [String: Any]?, Int)] = [
                    ("mention", 1, Self.reply(1, to: "900"), 12), ("favourite", 2, Self.status(0), 25),
                    ("reblog", 3, Self.status(0), 41), ("mention", 2, Self.reply(2, to: "900"), 58),
                    ("follow", 3, nil, 140), ("favourite", 1, Self.status(0), 205),
                ]
                items = rows.enumerated().map { offset, row in
                    var item: [String: Any] = ["id": String(600 - offset), "type": row.0,
                        "created_at": Self.recentDate(minutesAgo: row.3), "account": Self.account(row.1)]
                    if let status = row.2 { item["status"] = status }
                    return item
                }
            } else {
                items = (1...3).map { index -> [String: Any] in
                    ["id": String(600 - index), "type": ["mention", "favourite", "follow"][index - 1],
                     "created_at": "2026-09-30T01:00:00.000Z", "account": Self.account(index),
                     "status": Self.status(index)]
                }
            }
            payload = items.filter { types.isEmpty || types.contains($0["type"] as? String ?? "") }
        } else if path.hasSuffix("/trends/tags") || path.hasSuffix("/featured_tags") || path.hasSuffix("/followed_tags") {
            payload = Self.tagNames.map {
                ["id": "tag-\($0)", "name": $0, "url": Self.tagURL($0),
                 "statuses_count": "12", "history": [["day": "1790726400", "uses": "128", "accounts": "42"]]] as [String: Any]
            }
        } else if path.hasSuffix("/directory") {
            payload = (1...(Self.usesPhotos ? 7 : 3)).map { Self.account($0) }
        } else if path.hasSuffix("/relationships") {
            payload = []
        } else if path.hasSuffix("/context") {
            let statusID = url.deletingLastPathComponent().lastPathComponent
            payload = ["ancestors": [], "descendants": [1, 2].map { Self.reply($0, to: statusID) }]
        } else if path.hasSuffix("/search") {
            payload = ["accounts": (1...(Self.usesPhotos ? 7 : 3)).map { Self.account($0) },
                       "statuses": (0...3).map { Self.status($0) }, "hashtags": []]
        } else if path.hasSuffix("/markers") || path.hasSuffix("/preferences") {
            payload = [:]
        } else if path.contains("/timelines/") || path.hasSuffix("/statuses") || path.hasSuffix("/bookmarks") {
            payload = query.contains(where: { $0.name == "max_id" || $0.name == "since_id" || ($0.name == "pinned" && $0.value == "true") })
                ? [] : (0...3).map { Self.status($0) }
        } else if path.contains("/statuses/") {
            payload = Self.status(Self.statusIndex(forID: url.lastPathComponent) ?? 0)
        } else {
            payload = []
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    @MainActor static func cacheIllustrations() async {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        for (index, character) in emojiCharacters.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { _ in
                (String(character) as NSString).draw(at: CGPoint(x: 10, y: 3), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 130),
                ])
            }
            await withCheckedContinuation { continuation in
                SDImageCache.shared.store(image, imageData: image.pngData(),
                    forKey: customEmojis[index].url.absoluteString, toDisk: true) { continuation.resume() }
            }
        }
        _ = EmojiCatalogDiskCache.save(EmojiCatalogCacheRecord(fetchedAt: Date(), emojis: customEmojis),
            domain: URL(string: base)!.host!)
        for index in 0...4 {
            let size = index == 4 ? CGSize(width: 1200, height: 720) : CGSize(width: 180, height: 180)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(red: 0.94, green: 0.91, blue: 0.86, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                if index == 4 {
                    UIColor(red: 0.88, green: 0.67, blue: 0.43, alpha: 1).setFill()
                    UIBezierPath(ovalIn: CGRect(x: 820, y: 90, width: 150, height: 150)).fill()
                    for layer in 0..<3 {
                        colors[layer].withAlphaComponent(0.8).setFill()
                        let path = UIBezierPath()
                        let y = CGFloat(320 + layer * 110)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addCurve(to: CGPoint(x: 1200, y: y + 60),
                            controlPoint1: CGPoint(x: 350, y: y - 220), controlPoint2: CGPoint(x: 850, y: y + 160))
                        path.addLine(to: CGPoint(x: 1200, y: 720)); path.addLine(to: CGPoint(x: 0, y: 720))
                        path.close(); path.fill()
                    }
                } else {
                    colors[index].setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    let symbol = UIImage(systemName: ["leaf.fill", "moon.stars.fill", "sun.max.fill", "sparkles"][index],
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 74))?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    symbol?.draw(in: CGRect(x: 46, y: 46, width: 88, height: 88))
                }
            }
            let key = index == 4 ? "\(base)/landscape.png" : "\(base)/avatar-\(index).png"
            await withCheckedContinuation { continuation in
                SDImageCache.shared.store(image, imageData: image.pngData(), forKey: key, toDisk: true) {
                    continuation.resume()
                }
            }
        }
        await cachePhotos()
    }

    /// Puts the showcase photos in the image cache under their fixture URLs (nothing is fetched).
    @MainActor private static func cachePhotos() async {
        guard usesPhotos, let directory = photosDirectory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where name.hasSuffix(".jpg") {
            guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path),
                let image = UIImage(data: data)
            else { continue }
            await withCheckedContinuation { continuation in
                SDImageCache.shared.store(image, imageData: data, forKey: photoURL(name), toDisk: true) {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
