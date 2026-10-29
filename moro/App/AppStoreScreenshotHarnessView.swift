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
    /// The original screenshot harness keeps its English fixtures; the showcase follows the app.
    private static var language: AppStoreDemoLanguage {
        showcase ? AppStoreDemoLanguage(Locale.preferredLanguages.first ?? "en") : .en
    }
    private static var copy: AppStoreDemoCopy { language.copy }

    private static var names: [String] { copy.names }
    private static var tagNames: [String] {
        usesPhotos ? copy.photoTags : copy.illustratedTags
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

    /// A post's photos: file, width, height and localized alt text.
    private static func postPhotos(_ index: Int) -> [(String, Int, Int, String)] {
        switch index {
        case 0: return [("post-0-mountain.jpg", 1600, 1067, copy.photoDescriptions[0])]
        case 1: return [("post-1-cat-sunlight.jpg", 1600, 1067, copy.photoDescriptions[1])]
        case 2: return [("post-2-latte.jpg", 1600, 1065, copy.photoDescriptions[2]),
                         ("post-2-reading-corner.jpg", 1600, 2400, copy.photoDescriptions[3])]
        default: return [("post-3-city-sunset.jpg", 1600, 1067, copy.photoDescriptions[4])]
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
        let replies = usesPhotos ? copy.photoReplies[statusIndex(forID: statusID) ?? 0] : copy.illustratedReplies
        // The replier is never the post's author: shift by the post's index.
        let author = usesPhotos ? ((statusIndex(forID: statusID) ?? 0) + index) % 4 : index
        return ["id": "\(statusID)-\(index)", "content": "<p>\(replies[(index - 1) % replies.count])</p>", "account": account(author),
                "in_reply_to_id": statusID, "in_reply_to_account_id": account(0)["id"] ?? "",
                "created_at": usesPhotos ? recentDate(minutesAgo: 20 + index * 7) : "2026-09-30T02:00:00.000Z",
                "media_attachments": [] as [Any],
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": 6 - index, "reblogs_count": 0, "replies_count": 0,
                "language": language.rawValue]
    }
    private static let emojiCharacters = Array("😀😄😁😆🥹😊🙂😉😍🥰😘😋😎🤩🥳🤗🤔😴😮😌🙃😇🫶💜🌿🌸🌻🌷🍀🌱🌈✨")

    private static var customEmojis: [CustomEmoji] {
        emojiCharacters.indices.map { index in
            let url = URL(string: "\(base)/emoji-\(index).png")!
            return CustomEmoji(shortcode: "garden_\(index + 1)", url: url, staticURL: url,
                visibleInPicker: true, category: copy.emojiCategories[index < 24 ? 0 : 1])
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
        "<p>\(copy.notes[usesPhotos ? index : 0])</p>"
    }

    private static var profileFields: [[String: String]] {
        copy.profileFields.map { ["name": $0[0], "value": $0[1]] }
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
         "fields": profileFields,
         "source": ["privacy": "public", "language": language.rawValue,
                    "note": copy.notes[0], "fields": profileFields]]
    }

    private static func status(_ index: Int) -> [String: Any] {
        if usesPhotos { return photoStatus(index) }
        let content = copy.illustratedPosts[index].enumerated().map { offset, paragraph in
            let tag = index == 0 && offset == 1 ? " \(hashtag(copy.illustratedTags[0]))" : ""
            return "<p>\(paragraph)\(tag)</p>"
        }.joined()
        let media: [[String: Any]] = index == 0 ? [[
            "id": "store-photo", "type": "image", "url": "\(base)/landscape.png",
            "preview_url": "\(base)/landscape.png", "description": copy.illustrationDescription,
            "meta": ["original": ["width": 1200, "height": 720]],
        ]] : []
        var result: [String: Any] = ["id": String(900 - index), "content": content, "account": account(index),
                "created_at": "2026-09-30T01:00:00.000Z", "media_attachments": media,
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": 24 - index * 4, "reblogs_count": 3, "replies_count": 5,
                "bookmarked": index == 1, "language": language.rawValue]
        if ProcessInfo.processInfo.arguments.contains("LOCALIZATION_AUDIT") {
            if index == 1 { result["spoiler_text"] = copy.contentWarning }
            if index == 2 {
                result["filtered"] = copy.filterNames.map { ["filter": ["title": $0]] }
            }
            if index == 3 {
                var quoted = status(0)
                quoted["poll"] = ["id": "offline-poll", "expired": false, "multiple": false,
                    "votes_count": 0, "options": copy.pollOptions.map { ["title": $0] }]
                result["quote"] = ["state": "accepted", "quoted_status": quoted]
            }
        }
        return result
    }

    /// The showcase's everyday posts, each with its photos.
    private static func photoStatus(_ index: Int) -> [String: Any] {
        let content = "<p>\(copy.photoPosts[index])</p>"
            + (index == 0 ? "<p>\(hashtag(copy.photoTags[0]))</p>" : "")
        let media: [[String: Any]] = postPhotos(index).enumerated().map { offset, photo in
            ["id": "store-photo-\(index)-\(offset)", "type": "image", "url": photoURL(photo.0),
             "preview_url": photoURL(photo.0), "description": photo.3,
             "meta": ["original": ["width": photo.1, "height": photo.2]]]
        }
        return ["id": String(900 - index), "content": content, "account": account(index),
                "created_at": recentDate(minutesAgo: [38, 95, 180, 310][index]), "media_attachments": media,
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": [48, 126, 31, 22][index], "reblogs_count": [12, 34, 5, 3][index],
                "replies_count": [6, 18, 4, 2][index],
                "bookmarked": index == 1, "language": language.rawValue]
    }

    private static func hashtag(_ name: String) -> String {
        "<a href='\(tagURL(name))'>#\(name)</a>"
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
                 "category": $0.category ?? Self.copy.emojiCategories[0]] as [String: Any]
            }
        } else if path.hasSuffix("/verify_credentials") || path.hasSuffix("/accounts/store-0") {
            payload = Self.account(0)
        } else if path.contains("/instance") {
            code = 404; payload = ["error": Self.copy.offlineError]
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

// MARK: - Localized showcase copy

private nonisolated enum AppStoreDemoLanguage: String, Sendable {
    case en, de, es, fr, it, ja
    case ptPT = "pt-PT"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    init(_ preferredLanguage: String) {
        let parts = preferredLanguage.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-")
        switch parts.first {
        case "zh":
            self = parts.contains("hant") || parts.contains("tw") || parts.contains("hk") ? .zhHant : .zhHans
        case "de": self = .de
        case "es": self = .es
        case "fr": self = .fr
        case "it": self = .it
        case "ja": self = .ja
        case "pt": self = .ptPT
        default: self = .en
        }
    }

    var copy: AppStoreDemoCopy {
        switch self {
        case .en: .english
        case .de: .german
        case .es: .spanish
        case .fr: .french
        case .it: .italian
        case .ja: .japanese
        case .ptPT: .portuguese
        case .zhHans: .simplifiedChinese
        case .zhHant: .traditionalChinese
        }
    }
}

/// Entries share the same order: accounts match `handles`, posts match IDs 900–897,
/// and each photo post has two replies. Text stays separate from HTML and fixture metadata.
private nonisolated struct AppStoreDemoCopy: Sendable {
    let names: [String]
    let photoTags: [String]
    let illustratedTags: [String]
    let notes: [String]
    let profileFields: [[String]]
    let photoPosts: [String]
    let photoReplies: [[String]]
    let photoDescriptions: [String]
    let illustratedPosts: [[String]]
    let illustratedReplies: [String]
    let illustrationDescription: String
    let emojiCategories: [String]
    let contentWarning: String
    let filterNames: [String]
    let pollOptions: [String]
    let offlineError: String

    static let english = Self(
        names: ["Alex Rivers", "Luna Park", "Sam Chen", "Mira Stone", "Nora Hale", "Theo Grant", "Ivy Lane", "Kai Morgan"],
        photoTags: ["Photography", "Cats", "Coffee", "Books"],
        illustratedTags: ["Photography", "Art", "Nature", "Books"],
        notes: [
            "Small adventures, good conversations, and a little room to grow. 🌿",
            "Staff to two cats. Occasionally photographs the window. 🐈",
            "Coffee, used bookshops and weekend city walks. ☕️",
            "Hiking, camping, usually somewhere on a trail. ⛰️",
            "Night runs, city sunsets, and a warm latte. 🌇",
            "Grew up by the sea. I photograph tides and fishing boats. 🌊",
            "Indie bookshop clerk. One book recommendation a week. 📚",
            "Coffee roaster, noting how every cup tastes. ☕️",
        ],
        profileFields: [["About", "Photographs & everyday discoveries"], ["Community", "The open social web"]],
        photoPosts: [
            "Up at five for a mountain sunrise. The moment the mist cleared made the early alarm worth it. ⛰️",
            "Today's full job description for this one: follow the sunbeam around the couch. ☀️🐈",
            "A new café opened downstairs. Heart latte art and a whole wall of books in the corner. Weekend plans: sorted. ☕️📚",
            "On the walk home the sunset slipped right between two buildings. Stopped for a minute to watch. 🌇",
        ],
        photoReplies: [
            ["Stunning! Take me next time, I'll bring the hot coffee. ☕️", "This could be a wallpaper. Which mountain is it?"],
            ["Mine does the exact same sunbeam shuffle. 😂", "The simple joys of an orange cat. ☀️"],
            ["Name of the café, please! Going this weekend.", "That book wall. I could spend a whole afternoon there. 📚"],
            ["Little joys on the way home. 🌇", "That light. It looks like a still from a film."],
        ],
        photoDescriptions: [
            "Morning mist clearing between mountain peaks lit by the sunrise.",
            "An orange cat curled up on the couch, right in a patch of sunlight from the window.",
            "A cappuccino with heart latte art on a wooden table.",
            "A corner of the café with bookshelves, plants and a small table.",
            "An evening street, the sunset shining through a tree between two buildings.",
        ],
        illustratedPosts: [
            ["A little fresh air, a slower morning. 🌿", "What made you smile today?"],
            ["Made a small corner for books, plants, and good coffee. ☕️", "Sometimes the best discoveries are close to home."],
            ["The open web feels like a conversation, one thoughtful post at a time.", "Happy to find my people here. ✨"],
            ["A sketch from my evening walk. Making space for the little things. 🎨"],
        ],
        illustratedReplies: ["The neighbor's cat napping in a sunny window. I watched for a while. ☀️",
                             "A handwritten postcard from a friend, crooked letters and all. ✉️"],
        illustrationDescription: "An original illustration of a quiet landscape at sunrise.",
        emojiCategories: ["Mood", "Nature"],
        contentWarning: "Offline content warning",
        filterNames: ["First rule", "Second rule"],
        pollOptions: ["One", "Two"],
        offlineError: "Offline screenshot fixture"
    )

    static let simplifiedChinese = Self(
        names: ["林知夏", "陈屿", "苏晚", "周默", "许诺", "唐一舟", "白芷", "程野"],
        photoTags: ["摄影", "猫", "咖啡", "读书"],
        illustratedTags: ["摄影", "插画", "自然", "读书"],
        notes: [
            "记录小小的冒险和好的对话，也给自己留一点生长的空间。🌿",
            "两只猫的铲屎官，偶尔拍拍窗外。🐈",
            "咖啡、旧书店和周末的城市散步。☕️",
            "徒步、露营，在路上的人。⛰️",
            "城市夜跑、日落和一杯热拿铁。🌇",
            "海边长大，喜欢拍潮汐和渔船。🌊",
            "独立书店店员，每周推荐一本书。📚",
            "咖啡烘焙师，记录每一杯的味道。☕️",
        ],
        profileFields: [["关于", "摄影与日常发现"], ["社区", "开放的社交网络"]],
        photoPosts: [
            "周末进山看日出，五点出发，雾散开的那一刻觉得早起都值了。⛰️",
            "家里这位今天的全部工作：跟着阳光挪窝。☀️🐈",
            "楼下新开了家咖啡店，拉花是爱心，角落里还有一整面书墙。周末有地方待了。☕️📚",
            "下班路上，夕阳刚好卡在两栋楼中间，停下来看了一会儿。🌇",
        ],
        photoReplies: [
            ["太美了！下次带上我，我负责带热咖啡。☕️", "这张可以直接当壁纸了，是哪座山？"],
            ["这个睡姿我家猫也会，阳光在哪它就在哪。😂", "橘猫的快乐就是这么简单。☀️"],
            ["求店名！周末想去坐坐。", "书墙那张好有氛围，想在那里待一下午。📚"],
            ["下班路上的小确幸。🌇", "这个光线太好了，像电影里的一帧。"],
        ],
        photoDescriptions: [
            "晨雾在山峰间散开，峰顶被日出照亮。",
            "一只橘猫蜷在沙发上，正好躺在窗外照进来的一块阳光里。",
            "木桌上一杯拉了爱心的卡布奇诺。",
            "咖啡店角落，书架、绿植和一张小桌。",
            "傍晚的街道，夕阳从两栋楼之间的树后照过来。",
        ],
        illustratedPosts: [
            ["雨后的早晨，空气很新鲜。🌿", "今天有什么让你笑了一下？"],
            ["给书、植物和咖啡收拾出了一个小角落。☕️", "最好的发现，常常就在身边。"],
            ["开放的网络像一场对话，一条一条认真地写。", "很高兴在这里遇到同频的人。✨"],
            ["傍晚散步时画的速写，给小事留一点空间。🎨"],
        ],
        illustratedReplies: ["楼下的猫在窗台上晒太阳，我看了好一会儿。☀️", "朋友寄来一张手写明信片，字有点歪，但很可爱。✉️"],
        illustrationDescription: "日出时分安静山野的原创插画。",
        emojiCategories: ["心情", "自然"],
        contentWarning: "离线内容警告",
        filterNames: ["第一条规则", "第二条规则"],
        pollOptions: ["一", "二"],
        offlineError: "离线截图示例数据"
    )

    static let traditionalChinese = Self(
        names: ["林知夏", "陳嶼", "蘇晚", "周默", "許諾", "唐一舟", "白芷", "程野"],
        photoTags: ["攝影", "貓", "咖啡", "閱讀"],
        illustratedTags: ["攝影", "插畫", "自然", "閱讀"],
        notes: [
            "記錄小小的冒險和美好的對話，也給自己留一點成長的空間。🌿",
            "兩隻貓的貓奴，偶爾拍拍窗外。🐈",
            "咖啡、二手書店和週末的城市散步。☕️",
            "健行、露營，總是在路上。⛰️",
            "城市夜跑、日落和一杯熱拿鐵。🌇",
            "在海邊長大，喜歡拍潮汐和漁船。🌊",
            "獨立書店店員，每週推薦一本書。📚",
            "咖啡烘豆師，記錄每一杯的風味。☕️",
        ],
        profileFields: [["關於我", "攝影與日常發現"], ["社群", "開放的社交網路"]],
        photoPosts: [
            "週末上山看日出，五點出發，霧散開的那一刻覺得早起都值得了。⛰️",
            "家裡這位今天的全部工作：跟著陽光換地方睡。☀️🐈",
            "樓下新開了一家咖啡店，拉花是愛心，角落還有一整面書牆。週末有地方待了。☕️📚",
            "下班路上，夕陽剛好落在兩棟樓之間，停下來看了一會兒。🌇",
        ],
        photoReplies: [
            ["太美了！下次帶上我，我負責帶熱咖啡。☕️", "這張可以直接當桌布了，是哪座山？"],
            ["我家的貓也這樣睡，陽光在哪牠就在哪。😂", "橘貓的快樂就是這麼簡單。☀️"],
            ["求店名！週末想去坐坐。", "書牆那張好有氣氛，想在那裡待一下午。📚"],
            ["下班路上的小確幸。🌇", "這個光線太美了，像電影裡的一幕。"],
        ],
        photoDescriptions: [
            "晨霧在山峰間散開，峰頂被日出照亮。",
            "一隻橘貓蜷在沙發上，正好躺在窗外照進來的一片陽光裡。",
            "木桌上放著一杯有愛心拉花的卡布奇諾。",
            "咖啡店的角落，有書架、綠色植物和一張小桌子。",
            "傍晚的街道，夕陽從兩棟樓之間的樹後照過來。",
        ],
        illustratedPosts: [
            ["雨後的早晨，空氣很清新。🌿", "今天有什麼讓你笑了一下？"],
            ["整理出一個放書、植物和咖啡的小角落。☕️", "最好的發現，常常就在身邊。"],
            ["開放的網路像一場對話，一則一則用心地寫。", "很開心在這裡遇到頻率相近的人。✨"],
            ["傍晚散步時畫的速寫，給小事留一點空間。🎨"],
        ],
        illustratedReplies: ["樓下的貓在窗臺上曬太陽，我看了好一會兒。☀️", "朋友寄來一張手寫明信片，字有點歪，但很可愛。✉️"],
        illustrationDescription: "日出時分寧靜山野的原創插畫。",
        emojiCategories: ["心情", "自然"],
        contentWarning: "離線內容警告",
        filterNames: ["第一條規則", "第二條規則"],
        pollOptions: ["一", "二"],
        offlineError: "離線截圖範例資料"
    )

    static let german = Self(
        names: ["Alexander Weber", "Lena Fischer", "Samuel Becker", "Mira Hoffmann", "Nora Wagner", "Theo Schneider", "Johanna Bauer", "Kai Richter"],
        photoTags: ["Fotografie", "Katzen", "Kaffee", "Bücher"],
        illustratedTags: ["Fotografie", "Illustration", "Natur", "Bücher"],
        notes: [
            "Kleine Abenteuer, gute Gespräche und ein bisschen Raum zum Wachsen. 🌿",
            "Im Dienst von zwei Katzen. Fotografiere ab und zu den Blick aus dem Fenster. 🐈",
            "Kaffee, Antiquariate und Stadtspaziergänge am Wochenende. ☕️",
            "Wandern, zelten und meistens irgendwo unterwegs. ⛰️",
            "Abendläufe, Sonnenuntergänge in der Stadt und ein warmer Latte. 🌇",
            "Am Meer aufgewachsen. Ich fotografiere die Gezeiten und Fischerboote. 🌊",
            "Arbeite in einer unabhängigen Buchhandlung. Jede Woche ein Buchtipp. 📚",
            "Kaffeeröster. Halte den Geschmack jeder Tasse fest. ☕️",
        ],
        profileFields: [["Über mich", "Fotografie & Entdeckungen im Alltag"], ["Community", "Das offene soziale Netz"]],
        photoPosts: [
            "Am Wochenende um fünf los, zum Sonnenaufgang in die Berge. Als sich der Nebel lichtete, hatte sich das frühe Aufstehen gelohnt. ⛰️",
            "Die heutige Aufgabe dieser Katze: dem Sonnenfleck über das Sofa folgen. ☀️🐈",
            "Unten hat ein neues Café eröffnet. Herzen im Milchschaum und eine ganze Bücherwand in der Ecke. Das Wochenende ist gerettet. ☕️📚",
            "Auf dem Heimweg stand die Abendsonne genau zwischen zwei Häusern. Bin kurz stehen geblieben und habe zugeschaut. 🌇",
        ],
        photoReplies: [
            ["Wunderschön! Nimm mich nächstes Mal mit, ich bringe heißen Kaffee mit. ☕️", "Das könnte direkt mein Hintergrundbild werden. Welcher Berg ist das?"],
            ["Meine Katze wandert genauso der Sonne hinterher. 😂", "So einfach ist das Glück einer orangefarbenen Katze. ☀️"],
            ["Wie heißt das Café? Da will ich am Wochenende hin!", "Diese Bücherwand! Da könnte ich einen ganzen Nachmittag verbringen. 📚"],
            ["Die kleinen Freuden auf dem Heimweg. 🌇", "Dieses Licht! Sieht aus wie eine Filmszene."],
        ],
        photoDescriptions: [
            "Morgennebel lichtet sich zwischen Berggipfeln im Licht der aufgehenden Sonne.",
            "Eine orangefarbene Katze liegt zusammengerollt auf dem Sofa, genau im Sonnenfleck vom Fenster.",
            "Ein Cappuccino mit einem Herz im Milchschaum auf einem Holztisch.",
            "Eine Ecke des Cafés mit Bücherregalen, Pflanzen und einem kleinen Tisch.",
            "Eine Straße am Abend. Zwischen zwei Häusern scheint die untergehende Sonne durch einen Baum.",
        ],
        illustratedPosts: [
            ["Ein frischer Morgen nach dem Regen. 🌿", "Was hat dich heute zum Lächeln gebracht?"],
            ["Eine kleine Ecke für Bücher, Pflanzen und guten Kaffee eingerichtet. ☕️", "Die schönsten Entdeckungen liegen oft ganz nah."],
            ["Das offene Netz fühlt sich wie ein Gespräch an, mit jedem aufmerksamen Beitrag.", "Schön, hier Gleichgesinnte zu finden. ✨"],
            ["Eine Skizze vom Abendspaziergang. Ein bisschen Platz für die kleinen Dinge. 🎨"],
        ],
        illustratedReplies: ["Die Nachbarskatze schläft am sonnigen Fenster. Habe eine Weile zugeschaut. ☀️",
                             "Eine handgeschriebene Postkarte von einem Freund. Die Buchstaben sind etwas schief, aber liebenswert. ✉️"],
        illustrationDescription: "Eine eigens gezeichnete Illustration einer stillen Landschaft bei Sonnenaufgang.",
        emojiCategories: ["Stimmung", "Natur"],
        contentWarning: "Offline-Inhaltswarnung",
        filterNames: ["Erste Regel", "Zweite Regel"],
        pollOptions: ["Eins", "Zwei"],
        offlineError: "Offline-Beispieldaten für Screenshots"
    )

    static let spanish = Self(
        names: ["Alejandro Ríos", "Lucía Martín", "Samuel García", "Marta Ruiz", "Nora López", "Teo Navarro", "Irene Vega", "Carlos Romero"],
        photoTags: ["Fotografía", "Gatos", "Café", "Lectura"],
        illustratedTags: ["Fotografía", "Ilustración", "Naturaleza", "Lectura"],
        notes: [
            "Pequeñas aventuras, buenas conversaciones y un poco de espacio para crecer. 🌿",
            "Al servicio de dos gatos. De vez en cuando fotografío lo que veo por la ventana. 🐈",
            "Café, librerías de segunda mano y paseos por la ciudad los fines de semana. ☕️",
            "Senderismo, acampadas y casi siempre en algún camino. ⛰️",
            "Correr de noche, atardeceres en la ciudad y un café con leche calentito. 🌇",
            "Crecí junto al mar. Me gusta fotografiar las mareas y los barcos de pesca. 🌊",
            "Trabajo en una librería independiente. Recomiendo un libro cada semana. 📚",
            "Tostador de café. Anoto el sabor de cada taza. ☕️",
        ],
        profileFields: [["Sobre mí", "Fotografía y descubrimientos cotidianos"], ["Comunidad", "La web social abierta"]],
        photoPosts: [
            "El fin de semana salí a las cinco para ver amanecer en la montaña. Cuando se despejó la niebla, el madrugón mereció la pena. ⛰️",
            "Todo el trabajo de este gato hoy: seguir el rayito de sol por el sofá. ☀️🐈",
            "Han abierto una cafetería abajo. Corazones en la espuma y toda una pared de libros en un rincón. Ya tengo plan para el fin de semana. ☕️📚",
            "De camino a casa, el sol del atardecer se colaba justo entre dos edificios. Me paré un momento a mirarlo. 🌇",
        ],
        photoReplies: [
            ["¡Qué maravilla! Llévame la próxima vez, yo pongo el café caliente. ☕️", "Esta foto podría ser un fondo de pantalla. ¿Qué montaña es?"],
            ["Mi gato hace exactamente lo mismo persiguiendo el sol. 😂", "La felicidad de un gato naranja es así de sencilla. ☀️"],
            ["¡Nombre de la cafetería, por favor! Quiero ir este fin de semana.", "Esa pared de libros… Me quedaría allí toda la tarde. 📚"],
            ["Las pequeñas alegrías de volver a casa. 🌇", "¡Qué luz! Parece un fotograma de una película."],
        ],
        photoDescriptions: [
            "La niebla de la mañana se disipa entre las cumbres iluminadas por el amanecer.",
            "Un gato naranja acurrucado en el sofá, justo en un rayo de sol que entra por la ventana.",
            "Un capuchino con un corazón dibujado en la espuma sobre una mesa de madera.",
            "Un rincón de la cafetería con estanterías, plantas y una mesa pequeña.",
            "Una calle al atardecer, con el sol filtrándose por un árbol entre dos edificios.",
        ],
        illustratedPosts: [
            ["Una mañana de aire fresco después de la lluvia. 🌿", "¿Qué te ha hecho sonreír hoy?"],
            ["He preparado un rinconcito para libros, plantas y buen café. ☕️", "A veces, los mejores descubrimientos están muy cerca."],
            ["La web abierta es como una conversación, con cada publicación escrita con cariño.", "Qué alegría encontrar aquí a gente afín. ✨"],
            ["Un boceto del paseo de esta tarde. Dejando sitio a las pequeñas cosas. 🎨"],
        ],
        illustratedReplies: ["El gato del vecino dormía al sol en la ventana. Me quedé mirándolo un buen rato. ☀️",
                             "Una postal escrita a mano por un amigo, con letras un poco torcidas, pero con mucho encanto. ✉️"],
        illustrationDescription: "Una ilustración original de un paisaje tranquilo al amanecer.",
        emojiCategories: ["Ánimo", "Naturaleza"],
        contentWarning: "Aviso de contenido sin conexión",
        filterNames: ["Primera regla", "Segunda regla"],
        pollOptions: ["Uno", "Dos"],
        offlineError: "Datos de ejemplo sin conexión para capturas"
    )

    static let french = Self(
        names: ["Alexandre Rivière", "Léa Martin", "Samuel Laurent", "Camille Moreau", "Nora Dubois", "Théo Garnier", "Inès Lefèvre", "Lucas Bernard"],
        photoTags: ["Photographie", "Chats", "Café", "Lecture"],
        illustratedTags: ["Photographie", "Illustration", "Nature", "Lecture"],
        notes: [
            "De petites aventures, de belles conversations et un peu de place pour grandir. 🌿",
            "Au service de deux chats. Je photographie parfois la vue par la fenêtre. 🐈",
            "Café, bouquineries et balades en ville le week-end. ☕️",
            "Rando, camping, souvent quelque part sur un sentier. ⛰️",
            "Footing nocturne, couchers de soleil en ville et latte bien chaud. 🌇",
            "J’ai grandi au bord de la mer. Je photographie les marées et les bateaux de pêche. 🌊",
            "Libraire indépendante. Un livre à vous conseiller chaque semaine. 📚",
            "Torréfacteur, je note les saveurs de chaque tasse. ☕️",
        ],
        profileFields: [["À propos", "Photos et découvertes du quotidien"], ["Communauté", "Le web social ouvert"]],
        photoPosts: [
            "Départ à cinq heures ce week-end pour voir le soleil se lever en montagne. Quand la brume s’est dissipée, le réveil matinal en valait la peine. ⛰️",
            "Tout le programme de ce chat aujourd’hui : suivre le rayon de soleil sur le canapé. ☀️🐈",
            "Un nouveau café a ouvert en bas. Des cœurs dans la mousse et tout un mur de livres dans un coin. Le programme du week-end est trouvé. ☕️📚",
            "En rentrant, le soleil couchant s’est glissé pile entre deux immeubles. J’ai pris une minute pour le regarder. 🌇",
        ],
        photoReplies: [
            ["Magnifique ! Emmène-moi la prochaine fois, j’apporte le café chaud. ☕️", "Cette photo ferait un beau fond d’écran. C’est quelle montagne ?"],
            ["Mon chat fait exactement pareil pour suivre le soleil. 😂", "Les petits bonheurs d’un chat roux. ☀️"],
            ["Le nom du café, s’il te plaît ! J’aimerais y aller ce week-end.", "Ce mur de livres… J’y passerais bien tout l’après-midi. 📚"],
            ["Les petits bonheurs sur le chemin du retour. 🌇", "Cette lumière ! On dirait une image de cinéma."],
        ],
        photoDescriptions: [
            "La brume matinale se dissipe entre les sommets éclairés par le soleil levant.",
            "Un chat roux roulé en boule sur le canapé, dans un rayon de soleil venant de la fenêtre.",
            "Un cappuccino avec un cœur dessiné dans la mousse, sur une table en bois.",
            "Un coin du café avec des étagères de livres, des plantes et une petite table.",
            "Une rue en fin de journée, le soleil couchant filtrant à travers un arbre entre deux immeubles.",
        ],
        illustratedPosts: [
            ["Un matin tout frais après la pluie. 🌿", "Qu’est-ce qui vous a fait sourire aujourd’hui ?"],
            ["Un petit coin aménagé pour les livres, les plantes et le bon café. ☕️", "Les plus belles découvertes sont parfois tout près de chez soi."],
            ["Le web ouvert ressemble à une conversation, un message attentionné à la fois.", "Quel plaisir de trouver des gens qui me ressemblent ici. ✨"],
            ["Un croquis de ma balade du soir. Faire une place aux petites choses. 🎨"],
        ],
        illustratedReplies: ["Le chat du voisin faisait la sieste au soleil sur le rebord de la fenêtre. Je l’ai regardé un moment. ☀️",
                             "Une carte postale écrite à la main par un ami. Les lettres sont un peu de travers, mais c’est adorable. ✉️"],
        illustrationDescription: "Une illustration originale d’un paysage paisible au lever du soleil.",
        emojiCategories: ["Humeur", "Nature"],
        contentWarning: "Avertissement de contenu hors ligne",
        filterNames: ["Première règle", "Deuxième règle"],
        pollOptions: ["Un", "Deux"],
        offlineError: "Données de démonstration hors ligne pour les captures"
    )

    static let italian = Self(
        names: ["Alessandro Riva", "Luna Bianchi", "Samuele Conti", "Marta Moretti", "Nora Galli", "Teo Greco", "Ilaria Costa", "Carlo Romano"],
        photoTags: ["Fotografia", "Gatti", "Caffè", "Lettura"],
        illustratedTags: ["Fotografia", "Illustrazione", "Natura", "Lettura"],
        notes: [
            "Piccole avventure, belle conversazioni e un po’ di spazio per crescere. 🌿",
            "Al servizio di due gatti. Ogni tanto fotografo il mondo fuori dalla finestra. 🐈",
            "Caffè, librerie dell’usato e passeggiate in città nel fine settimana. ☕️",
            "Escursioni, campeggio e quasi sempre su qualche sentiero. ⛰️",
            "Corse notturne, tramonti in città e un caffellatte caldo. 🌇",
            "Sono cresciuto al mare. Fotografo le maree e i pescherecci. 🌊",
            "Lavoro in una libreria indipendente. Un consiglio di lettura ogni settimana. 📚",
            "Tostatore di caffè. Annoto il gusto di ogni tazza. ☕️",
        ],
        profileFields: [["Su di me", "Fotografie e scoperte quotidiane"], ["Comunità", "Il web sociale aperto"]],
        photoPosts: [
            "Partenza alle cinque nel fine settimana per vedere l’alba in montagna. Quando la nebbia si è diradata, ho capito che ne era valsa la pena. ⛰️",
            "Tutto il lavoro di questo gatto oggi: seguire il raggio di sole sul divano. ☀️🐈",
            "Ha aperto un nuovo bar qui sotto. Cuori nella schiuma e un’intera parete di libri in un angolo. Trovato il programma per il fine settimana. ☕️📚",
            "Tornando a casa, il sole al tramonto si è infilato proprio tra due palazzi. Mi sono fermata un attimo a guardarlo. 🌇",
        ],
        photoReplies: [
            ["Che meraviglia! La prossima volta portami, al caffè caldo penso io. ☕️", "Questa foto è perfetta come sfondo. Che montagna è?"],
            ["Anche il mio gatto fa lo stesso giro inseguendo il sole. 😂", "Le gioie semplici di un gatto rosso. ☀️"],
            ["Il nome del bar, per favore! Ci voglio andare questo fine settimana.", "Quella parete di libri… Ci passerei un pomeriggio intero. 📚"],
            ["Le piccole gioie sulla strada di casa. 🌇", "Che luce! Sembra un fotogramma di un film."],
        ],
        photoDescriptions: [
            "La nebbia del mattino si dirada tra le cime illuminate dall’alba.",
            "Un gatto rosso raggomitolato sul divano, proprio in una chiazza di sole che entra dalla finestra.",
            "Un cappuccino con un cuore disegnato nella schiuma su un tavolo di legno.",
            "Un angolo del bar con scaffali di libri, piante e un tavolino.",
            "Una strada di sera, con il sole al tramonto che filtra da un albero tra due palazzi.",
        ],
        illustratedPosts: [
            ["Una mattina d’aria fresca dopo la pioggia. 🌿", "Che cosa vi ha fatto sorridere oggi?"],
            ["Ho sistemato un angolino per libri, piante e buon caffè. ☕️", "A volte le scoperte migliori sono proprio dietro l’angolo."],
            ["Il web aperto sembra una conversazione, un post scritto con cura alla volta.", "Che bello trovare persone affini qui. ✨"],
            ["Uno schizzo dalla passeggiata serale. Un po’ di spazio per le piccole cose. 🎨"],
        ],
        illustratedReplies: ["Il gatto del vicino dormiva al sole sul davanzale. Sono rimasta a guardarlo per un po’. ☀️",
                             "Una cartolina scritta a mano da un amico. Le lettere sono un po’ storte, ma è adorabile. ✉️"],
        illustrationDescription: "Un’illustrazione originale di un paesaggio tranquillo all’alba.",
        emojiCategories: ["Umore", "Natura"],
        contentWarning: "Avviso sul contenuto offline",
        filterNames: ["Prima regola", "Seconda regola"],
        pollOptions: ["Uno", "Due"],
        offlineError: "Dati di esempio offline per le schermate"
    )

    static let japanese = Self(
        names: ["佐藤 晴", "高橋 美月", "田中 颯太", "山本 美咲", "小林 遥", "伊藤 大地", "中村 葵", "渡辺 海"],
        photoTags: ["写真", "猫", "コーヒー", "読書"],
        illustratedTags: ["写真", "イラスト", "自然", "読書"],
        notes: [
            "小さな冒険と、心地よい会話。自分が育つ余白も少しだけ。🌿",
            "猫2匹のお世話係。ときどき窓の外を撮っています。🐈",
            "コーヒーと古本屋、週末の街歩きが好き。☕️",
            "山歩きとキャンプ。たいていどこかの道の上。⛰️",
            "夜のランニング、街の夕焼け、温かいラテ。🌇",
            "海辺育ち。潮の満ち引きや漁船を撮っています。🌊",
            "小さな独立書店の店員。毎週1冊、おすすめの本を紹介。📚",
            "コーヒーの焙煎をしています。一杯ごとの味を記録中。☕️",
        ],
        profileFields: [["自己紹介", "写真と日々の小さな発見"], ["コミュニティ", "開かれたソーシャルウェブ"]],
        photoPosts: [
            "週末は朝日を見に山へ。5時に出発したけれど、霧が晴れた瞬間、早起きしてよかったと思えた。⛰️",
            "うちの猫の今日のお仕事：ソファの上で、日だまりに合わせてお引っ越し。☀️🐈",
            "下の階に新しいカフェができた。ハートのラテアートに、壁一面の本棚。週末の居場所が見つかった。☕️📚",
            "帰り道、夕日がちょうどビルとビルの間に。少し立ち止まって眺めていた。🌇",
        ],
        photoReplies: [
            ["きれい！次は連れていって。温かいコーヒーを持っていくね。☕️", "そのまま壁紙にしたい一枚。どこの山？"],
            ["うちの猫も同じ。日だまりを追いかけて移動してる。😂", "茶トラの幸せって、こんなにシンプル。☀️"],
            ["お店の名前を教えて！週末に行ってみたい。", "あの本棚、いい雰囲気。午後いっぱい過ごせそう。📚"],
            ["帰り道の小さな幸せ。🌇", "この光、映画のワンシーンみたい。"],
        ],
        photoDescriptions: [
            "朝日を浴びた山々の間で、朝霧が晴れていく。",
            "窓から差し込む日だまりの中、ソファで丸くなっている茶トラの猫。",
            "木のテーブルに置かれた、ハートのラテアートのカプチーノ。",
            "本棚と観葉植物、小さなテーブルがあるカフェの一角。",
            "夕暮れの通り。二つのビルの間にある木の向こうから夕日が差している。",
        ],
        illustratedPosts: [
            ["雨上がりの朝、空気が気持ちいい。🌿", "今日はどんなことで笑顔になった？"],
            ["本と植物とコーヒーのために、小さな一角を整えた。☕️", "素敵な発見は、案外すぐそばにある。"],
            ["開かれたウェブは、丁寧に書かれた投稿がつながる会話みたい。", "ここで気の合う人たちに出会えてうれしい。✨"],
            ["夕方の散歩で描いたスケッチ。小さなことのために、少し余白を。🎨"],
        ],
        illustratedReplies: ["近所の猫が窓辺で日なたぼっこ。しばらく眺めてしまった。☀️", "友達から届いた手書きの絵はがき。少し曲がった文字も、なんだか愛おしい。✉️"],
        illustrationDescription: "日の出の静かな山の風景を描いたオリジナルイラスト。",
        emojiCategories: ["気分", "自然"],
        contentWarning: "オフラインのコンテンツ警告",
        filterNames: ["1つ目のルール", "2つ目のルール"],
        pollOptions: ["ひとつ", "ふたつ"],
        offlineError: "スクリーンショット用のオフラインサンプルデータ"
    )

    static let portuguese = Self(
        names: ["Alexandre Ribeiro", "Leonor Martins", "Samuel Costa", "Mariana Silva", "Inês Almeida", "Tomás Ferreira", "Isabel Sousa", "Diogo Pereira"],
        photoTags: ["Fotografia", "Gatos", "Café", "Leitura"],
        illustratedTags: ["Fotografia", "Ilustração", "Natureza", "Leitura"],
        notes: [
            "Pequenas aventuras, boas conversas e algum espaço para crescer. 🌿",
            "Ao serviço de dois gatos. De vez em quando fotografo a vista da janela. 🐈",
            "Café, alfarrabistas e passeios pela cidade ao fim de semana. ☕️",
            "Caminhadas, campismo e quase sempre algures num trilho. ⛰️",
            "Corridas à noite, pores do sol na cidade e um galão quentinho. 🌇",
            "Cresci à beira-mar. Fotografo as marés e os barcos de pesca. 🌊",
            "Trabalho numa livraria independente. Recomendo um livro por semana. 📚",
            "Torrefator de café. Registo o sabor de cada chávena. ☕️",
        ],
        profileFields: [["Sobre mim", "Fotografias e descobertas do dia a dia"], ["Comunidade", "A web social aberta"]],
        photoPosts: [
            "No fim de semana saí às cinco para ver o nascer do sol na serra. Quando o nevoeiro se dissipou, valeu a pena ter acordado tão cedo. ⛰️",
            "Todo o trabalho deste gato hoje: seguir a mancha de sol pelo sofá. ☀️🐈",
            "Abriu um café novo aqui em baixo. Corações na espuma e uma parede inteira de livros num canto. Já tenho planos para o fim de semana. ☕️📚",
            "A caminho de casa, o sol poente apareceu mesmo entre dois prédios. Parei um bocadinho para ver. 🌇",
        ],
        photoReplies: [
            ["Que maravilha! Leva-me da próxima vez, eu levo o café quente. ☕️", "Esta foto dava um fundo de ecrã. Que serra é esta?"],
            ["O meu gato faz exatamente o mesmo à procura do sol. 😂", "As alegrias simples de um gato ruivo. ☀️"],
            ["O nome do café, por favor! Quero ir lá este fim de semana.", "Aquela parede de livros… Ficava lá uma tarde inteira. 📚"],
            ["As pequenas alegrias no caminho para casa. 🌇", "Que luz! Parece um fotograma de um filme."],
        ],
        photoDescriptions: [
            "O nevoeiro da manhã dissipa-se entre os cumes iluminados pelo nascer do sol.",
            "Um gato ruivo enroscado no sofá, mesmo numa mancha de sol que entra pela janela.",
            "Um cappuccino com um coração desenhado na espuma, sobre uma mesa de madeira.",
            "Um canto do café com estantes de livros, plantas e uma mesa pequena.",
            "Uma rua ao fim da tarde, com o sol poente a atravessar uma árvore entre dois prédios.",
        ],
        illustratedPosts: [
            ["Uma manhã de ar fresco depois da chuva. 🌿", "O que vos fez sorrir hoje?"],
            ["Arrumei um cantinho para livros, plantas e bom café. ☕️", "Às vezes, as melhores descobertas estão mesmo ao pé de casa."],
            ["A web aberta parece uma conversa, com cada publicação escrita com cuidado.", "É bom encontrar por aqui pessoas com quem me identifico. ✨"],
            ["Um esboço do passeio ao fim da tarde. Dar espaço às pequenas coisas. 🎨"],
        ],
        illustratedReplies: ["O gato do vizinho estava a dormir ao sol no parapeito. Fiquei a olhar um bom bocado. ☀️",
                             "Um postal escrito à mão por um amigo. As letras estão um pouco tortas, mas tem muita graça. ✉️"],
        illustrationDescription: "Uma ilustração original de uma paisagem tranquila ao nascer do sol.",
        emojiCategories: ["Estado de espírito", "Natureza"],
        contentWarning: "Aviso de conteúdo offline",
        filterNames: ["Primeira regra", "Segunda regra"],
        pollOptions: ["Um", "Dois"],
        offlineError: "Dados de exemplo offline para capturas de ecrã"
    )
}
#endif
