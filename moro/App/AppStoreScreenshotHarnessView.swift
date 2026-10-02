#if DEBUG
import SDWebImage
import SwiftUI

/// Store assets use the production shell and screens with fictional, offline data.
struct AppStoreScreenshotHarnessView: View {
    @StateObject private var appState = AppState()
    @State private var ready = false
    private let client = AppStoreScreenshotProtocol.makeClient()

    var body: some View {
        Group {
            if ready {
                MainTabView(apiClient: client, onLogout: {}, accountSessions: [],
                    activeSessionID: "app-store-screenshots", onSwitchAccount: { _ in },
                    onRemoveAccount: { _ in }, onAccountAuthenticated: { _, _, _ in })
                    .environmentObject(appState)
            } else {
                ProgressView().task {
                    await AppStoreScreenshotProtocol.cacheIllustrations()
                    appState.currentAccount = try? JSONDecoder().decode(Account.self,
                        from: JSONSerialization.data(withJSONObject: AppStoreScreenshotProtocol.account(0)))
                    appState.isAuthenticated = true
                    AppSettings.shared.notificationPolicy = .anyone
                    ready = true
                }
            }
        }
        .moroTheme(MoroTheme())
    }
}

private final class AppStoreScreenshotToken: AuthTokenProvider {
    var authToken: String? { "offline-screenshot-token" }
}

private final class AppStoreScreenshotProtocol: URLProtocol, @unchecked Sendable {
    private static let base = "https://moro-screenshots.invalid"
    private static let names = ["Alex Rivers", "Luna Park", "Sam Chen", "Mira Stone"]
    private static let handles = ["alex", "luna", "sam", "mira"]
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

    static func account(_ index: Int) -> [String: Any] {
        ["id": "store-\(index)", "username": handles[index], "acct": handles[index],
         "display_name": names[index], "note": "<p>Small adventures, good conversations, and a little room to grow. 🌿</p>",
         "avatar": "\(base)/avatar-\(index).png", "avatar_static": "\(base)/avatar-\(index).png",
         "header": "\(base)/landscape.png", "header_static": "\(base)/landscape.png",
         "followers_count": 128, "following_count": 86, "statuses_count": 42,
         "url": "\(base)/@\(handles[index])", "show_media": true, "show_featured": true,
         "fields": [["name": "About", "value": "Photographs & everyday discoveries"],
                    ["name": "Community", "value": "The open social web"]],
         "source": ["privacy": "public", "language": "en"]]
    }

    private static func status(_ index: Int) -> [String: Any] {
        let copy = [
            "<p>A little fresh air, a slower morning. 🌿</p><p>What made you smile today? <a href='\(base)/tags/Photography'>#Photography</a></p>",
            "<p>Made a small corner for books, plants, and good coffee. ☕️</p><p>Sometimes the best discoveries are close to home.</p>",
            "<p>The open web feels like a conversation, one thoughtful post at a time.</p><p>Happy to find my people here. ✨</p>",
            "<p>A sketch from my evening walk. Making space for the little things. 🎨</p>",
        ]
        let media: [[String: Any]] = index == 0 ? [[
            "id": "store-photo", "type": "image", "url": "\(base)/landscape.png",
            "preview_url": "\(base)/landscape.png", "description": "An original illustration of a quiet landscape at sunrise.",
            "meta": ["original": ["width": 1200, "height": 720]],
        ]] : []
        var result: [String: Any] = ["id": String(900 - index), "content": copy[index], "account": account(index),
                "created_at": "2026-09-30T01:00:00.000Z", "media_attachments": media,
                "visibility": "public", "sensitive": false, "spoiler_text": "",
                "favourites_count": 24 - index * 4, "reblogs_count": 3, "replies_count": 5,
                "bookmarked": index == 1, "language": "en"]
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
            payload = ["display_name": Self.names[0], "note": "Small adventures and good conversations.",
                       "fields": [], "show_media": true, "show_featured": true]
        } else if path.hasSuffix("/unread_count") {
            payload = ["count": 0]
        } else if path.hasSuffix("/notifications") {
            let types = query.filter { $0.name == "types[]" }.compactMap(\.value)
            payload = (1...3).map { index -> [String: Any] in
                ["id": String(600 - index), "type": ["mention", "favourite", "follow"][index - 1],
                 "created_at": "2026-09-30T01:00:00.000Z", "account": Self.account(index),
                 "status": Self.status(index)]
            }.filter { types.isEmpty || types.contains($0["type"] as? String ?? "") }
        } else if path.hasSuffix("/trends/tags") || path.hasSuffix("/featured_tags") || path.hasSuffix("/followed_tags") {
            payload = ["Photography", "Art", "Nature", "Books"].map {
                ["id": "tag-\($0)", "name": $0, "url": "\(Self.base)/tags/\($0)",
                 "statuses_count": "12", "history": [["day": "1790726400", "uses": "128", "accounts": "42"]]] as [String: Any]
            }
        } else if path.hasSuffix("/directory") {
            payload = (1...3).map { Self.account($0) }
        } else if path.hasSuffix("/relationships") {
            payload = []
        } else if path.hasSuffix("/context") {
            payload = ["ancestors": [], "descendants": []]
        } else if path.hasSuffix("/search") {
            payload = ["accounts": (1...3).map { Self.account($0) }, "statuses": (0...3).map { Self.status($0) }, "hashtags": []]
        } else if path.hasSuffix("/markers") || path.hasSuffix("/preferences") {
            payload = [:]
        } else if path.contains("/timelines/") || path.hasSuffix("/statuses") || path.hasSuffix("/bookmarks") {
            payload = query.contains(where: { $0.name == "max_id" || $0.name == "since_id" || ($0.name == "pinned" && $0.value == "true") })
                ? [] : (0...3).map { Self.status($0) }
        } else if path.contains("/statuses/") {
            payload = Self.status(0)
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
    }
}
#endif
