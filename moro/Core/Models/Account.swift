//
//  Account.swift
//  moro
//
//  Mastodon account model with full profile information.
//

import Foundation

struct Account: Identifiable, Codable, Hashable {
    struct Emoji: Codable, Hashable {
        let shortcode: String
        let url: URL
        let staticURL: URL

        enum CodingKeys: String, CodingKey {
            case shortcode
            case url
            case staticURL = "static_url"
        }
    }

    /// Account preferences, returned only by `verify_credentials`. Holds the
    /// server-side defaults the user set on their instance — notably the
    /// default posting language and visibility.
    struct Source: Codable, Hashable {
        let language: String?
        let privacy: String?
        let hideCollections: Bool?
        let discoverable: Bool?
        let indexable: Bool?

        enum CodingKeys: String, CodingKey {
            case language
            case privacy
            case hideCollections = "hide_collections"
            case discoverable
            case indexable
        }

        init(
            language: String? = nil,
            privacy: String? = nil,
            hideCollections: Bool? = nil,
            discoverable: Bool? = nil,
            indexable: Bool? = nil
        ) {
            self.language = language
            self.privacy = privacy
            self.hideCollections = hideCollections
            self.discoverable = discoverable
            self.indexable = indexable
        }
    }

    let id: String
    let username: String
    let acct: String
    let displayName: String
    let note: String
    let avatar: String
    let avatarStatic: String
    let header: String
    let headerStatic: String
    let followersCount: Int
    let followingCount: Int
    let statusesCount: Int
    let createdAt: Date?
    let locked: Bool
    let bot: Bool
    let fields: [AccountField]
    let emojis: [Emoji]
    
    // Optional fields
    let url: String?
    let moved: Indirect<Account>?
    let suspended: Bool?
    let limited: Bool?
    /// Server-side account preferences (only populated from verify_credentials).
    let source: Source?
    let discoverable: Bool?
    let indexable: Bool?
    let hideCollections: Bool?

    /// The account's default posting language as configured on the server, if any.
    var defaultPostingLanguage: String? {
        guard let language = source?.language?.trimmingCharacters(in: .whitespacesAndNewlines),
            !language.isEmpty
        else { return nil }
        return language
    }

    var credentialDiscoverable: Bool? {
        source?.discoverable ?? discoverable
    }

    var credentialIndexable: Bool? {
        source?.indexable ?? indexable
    }

    var credentialHideCollections: Bool? {
        source?.hideCollections ?? hideCollections
    }

    /// Convenience accessor for moved account
    var movedAccount: Account? {
        moved?.value
    }
    
    // Computed properties
    /// Static avatar URL (non-animated)
    var avatarURL: URL? {
        URL(string: avatarStatic)
    }
    
    /// Animated avatar URL (GIF/WebP)
    var avatarAnimatedURL: URL? {
        let urlString = avatar.isEmpty ? avatarStatic : avatar
        return URL(string: urlString)
    }

    /// Avatar media suitable for profile presentation. Mastodon commonly uses
    /// `missing.png` when an account has no custom avatar.
    var profileAvatarURL: URL? {
        [avatar, avatarStatic]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
            .first { url in
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      url.host != nil
                else { return false }

                return url.lastPathComponent.lowercased() != "missing.png"
            }
    }
    
    /// Static header URL (non-animated)
    var headerURL: URL? {
        URL(string: headerStatic)
    }
    
    /// Animated header URL (GIF/WebP)
    var headerAnimatedURL: URL? {
        let urlString = header.isEmpty ? headerStatic : header
        return URL(string: urlString)
    }

    /// Header media suitable for profile presentation. Mastodon uses
    /// `missing.png` for accounts without a custom header on some instances.
    var profileHeaderURL: URL? {
        [header, headerStatic]
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
            .first { url in
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http",
                      url.host != nil
                else { return false }

                return url.lastPathComponent.lowercased() != "missing.png"
            }
    }
    
    /// Display name with fallback to username
    var displayNameFormatted: String {
        displayNameContent.plainText
    }

    /// Parsed display name segments for inline custom emoji rendering
    var displayNameContent: AccountDisplayNameContent {
        AccountDisplayNameParser.parse(
            displayName: displayName,
            fallbackUsername: username,
            emojis: emojis
        )
    }

    /// Avatar initials should ignore custom emoji-only prefixes.
    var displayNameInitials: String {
        displayNameContent.initials
    }

    /// Shared emoji payload for account-authored rich text such as bio/note.
    var contentEmojis: [Status.Emoji] {
        emojis.map {
            Status.Emoji(
                shortcode: $0.shortcode,
                url: $0.url,
                staticURL: $0.staticURL
            )
        }
    }

    var contentBaseURL: URL? {
        if let url, let parsed = URL(string: url), parsed.host != nil {
            return parsed
        }

        let host = acct
            .split(separator: "@", omittingEmptySubsequences: true)
            .dropFirst()
            .first
            .map(String.init)

        guard let host, !host.isEmpty else { return nil }
        return URL(string: "https://\(host)")
    }

    /// Parsed note elements preserve links, line breaks, and custom emoji.
    var noteContentElements: [ContentElement] {
        ContentParser.parseToElements(
            html: note,
            mentions: nil,
            tags: nil,
            emojis: contentEmojis,
            contentBaseURL: contentBaseURL,
            options: .accountRichText
        )
    }

    /// Compact plain-text preview for list surfaces and accessibility labels.
    var notePreviewText: String {
        noteContentElements.normalizedInlinePlainText
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case acct
        case displayName = "display_name"
        case note
        case avatar
        case avatarStatic = "avatar_static"
        case header
        case headerStatic = "header_static"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case statusesCount = "statuses_count"
        case createdAt = "created_at"
        case locked
        case bot
        case fields
        case formattedFields = "formatted_fields"
        case emojis
        case url
        case moved
        case suspended
        case limited
        case source
        case discoverable
        case indexable
        case hideCollections = "hide_collections"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        acct = try container.decodeIfPresent(String.self, forKey: .acct) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        avatarStatic = try container.decodeIfPresent(String.self, forKey: .avatarStatic) ?? ""
        header = try container.decodeIfPresent(String.self, forKey: .header) ?? ""
        headerStatic = try container.decodeIfPresent(String.self, forKey: .headerStatic) ?? ""
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        statusesCount = try container.decodeIfPresent(Int.self, forKey: .statusesCount) ?? 0
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        bot = try container.decodeIfPresent(Bool.self, forKey: .bot) ?? false
        let decodedFields = try container.decodeIfPresent([AccountField].self, forKey: .fields)
        let formattedFields = try container.decodeIfPresent(
            [AccountField].self,
            forKey: .formattedFields
        )
        if let formattedFields, !formattedFields.isEmpty {
            fields = formattedFields
        } else {
            fields = decodedFields ?? []
        }
        emojis = try container.decodeIfPresent([Emoji].self, forKey: .emojis) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
        if let movedAccount = try container.decodeIfPresent(Account.self, forKey: .moved) {
            moved = Indirect(movedAccount)
        } else {
            moved = nil
        }
        suspended = try container.decodeIfPresent(Bool.self, forKey: .suspended)
        limited = try container.decodeIfPresent(Bool.self, forKey: .limited)
        source = try container.decodeIfPresent(Source.self, forKey: .source)
        discoverable = try container.decodeIfPresent(Bool.self, forKey: .discoverable)
        indexable = try container.decodeIfPresent(Bool.self, forKey: .indexable)
        hideCollections = try container.decodeIfPresent(Bool.self, forKey: .hideCollections)

        // Decode createdAt with flexible date parsing
        if let dateString = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = DateFormatting.parseISO8601(dateString)
        } else {
            createdAt = nil
        }
    }
    
    // Manual initializer for previews and testing
    init(
        id: String,
        username: String,
        acct: String,
        displayName: String,
        note: String,
        avatar: String,
        avatarStatic: String,
        header: String,
        headerStatic: String,
        followersCount: Int,
        followingCount: Int,
        statusesCount: Int,
        createdAt: Date? = nil,
        locked: Bool = false,
        bot: Bool = false,
        fields: [AccountField] = [],
        emojis: [Emoji] = [],
        url: String? = nil,
        moved: Account? = nil,
        suspended: Bool? = nil,
        limited: Bool? = nil,
        source: Source? = nil,
        discoverable: Bool? = nil,
        indexable: Bool? = nil,
        hideCollections: Bool? = nil
    ) {
        self.id = id
        self.username = username
        self.acct = acct
        self.displayName = displayName
        self.note = note
        self.avatar = avatar
        self.avatarStatic = avatarStatic
        self.header = header
        self.headerStatic = headerStatic
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount = statusesCount
        self.createdAt = createdAt
        self.locked = locked
        self.bot = bot
        self.fields = fields
        self.emojis = emojis
        self.url = url
        self.moved = moved.map { Indirect($0) }
        self.suspended = suspended
        self.limited = limited
        self.source = source
        self.discoverable = discoverable
        self.indexable = indexable
        self.hideCollections = hideCollections
    }

    /// Returns a copy with an updated followers count, preserving every other field —
    /// notably `emojis`, which a hand-rebuilt Account silently drops to [].
    func updating(followersCount: Int? = nil) -> Account {
        Account(
            id: id,
            username: username,
            acct: acct,
            displayName: displayName,
            note: note,
            avatar: avatar,
            avatarStatic: avatarStatic,
            header: header,
            headerStatic: headerStatic,
            followersCount: followersCount ?? self.followersCount,
            followingCount: followingCount,
            statusesCount: statusesCount,
            createdAt: createdAt,
            locked: locked,
            bot: bot,
            fields: fields,
            emojis: emojis,
            url: url,
            moved: movedAccount,
            suspended: suspended,
            limited: limited,
            source: source,
            discoverable: discoverable,
            indexable: indexable,
            hideCollections: hideCollections
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(acct, forKey: .acct)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(note, forKey: .note)
        try container.encode(avatar, forKey: .avatar)
        try container.encode(avatarStatic, forKey: .avatarStatic)
        try container.encode(header, forKey: .header)
        try container.encode(headerStatic, forKey: .headerStatic)
        try container.encode(followersCount, forKey: .followersCount)
        try container.encode(followingCount, forKey: .followingCount)
        try container.encode(statusesCount, forKey: .statusesCount)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(locked, forKey: .locked)
        try container.encode(bot, forKey: .bot)
        try container.encode(fields, forKey: .fields)
        try container.encode(emojis, forKey: .emojis)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(moved?.value, forKey: .moved)
        try container.encodeIfPresent(suspended, forKey: .suspended)
        try container.encodeIfPresent(limited, forKey: .limited)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(discoverable, forKey: .discoverable)
        try container.encodeIfPresent(indexable, forKey: .indexable)
        try container.encodeIfPresent(hideCollections, forKey: .hideCollections)
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Account Field

struct AccountField: Codable, Hashable, Identifiable {
    let name: String
    let value: String
    let verifiedAt: Date?
    
    var id: String { name }
    
    var isVerified: Bool {
        verifiedAt != nil
    }

    func nameContentElements(emojis: [Status.Emoji], contentBaseURL: URL? = nil) -> [ContentElement] {
        ContentParser.parseToElements(
            html: name,
            mentions: nil,
            tags: nil,
            emojis: emojis,
            contentBaseURL: contentBaseURL,
            options: .accountRichText
        )
    }

    func valueContentElements(emojis: [Status.Emoji], contentBaseURL: URL? = nil) -> [ContentElement] {
        ContentParser.parseToElements(
            html: value,
            mentions: nil,
            tags: nil,
            emojis: emojis,
            contentBaseURL: contentBaseURL,
            options: .accountRichText
        )
    }
    
    /// Stripped HTML value for display
    var displayValue: String {
        HTMLParser.stripHTML(value)
    }
    
    /// URL if the value contains a link
    var linkURL: URL? {
        // Try to extract URL from the HTML value
        let pattern = #"href="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range(at: 1), in: value) {
            return URL(string: String(value[range]))
        }
        return nil
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case value
        case verifiedAt = "verified_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(String.self, forKey: .value)
        
        if let dateString = try? container.decodeIfPresent(String.self, forKey: .verifiedAt) {
            verifiedAt = DateFormatting.parseISO8601(dateString)
        } else {
            verifiedAt = nil
        }
    }
    
    init(name: String, value: String, verifiedAt: Date? = nil) {
        self.name = name
        self.value = value
        self.verifiedAt = verifiedAt
    }
}
