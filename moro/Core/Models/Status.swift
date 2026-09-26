//
//  Status.swift
//  moro
//
//  Complete Mastodon status model with reblog, quote, and reply support.
//

import Foundation

// Indirect wrapper to allow recursive structures in value types.
// Modeled as an `indirect enum` rather than a `final class`: the class form crashes the
// Swift -O optimizer (EarlyPerfInliner on the generic deinit, Xcode 26.5) during the Release
// archive. `.value` is only ever read here, so value semantics is equivalent.
enum Indirect<T> {
    indirect case wrapped(T)

    nonisolated init(_ value: T) {
        self = .wrapped(value)
    }

    var value: T {
        get {
            switch self {
            case .wrapped(let value): return value
            }
        }
        set {
            self = .wrapped(newValue)
        }
    }
}

extension Indirect: Codable where T: Codable {
    init(from decoder: Decoder) throws {
        self.init(try T(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension Indirect: Equatable where T: Equatable {
    static func == (lhs: Indirect<T>, rhs: Indirect<T>) -> Bool {
        return lhs.value == rhs.value
    }
}

struct Status: Identifiable, Codable, Hashable {
    /// Authorization state for a Mastodon quote placeholder.
    /// Unknown server values are intentionally treated as unauthorized.
    enum QuoteState: String, Codable {
        case pending
        case accepted
        case rejected
        case revoked
        case deleted
        case unauthorized
        case blockedAccount = "blocked_account"
        case blockedDomain = "blocked_domain"
        case mutedAccount = "muted_account"

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = QuoteState(rawValue: rawValue) ?? .unauthorized
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// Mastodon 4.4+ quote entity. A status is displayable only after consent
    /// has been accepted, even when a server happens to include it otherwise.
    struct Quote: Codable {
        let state: QuoteState
        private let wrappedStatus: Indirect<Status>?

        var quotedStatus: Status? {
            wrappedStatus?.value
        }

        var displayableStatus: Status? {
            guard state == .accepted else { return nil }
            return quotedStatus
        }

        init(state: QuoteState, quotedStatus: Status? = nil) {
            self.state = state
            wrappedStatus = quotedStatus.map(Indirect.init)
        }

        private enum CodingKeys: String, CodingKey {
            case state
            case quotedStatus = "quoted_status"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Current Mastodon API shape: { state, quoted_status }.
            if container.contains(.state) {
                state = try container.decode(QuoteState.self, forKey: .state)
                wrappedStatus = try container.decodeIfPresent(Indirect<Status>.self, forKey: .quotedStatus)
                return
            }

            // Preserve compatibility with older/non-standard servers that
            // returned the quoted Status directly under the `quote` key.
            state = .accepted
            wrappedStatus = Indirect(try Status(from: decoder))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(state, forKey: .state)
            if let wrappedStatus {
                try container.encode(wrappedStatus, forKey: .quotedStatus)
            }
        }
    }

    // MARK: - Hashable conformance (based on unique ID)
    static func == (lhs: Status, rhs: Status) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    struct Attachment: Identifiable, Codable {
        let id: String
        let type: String
        let url: URL
        let previewURL: URL?
        let description: String?
        let blurhash: String?
        let meta: AttachmentMeta?
        
        struct AttachmentMeta: Codable {
            let original: MediaSize?
            let small: MediaSize?
            
            struct MediaSize: Codable {
                let width: Int?
                let height: Int?
                let aspect: Double?
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case url
            case previewURL = "preview_url"
            case description
            case blurhash
            case meta
        }
        
        // Convenience initializer for manual creation (e.g., Previews)
        init(id: String, type: String, url: URL, previewURL: URL? = nil, description: String? = nil, blurhash: String? = nil, meta: AttachmentMeta? = nil) {
            self.id = id
            self.type = type
            self.url = url
            self.previewURL = previewURL
            self.description = description
            self.blurhash = blurhash
            self.meta = meta
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
            // A still-processing upload (HTTP 202 from /api/v2/media) returns a null `url`;
            // fall back to the preview so decoding doesn't fail and the upload can complete.
            if let resolvedURL = try container.decodeIfPresent(URL.self, forKey: .url) {
                url = resolvedURL
            } else {
                url = previewURL ?? URL(string: "about:blank")!
            }
            description = try container.decodeIfPresent(String.self, forKey: .description)
            blurhash = try container.decodeIfPresent(String.self, forKey: .blurhash)
            meta = try container.decodeIfPresent(AttachmentMeta.self, forKey: .meta)
        }

        // Computed property for aspect ratio
        var aspectRatio: Double? {
            if let aspect = meta?.original?.aspect, aspect.isFinite, aspect > 0 {
                return aspect
            }
            if let width = meta?.original?.width, let height = meta?.original?.height,
                width > 0, height > 0
            {
                return Double(width) / Double(height)
            }
            return nil
        }

        /// Aspect ratio of the preview rendered in timeline cells. Standalone attachments
        /// use `meta.small` because that is also the image loaded for the preview.
        /// Fall back to the original dimensions for servers that omit preview metadata.
        var previewAspectRatio: Double? {
            if let aspect = meta?.small?.aspect, aspect.isFinite, aspect > 0 {
                return aspect
            }
            if let width = meta?.small?.width, let height = meta?.small?.height,
                width > 0, height > 0
            {
                return Double(width) / Double(height)
            }
            return aspectRatio
        }
    }
    
    struct Mention: Codable, Hashable {
        let id: String
        let username: String
        let url: URL
        let acct: String
    }
    
    struct Tag: Codable {
        let name: String
        let url: URL
    }
    
    struct Emoji: Codable {
        let shortcode: String
        let url: URL
        let staticURL: URL
        
        enum CodingKeys: String, CodingKey {
            case shortcode
            case url
            case staticURL = "static_url"
        }
    }

    struct FilterResult: Codable, Hashable {
        struct Filter: Codable, Hashable {
            let title: String?

            init(title: String?) {
                self.title = title
            }
        }

        let filter: Filter?
        let title: String?
        let keywordMatches: [String]?
        let statusMatches: [String]?
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case filter
            case title
            case keywordMatches = "keyword_matches"
            case statusMatches = "status_matches"
            case expiresAt = "expires_at"
        }

        init(
            filter: Filter? = nil,
            title: String? = nil,
            keywordMatches: [String]? = nil,
            statusMatches: [String]? = nil,
            expiresAt: Date? = nil
        ) {
            self.filter = filter
            self.title = title
            self.keywordMatches = keywordMatches
            self.statusMatches = statusMatches
            self.expiresAt = expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filter = try container.decodeIfPresent(Filter.self, forKey: .filter)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            keywordMatches = try container.decodeIfPresent([String].self, forKey: .keywordMatches)
            statusMatches = try container.decodeIfPresent([String].self, forKey: .statusMatches)

            if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
                expiresAt = DateFormatting.parseISO8601(expiresAtString)
            } else {
                expiresAt = nil
            }
        }

        var displayTitle: String? {
            filter?.title ?? title
        }
    }
    
    /// Link Preview Card (OpenGraph/oEmbed data)
    struct PreviewCard: Codable {
        let url: URL
        let title: String
        let description: String
        let type: CardType
        let authorName: String?
        let authorURL: URL?
        let providerName: String?
        let providerURL: URL?
        let html: String?
        let width: Int?
        let height: Int?
        let image: URL?
        let embedURL: URL?
        let blurhash: String?
        let authors: [CardAuthor]?
        let publishedAt: Date?
        
        struct CardAuthor: Codable {
            let name: String?
            let url: URL?
            let account: Account?
            
            enum CodingKeys: String, CodingKey {
                case name
                case url
                case account
            }
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
                
                if let urlString = try container.decodeIfPresent(String.self, forKey: .url),
                   !urlString.isEmpty {
                    url = URL(string: urlString)
                } else {
                    url = nil
                }
                
                account = try container.decodeIfPresent(Account.self, forKey: .account)
            }
        }
        
        enum CardType: String, Codable {
            case link
            case photo
            case video
            case rich
            case unknown
            
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                self = CardType(rawValue: value) ?? .unknown
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case url
            case title
            case description
            case type
            case authorName = "author_name"
            case authorURL = "author_url"
            case providerName = "provider_name"
            case providerURL = "provider_url"
            case html
            case width
            case height
            case image
            case embedURL = "embed_url"
            case blurhash
            case authors
            case publishedAt = "published_at"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(URL.self, forKey: .url)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
            type = try container.decodeIfPresent(CardType.self, forKey: .type) ?? .link
            authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
            
            // URL fields: decode as String first, then convert (handles empty strings)
            if let authorURLString = try container.decodeIfPresent(String.self, forKey: .authorURL),
               !authorURLString.isEmpty {
                authorURL = URL(string: authorURLString)
            } else {
                authorURL = nil
            }
            
            providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
            
            if let providerURLString = try container.decodeIfPresent(String.self, forKey: .providerURL),
               !providerURLString.isEmpty {
                providerURL = URL(string: providerURLString)
            } else {
                providerURL = nil
            }
            
            html = try container.decodeIfPresent(String.self, forKey: .html)
            width = try container.decodeIfPresent(Int.self, forKey: .width)
            height = try container.decodeIfPresent(Int.self, forKey: .height)
            
            if let imageString = try container.decodeIfPresent(String.self, forKey: .image),
               !imageString.isEmpty {
                image = URL(string: imageString)
            } else {
                image = nil
            }
            
            if let embedURLString = try container.decodeIfPresent(String.self, forKey: .embedURL),
               !embedURLString.isEmpty {
                embedURL = URL(string: embedURLString)
            } else {
                embedURL = nil
            }
            
            blurhash = try container.decodeIfPresent(String.self, forKey: .blurhash)
            authors = try container.decodeIfPresent([CardAuthor].self, forKey: .authors)
            
            // Decode published_at as ISO8601 date
            if let publishedAtString = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
                publishedAt = DateFormatting.parseISO8601(publishedAtString)
            } else {
                publishedAt = nil
            }
        }
        
        /// Display name for the provider (fallback to URL host)
        var displayProviderName: String {
            if let name = providerName, !name.isEmpty {
                return name
            }
            return url.host ?? ""
        }
        
        /// Format published date for display
        var formattedPublishedDate: String? {
            guard let publishedAt = publishedAt else { return nil }
            return DateFormatting.relativeString(for: publishedAt)
        }
        
        // Manual initializer for previews
        init(url: URL, title: String, description: String, type: CardType, authorName: String?, authorURL: URL?, providerName: String?, providerURL: URL?, html: String?, width: Int?, height: Int?, image: URL?, embedURL: URL?, blurhash: String?, authors: [CardAuthor]? = nil, publishedAt: Date? = nil) {
            self.url = url
            self.title = title
            self.description = description
            self.type = type
            self.authorName = authorName
            self.authorURL = authorURL
            self.providerName = providerName
            self.providerURL = providerURL
            self.html = html
            self.width = width
            self.height = height
            self.image = image
            self.embedURL = embedURL
            self.blurhash = blurhash
            self.authors = authors
            self.publishedAt = publishedAt
        }
    }

    let id: String
    let content: String
    let createdAt: Date
    let account: Account
    let mediaAttachments: [Attachment]
    let favouritesCount: Int
    let reblogsCount: Int
    let repliesCount: Int
    let bookmarked: Bool
    let favourited: Bool
    let reblogged: Bool
    
    // Reblog support (using indirect wrapper for recursion)
    let reblog: Indirect<Status>?
    
    // Consent-aware quote support.
    let quote: Quote?
    
    // Reply support
    let inReplyToID: String?
    let inReplyToAccountID: String?
    
    // Additional fields
    let spoilerText: String?
    let sensitive: Bool
    let visibility: String?
    let language: String?
    let uri: String?
    let url: URL?
    let mentions: [Mention]?
    let tags: [Tag]?
    let emojis: [Emoji]?
    let card: PreviewCard?
    let poll: Poll?
    let filtered: [FilterResult]?
    let pinned: Bool?
    let editedAt: Date?
    
    /// Poll structure (for future implementation)
    struct Poll: Codable {
        let id: String
        let expiresAt: Date?
        let expired: Bool
        let multiple: Bool
        let votesCount: Int
        let votersCount: Int?
        let options: [PollOption]
        let voted: Bool?
        let ownVotes: [Int]?
        
        struct PollOption: Codable {
            let title: String
            let votesCount: Int?
            
            enum CodingKeys: String, CodingKey {
                case title
                case votesCount = "votes_count"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case id
            case expiresAt = "expires_at"
            case expired
            case multiple
            case votesCount = "votes_count"
            case votersCount = "voters_count"
            case options
            case voted
            case ownVotes = "own_votes"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)

            // Handle expires_at as ISO8601 string
            if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
                expiresAt = DateFormatting.parseISO8601(expiresAtString)
            } else {
                expiresAt = nil
            }

            expired = try container.decodeIfPresent(Bool.self, forKey: .expired) ?? false
            multiple = try container.decodeIfPresent(Bool.self, forKey: .multiple) ?? false
            votesCount = try container.decodeIfPresent(Int.self, forKey: .votesCount) ?? 0
            votersCount = try container.decodeIfPresent(Int.self, forKey: .votersCount)
            options = try container.decodeIfPresent([PollOption].self, forKey: .options) ?? []
            voted = try container.decodeIfPresent(Bool.self, forKey: .voted)
            ownVotes = try container.decodeIfPresent([Int].self, forKey: .ownVotes)
        }

        // Manual initializer for testing and previews
        init(id: String, expiresAt: Date?, expired: Bool, multiple: Bool, votesCount: Int, votersCount: Int?, options: [PollOption], voted: Bool?, ownVotes: [Int]?) {
            self.id = id
            self.expiresAt = expiresAt
            self.expired = expired
            self.multiple = multiple
            self.votesCount = votesCount
            self.votersCount = votersCount
            self.options = options
            self.voted = voted
            self.ownVotes = ownVotes
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case account
        case mediaAttachments = "media_attachments"
        case favouritesCount = "favourites_count"
        case reblogsCount = "reblogs_count"
        case repliesCount = "replies_count"
        case bookmarked
        case favourited
        case reblogged
        case reblog
        case quote
        case inReplyToID = "in_reply_to_id"
        case inReplyToAccountID = "in_reply_to_account_id"
        case spoilerText = "spoiler_text"
        case sensitive
        case visibility
        case language
        case uri
        case url
        case mentions
        case tags
        case emojis
        case card
        case poll
        case filtered
        case pinned
        case editedAt = "edited_at"
    }
    
    // Custom decoder to handle recursive structure
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        account = try container.decode(Account.self, forKey: .account)
        mediaAttachments = try container.decodeIfPresent([Attachment].self, forKey: .mediaAttachments) ?? []
        favouritesCount = try container.decodeIfPresent(Int.self, forKey: .favouritesCount) ?? 0
        reblogsCount = try container.decodeIfPresent(Int.self, forKey: .reblogsCount) ?? 0
        repliesCount = try container.decodeIfPresent(Int.self, forKey: .repliesCount) ?? 0
        bookmarked = try container.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
        favourited = try container.decodeIfPresent(Bool.self, forKey: .favourited) ?? false
        reblogged = try container.decodeIfPresent(Bool.self, forKey: .reblogged) ?? false
        
        // Decode recursive fields with decodeIfPresent to avoid throwing on frequent null payloads.
        // Keep try? fallback behavior so malformed nested payload does not fail whole status decode.
        reblog = (try? container.decodeIfPresent(Indirect<Status>.self, forKey: .reblog)) ?? nil
        quote = (try? container.decodeIfPresent(Quote.self, forKey: .quote)) ?? nil
        
        inReplyToID = try container.decodeIfPresent(String.self, forKey: .inReplyToID)
        inReplyToAccountID = try container.decodeIfPresent(String.self, forKey: .inReplyToAccountID)
        spoilerText = try container.decodeIfPresent(String.self, forKey: .spoilerText)
        sensitive = try container.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        mentions = try container.decodeIfPresent([Mention].self, forKey: .mentions)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        emojis = try container.decodeIfPresent([Emoji].self, forKey: .emojis)
        card = try container.decodeIfPresent(PreviewCard.self, forKey: .card)
        poll = try container.decodeIfPresent(Poll.self, forKey: .poll)
        filtered = try container.decodeIfPresent([FilterResult].self, forKey: .filtered)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(account, forKey: .account)
        try container.encode(mediaAttachments, forKey: .mediaAttachments)
        try container.encode(favouritesCount, forKey: .favouritesCount)
        try container.encode(reblogsCount, forKey: .reblogsCount)
        try container.encode(repliesCount, forKey: .repliesCount)
        try container.encode(bookmarked, forKey: .bookmarked)
        try container.encode(favourited, forKey: .favourited)
        try container.encode(reblogged, forKey: .reblogged)
        if let reblogValue = reblog {
            try container.encode(reblogValue.value, forKey: .reblog)
        }
        try container.encodeIfPresent(quote, forKey: .quote)
        try container.encodeIfPresent(inReplyToID, forKey: .inReplyToID)
        try container.encodeIfPresent(inReplyToAccountID, forKey: .inReplyToAccountID)
        try container.encodeIfPresent(spoilerText, forKey: .spoilerText)
        try container.encode(sensitive, forKey: .sensitive)
        try container.encodeIfPresent(visibility, forKey: .visibility)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(uri, forKey: .uri)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(mentions, forKey: .mentions)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(emojis, forKey: .emojis)
        try container.encodeIfPresent(card, forKey: .card)
        try container.encodeIfPresent(poll, forKey: .poll)
        try container.encodeIfPresent(filtered, forKey: .filtered)
        try container.encodeIfPresent(pinned, forKey: .pinned)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
    }
    
    // Computed property to determine status type
    var statusType: StatusType {
        if reblog != nil {
            return .reblog
        } else if quote != nil {
            return .quote
        } else if inReplyToID != nil {
            return .reply
        } else {
            return .normal
        }
    }
    
    // Get the actual status content (reblog's original status or self)
    var displayStatus: Status {
        return reblog?.value ?? self
    }
    
    // Get the account that posted this (reblogger or original author)
    var displayAccount: Account {
        return reblog != nil ? account : account
    }
    
    // Convenience initializer for creating Status instances manually (e.g., in Previews)
    init(
        id: String,
        content: String,
        createdAt: Date,
        account: Account,
        mediaAttachments: [Attachment],
        favouritesCount: Int,
        reblogsCount: Int,
        repliesCount: Int,
        bookmarked: Bool,
        favourited: Bool,
        reblogged: Bool,
        reblog: Indirect<Status>? = nil,
        quote: Quote? = nil,
        inReplyToID: String? = nil,
        inReplyToAccountID: String? = nil,
        spoilerText: String? = nil,
        sensitive: Bool = false,
        visibility: String? = nil,
        language: String? = nil,
        uri: String? = nil,
        url: URL? = nil,
        mentions: [Mention]? = nil,
        tags: [Tag]? = nil,
        emojis: [Emoji]? = nil,
        card: PreviewCard? = nil,
        poll: Poll? = nil,
        filtered: [FilterResult]?,
        pinned: Bool? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.account = account
        self.mediaAttachments = mediaAttachments
        self.favouritesCount = favouritesCount
        self.reblogsCount = reblogsCount
        self.repliesCount = repliesCount
        self.bookmarked = bookmarked
        self.favourited = favourited
        self.reblogged = reblogged
        self.reblog = reblog
        self.quote = quote
        self.inReplyToID = inReplyToID
        self.inReplyToAccountID = inReplyToAccountID
        self.spoilerText = spoilerText
        self.sensitive = sensitive
        self.visibility = visibility
        self.language = language
        self.uri = uri
        self.url = url
        self.mentions = mentions
        self.tags = tags
        self.emojis = emojis
        self.card = card
        self.poll = poll
        self.filtered = filtered
        self.pinned = pinned
        self.editedAt = editedAt
    }

    // Backward-compatible initializer for existing call sites that don't provide filter results.
    init(
        id: String,
        content: String,
        createdAt: Date,
        account: Account,
        mediaAttachments: [Attachment],
        favouritesCount: Int,
        reblogsCount: Int,
        repliesCount: Int,
        bookmarked: Bool,
        favourited: Bool,
        reblogged: Bool,
        reblog: Indirect<Status>? = nil,
        quote: Quote? = nil,
        inReplyToID: String? = nil,
        inReplyToAccountID: String? = nil,
        spoilerText: String? = nil,
        sensitive: Bool = false,
        visibility: String? = nil,
        language: String? = nil,
        uri: String? = nil,
        url: URL? = nil,
        mentions: [Mention]? = nil,
        tags: [Tag]? = nil,
        emojis: [Emoji]? = nil,
        card: PreviewCard? = nil,
        poll: Poll? = nil,
        pinned: Bool? = nil,
        editedAt: Date? = nil
    ) {
        self.init(
            id: id,
            content: content,
            createdAt: createdAt,
            account: account,
            mediaAttachments: mediaAttachments,
            favouritesCount: favouritesCount,
            reblogsCount: reblogsCount,
            repliesCount: repliesCount,
            bookmarked: bookmarked,
            favourited: favourited,
            reblogged: reblogged,
            reblog: reblog,
            quote: quote,
            inReplyToID: inReplyToID,
            inReplyToAccountID: inReplyToAccountID,
            spoilerText: spoilerText,
            sensitive: sensitive,
            visibility: visibility,
            language: language,
            uri: uri,
            url: url,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            card: card,
            poll: poll,
            filtered: nil,
            pinned: pinned,
            editedAt: editedAt
        )
    }
    
    /// Determine attachment type for display priority
    enum AttachmentType {
        case media      // Images, videos, audio
        case poll       // Poll
        case card       // Link preview card
        case none       // No attachments
    }
    
    /// Get the primary attachment type (for display priority)
    var attachmentType: AttachmentType {
        if !mediaAttachments.isEmpty {
            return .media
        } else if poll != nil {
            return .poll
        } else if card != nil {
            return .card
        } else {
            return .none
        }
    }
}

enum StatusType {
    case normal
    case reblog
    case quote
    case reply
}

extension Status {
    var allowsReblogAction: Bool {
        let visibility = displayStatus.visibility ?? visibility ?? "public"
        return displayStatus.reblogged || visibility == "public" || visibility == "unlisted"
    }

    func incorporatingDisplayStatusUpdate(_ updatedStatus: Status) -> Status {
        guard id == updatedStatus.id || displayStatus.id == updatedStatus.id else {
            return self
        }

        // Interaction responses may omit `pinned`. In that case the server did not report a
        // pin-state transition, so preserve the profile-context value instead of treating nil
        // as an unpin.
        let resolvedUpdate = updatedStatus.pinned == nil
            ? updatedStatus.withPinnedState(displayStatus.pinned)
            : updatedStatus

        guard id != updatedStatus.id else {
            return resolvedUpdate
        }

        return Status(
            id: id,
            content: content,
            createdAt: createdAt,
            account: account,
            mediaAttachments: mediaAttachments,
            favouritesCount: resolvedUpdate.favouritesCount,
            reblogsCount: resolvedUpdate.reblogsCount,
            repliesCount: resolvedUpdate.repliesCount,
            bookmarked: resolvedUpdate.bookmarked,
            favourited: resolvedUpdate.favourited,
            reblogged: resolvedUpdate.reblogged,
            reblog: reblog.map { _ in Indirect(resolvedUpdate) },
            quote: quote,
            inReplyToID: inReplyToID,
            inReplyToAccountID: inReplyToAccountID,
            spoilerText: spoilerText,
            sensitive: sensitive,
            visibility: visibility,
            language: language,
            uri: uri,
            url: url,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            card: card,
            poll: poll,
            filtered: filtered,
            pinned: pinned
        )
    }

    private func withPinnedState(_ pinned: Bool?) -> Status {
        Status(
            id: id,
            content: content,
            createdAt: createdAt,
            account: account,
            mediaAttachments: mediaAttachments,
            favouritesCount: favouritesCount,
            reblogsCount: reblogsCount,
            repliesCount: repliesCount,
            bookmarked: bookmarked,
            favourited: favourited,
            reblogged: reblogged,
            reblog: reblog,
            quote: quote,
            inReplyToID: inReplyToID,
            inReplyToAccountID: inReplyToAccountID,
            spoilerText: spoilerText,
            sensitive: sensitive,
            visibility: visibility,
            language: language,
            uri: uri,
            url: url,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            card: card,
            poll: poll,
            filtered: filtered,
            pinned: pinned,
            editedAt: editedAt
        )
    }

    /// Create a copy of this status with updated interaction fields
    /// For reblogs, updates are applied to the reblogged status
    func updating(
        favouritesCount: Int? = nil,
        reblogsCount: Int? = nil,
        repliesCount: Int? = nil,
        bookmarked: Bool? = nil,
        favourited: Bool? = nil,
        reblogged: Bool? = nil,
        poll: Poll? = nil
    ) -> Status {
        // If this is a reblog, update the nested reblog status
        if let nestedReblog = self.reblog {
            let updatedReblog = nestedReblog.value.updating(
                favouritesCount: favouritesCount,
                reblogsCount: reblogsCount,
                repliesCount: repliesCount,
                bookmarked: bookmarked,
                favourited: favourited,
                reblogged: reblogged,
                poll: poll
            )
            return Status(
                id: self.id,
                content: self.content,
                createdAt: self.createdAt,
                account: self.account,
                mediaAttachments: self.mediaAttachments,
                favouritesCount: self.favouritesCount,
                reblogsCount: self.reblogsCount,
                repliesCount: self.repliesCount,
                bookmarked: self.bookmarked,
                favourited: self.favourited,
                reblogged: reblogged ?? self.reblogged,
                reblog: Indirect(updatedReblog),
                quote: self.quote,
                inReplyToID: self.inReplyToID,
                inReplyToAccountID: self.inReplyToAccountID,
                spoilerText: self.spoilerText,
                sensitive: self.sensitive,
                visibility: self.visibility,
                language: self.language,
                uri: self.uri,
                url: self.url,
                mentions: self.mentions,
                tags: self.tags,
                emojis: self.emojis,
                card: self.card,
                poll: self.poll,
                filtered: self.filtered,
                pinned: self.pinned,
                editedAt: self.editedAt
            )
        }

        // Otherwise, update this status directly
        return Status(
            id: self.id,
            content: self.content,
            createdAt: self.createdAt,
            account: self.account,
            mediaAttachments: self.mediaAttachments,
            favouritesCount: favouritesCount ?? self.favouritesCount,
            reblogsCount: reblogsCount ?? self.reblogsCount,
            repliesCount: repliesCount ?? self.repliesCount,
            bookmarked: bookmarked ?? self.bookmarked,
            favourited: favourited ?? self.favourited,
            reblogged: reblogged ?? self.reblogged,
            reblog: self.reblog,
            quote: self.quote,
            inReplyToID: self.inReplyToID,
            inReplyToAccountID: self.inReplyToAccountID,
            spoilerText: self.spoilerText,
            sensitive: self.sensitive,
            visibility: self.visibility,
            language: self.language,
            uri: self.uri,
            url: self.url,
            mentions: self.mentions,
            tags: self.tags,
            emojis: self.emojis,
            card: self.card,
            poll: poll ?? self.poll,
            filtered: self.filtered,
            pinned: self.pinned,
            editedAt: self.editedAt
        )
    }
}

extension Status {
    var effectiveFilterResults: [FilterResult] {
        let status = displayStatus
        return status.filtered ?? []
    }

    var hasFilterWarning: Bool {
        !effectiveFilterResults.isEmpty
    }

    var primaryFilterWarningTitle: String? {
        normalizedFilterWarningTitles.first
    }

    var filterWarningBannerText: String? {
        let titles = normalizedFilterWarningTitles
        if titles.count == 1 {
            return titles[0]
        }
        if titles.count > 1 {
            return "Filtered by \(titles.count) rules"
        }
        return hasFilterWarning ? "Filtered" : nil
    }

    private var normalizedFilterWarningTitles: [String] {
        var uniqueTitles: [String] = []
        for rawTitle in effectiveFilterResults.compactMap(\.displayTitle) {
            let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !uniqueTitles.contains(trimmed) {
                uniqueTitles.append(trimmed)
            }
        }
        return uniqueTitles
    }
}
