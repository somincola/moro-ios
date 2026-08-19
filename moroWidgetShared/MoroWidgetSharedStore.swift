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

nonisolated struct MoroWidgetDataSnapshot: Equatable, Sendable {
    let sessionID: String
    let account: MoroWidgetAccount
    let unreadCount: Int
    let updatedAt: Date
}

nonisolated enum MoroWidgetSharedStore {
    static let appGroupIdentifier = "group.com.somincola.moro.app"

    private enum Keys {
        static let activeSession = "shared_active_account_session_snapshot_v1"
        static let unreadCounts = "notification_unread_counts_by_session_v1"
        static let unreadDirectMessageIDs = "direct_message_unread_conversation_ids_by_session_v1"
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
        let directMessageUnreadCount: Int = {
            guard let idsBySession = userDefaults.dictionary(forKey: Keys.unreadDirectMessageIDs),
                let ids = idsBySession[activeSession.sessionID] as? [String]
            else {
                return 0
            }
            return Set(ids).count
        }()

        return MoroWidgetDataSnapshot(
            sessionID: activeSession.sessionID,
            account: activeSession.account,
            unreadCount: notificationUnreadCount + directMessageUnreadCount,
            updatedAt: activeSession.updatedAt
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
    private static let key = "moro_widget_pending_handoff_v1"

    static func write(
        destination: MoroWidgetDestination,
        now: Date = Date(),
        to userDefaults: UserDefaults? = MoroWidgetSharedStore.sharedUserDefaults()
    ) {
        guard let userDefaults,
            let data = try? JSONEncoder().encode(
                MoroWidgetHandoff(destination: destination, createdAt: now)
            )
        else {
            return
        }
        userDefaults.set(data, forKey: key)
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
