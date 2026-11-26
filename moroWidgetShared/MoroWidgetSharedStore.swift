//
//  MoroWidgetSharedStore.swift
//  moro
//
//  Lightweight App Group models shared by the app and WidgetKit extension.
//

import Foundation

nonisolated enum MoroWidgetKind {
    static let overview = "com.somincola.moro.widget.overview"
    static let quickActions = "com.somincola.moro.widget.quick-actions"
    static let profileCard = "com.somincola.moro.widget.profile-card"
    static let comfort = "com.somincola.moro.widget.comfort"
}

nonisolated struct MoroWidgetAccount: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let acct: String
    let displayName: String
    let avatar: String
    let avatarStatic: String
    let followersCount: Int
    let followingCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case acct
        case displayName = "display_name"
        case avatar
        case avatarStatic = "avatar_static"
        case followersCount = "followers_count"
        case followingCount = "following_count"
    }

    init(
        id: String,
        username: String,
        acct: String,
        displayName: String,
        avatar: String,
        avatarStatic: String,
        followersCount: Int = 0,
        followingCount: Int = 0
    ) {
        self.id = id
        self.username = username
        self.acct = acct
        self.displayName = displayName
        self.avatar = avatar
        self.avatarStatic = avatarStatic
        self.followersCount = max(0, followersCount)
        self.followingCount = max(0, followingCount)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        acct = try container.decode(String.self, forKey: .acct)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        avatarStatic = try container.decodeIfPresent(String.self, forKey: .avatarStatic) ?? ""
        followersCount = max(0, try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0)
        followingCount = max(0, try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0)
    }

    var preferredName: String {
        let withoutEmojiShortcodes = displayName.replacingOccurrences(
            of: #":[A-Za-z0-9_+\-]+:"#,
            with: "",
            options: .regularExpression
        )
        let normalized = withoutEmojiShortcodes
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? username : normalized
    }

    var handle: String {
        acct.hasPrefix("@") ? acct : "@\(acct)"
    }

    var instanceDomain: String? {
        let trimmed = acct.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "@", omittingEmptySubsequences: true)
        guard components.count >= 2, let host = components.last else { return nil }
        let value = String(host)
        return value.isEmpty ? nil : value
    }

    var avatarURL: URL? {
        [avatarStatic, avatar]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
            .first { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "https" || scheme == "http") && url.host != nil
            }
    }
}

nonisolated struct MoroWidgetAccent: Codable, Equatable, Sendable {
    static let defaultCustomRGB: UInt32 = 0x0052A3
    static let `default` = MoroWidgetAccent(
        themeColorRawValue: "blue",
        customRGB: defaultCustomRGB
    )

    let themeColorRawValue: String
    let customRGB: UInt32

    init(themeColorRawValue: String, customRGB: UInt32 = defaultCustomRGB) {
        self.themeColorRawValue = themeColorRawValue
        self.customRGB = customRGB & 0xFFFFFF
    }

    func resolvedHex(isDarkMode: Bool) -> UInt32 {
        switch themeColorRawValue {
        case "blue":
            return isDarkMode ? 0x3E95F5 : 0x0052A3
        case "yellow":
            return isDarkMode ? 0xF2C94C : 0x8A6400
        case "pink":
            return isDarkMode ? 0xFF70AB : 0xC2185B
        case "purple":
            return isDarkMode ? 0xB69CFF : 0x6F42C1
        case "orange":
            return isDarkMode ? 0xFFAA66 : 0xB45100
        case "green":
            return isDarkMode ? 0x53D6A4 : 0x007F5F
        case "custom":
            return Self.accessibleCustomHex(customRGB, isDarkMode: isDarkMode)
        default:
            return isDarkMode ? 0x3E95F5 : 0x0052A3
        }
    }

    func prefersDarkForeground(isDarkMode: Bool) -> Bool {
        let luminance = Self.luminance(resolvedHex(isDarkMode: isDarkMode))
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    private static func accessibleCustomHex(_ raw: UInt32, isDarkMode: Bool) -> UInt32 {
        let original = raw & 0xFFFFFF
        let background: UInt32 = isDarkMode ? 0x16181A : 0xFFFFFF
        let backgroundLuminance = luminance(background)
        func isReadable(_ color: UInt32) -> Bool {
            let fg = luminance(color)
            return (max(fg, backgroundLuminance) + 0.05) / (min(fg, backgroundLuminance) + 0.05) >= 4.5
        }
        guard !isReadable(original) else { return original }

        let target = isDarkMode ? 255.0 : 0.0
        func shade(_ amount: Double) -> UInt32 {
            var hex: UInt32 = 0
            for shift in [16, 8, 0] {
                let component = Double((original >> shift) & 0xFF)
                hex |= UInt32((component + (target - component) * amount).rounded()) << shift
            }
            return hex
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<12 {
            let middle = (lower + upper) / 2
            if isReadable(shade(middle)) {
                upper = middle
            } else {
                lower = middle
            }
        }
        return shade(upper)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func linear(_ shift: Int) -> Double {
            let component = Double((hex >> shift) & 0xFF) / 255.0
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }
}

nonisolated struct MoroWidgetDataSnapshot: Equatable, Sendable {
    let sessionID: String
    let account: MoroWidgetAccount
    let unreadCount: Int
    let updatedAt: Date
    let accent: MoroWidgetAccent

    init(
        sessionID: String,
        account: MoroWidgetAccount,
        unreadCount: Int,
        updatedAt: Date,
        accent: MoroWidgetAccent = .default
    ) {
        self.sessionID = sessionID
        self.account = account
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.accent = accent
    }
}

nonisolated enum MoroWidgetSharedStore {
    static let appGroupIdentifier = "group.com.somincola.moro.app"

    private enum Keys {
        static let activeSession = "shared_active_account_session_snapshot_v1"
        static let unreadCounts = "notification_unread_counts_by_session_v1"
        static let themeAccent = "moro_widget_theme_accent_v1"
        static let avatarCachePrefix = "moro_widget_avatar_cache_v1_"
        static let avatarSourcePrefix = "moro_widget_avatar_source_v1_"
    }

    private struct ActiveSession: Decodable {
        let sessionID: String
        let account: MoroWidgetAccount
        let updatedAt: Date
    }

    static func sharedUserDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static func loadAccent(from userDefaults: UserDefaults? = sharedUserDefaults()) -> MoroWidgetAccent {
        guard let userDefaults,
            let data = userDefaults.data(forKey: Keys.themeAccent),
            let accent = try? JSONDecoder().decode(MoroWidgetAccent.self, from: data)
        else {
            return .default
        }
        return accent
    }

    static func saveAccent(
        _ accent: MoroWidgetAccent,
        to userDefaults: UserDefaults? = sharedUserDefaults()
    ) {
        guard let userDefaults,
            let data = try? JSONEncoder().encode(accent)
        else {
            return
        }
        userDefaults.set(data, forKey: Keys.themeAccent)
    }

    static func loadSnapshot(from userDefaults: UserDefaults? = sharedUserDefaults()) -> MoroWidgetDataSnapshot? {
        guard let userDefaults,
            let data = userDefaults.data(forKey: Keys.activeSession),
            let activeSession = try? JSONDecoder().decode(ActiveSession.self, from: data)
        else {
            return nil
        }

        let notificationUnreadCount: Int = {
            guard let counts = userDefaults.dictionary(forKey: Keys.unreadCounts),
                let number = counts[activeSession.sessionID] as? NSNumber
            else {
                return 0
            }
            return max(0, number.intValue)
        }()

        return MoroWidgetDataSnapshot(
            sessionID: activeSession.sessionID,
            account: activeSession.account,
            unreadCount: notificationUnreadCount,
            updatedAt: activeSession.updatedAt,
            accent: loadAccent(from: userDefaults)
        )
    }

    static func cachedAvatarData(
        accountID: String,
        sourceURL: URL?,
        from userDefaults: UserDefaults? = sharedUserDefaults()
    ) -> Data? {
        if let sourceURL,
            userDefaults?.string(forKey: Keys.avatarSourcePrefix + accountID) != sourceURL.absoluteString
        {
            return nil
        }
        return userDefaults?.data(forKey: Keys.avatarCachePrefix + accountID)
    }

    static func cacheAvatarData(
        _ data: Data,
        accountID: String,
        sourceURL: URL?,
        in userDefaults: UserDefaults? = sharedUserDefaults()
    ) {
        guard data.count <= 3_000_000 else { return }
        userDefaults?.set(data, forKey: Keys.avatarCachePrefix + accountID)
        userDefaults?.set(sourceURL?.absoluteString, forKey: Keys.avatarSourcePrefix + accountID)
    }
}

nonisolated enum MoroWidgetDestination: String, Codable, CaseIterable, Hashable, Sendable {
    case home
    case compose
    case search
    case inbox
    case profile

    var deepLinkURL: URL {
        URL(string: "moro://open/\(rawValue)")!
    }

    init?(deepLinkURL url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "moro",
            components.host?.lowercased() == "open",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            components.queryItems == nil,
            components.fragment == nil
        else {
            return nil
        }

        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
        guard segments.count == 1, let target = segments.first else {
            return nil
        }

        if target == "notifications" {
            self = .inbox
            return
        }
        guard let destination = Self(rawValue: target) else {
            return nil
        }
        self = destination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "notifications" {
            self = .inbox
            return
        }
        guard let destination = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Moro widget destination: \(rawValue)"
            )
        }
        self = destination
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct MoroWidgetHandoff: Codable, Equatable, Sendable {
    let destination: MoroWidgetDestination
    let createdAt: Date
}

nonisolated enum MoroWidgetHandoffStore {
    static let didWriteNotification = Notification.Name("com.somincola.moro.widget.handoffDidWrite")
    private static let key = "moro_widget_pending_handoff_v1"

    static func write(
        destination: MoroWidgetDestination,
        now: Date = Date(),
        to userDefaults: UserDefaults? = MoroWidgetSharedStore.sharedUserDefaults(),
        notificationCenter: NotificationCenter? = .default
    ) {
        guard let userDefaults,
            let data = try? JSONEncoder().encode(
                MoroWidgetHandoff(destination: destination, createdAt: now)
            )
        else {
            return
        }
        userDefaults.set(data, forKey: key)
        notificationCenter?.post(name: didWriteNotification, object: nil)
    }

    static func consume(
        from userDefaults: UserDefaults? = MoroWidgetSharedStore.sharedUserDefaults(),
        now: Date = Date(),
        maximumAge: TimeInterval = 10 * 60
    ) -> MoroWidgetHandoff? {
        guard let userDefaults,
            let data = userDefaults.data(forKey: key)
        else {
            return nil
        }

        userDefaults.removeObject(forKey: key)
        guard let handoff = try? JSONDecoder().decode(MoroWidgetHandoff.self, from: data),
            now.timeIntervalSince(handoff.createdAt) <= maximumAge
        else {
            return nil
        }
        return handoff
    }
}
