//
//  MastodonAPI.swift
//  moro
//
//  Contract for Mastodon endpoints used in MVP.
//

import Foundation

/// Post visibility. Wire values are public / unlisted / private / direct;
/// `.followers` keeps a clearer Swift name while mapping to the API's "private".
/// `_other` preserves any value the server introduces in future so decoding never
/// fails and the original value round-trips on edit.
enum MastodonVisibility: RawRepresentable, Codable, Hashable {
    case `public`
    case unlisted
    case followers
    case direct
    case _other(String)

    init?(rawValue: String) {
        switch rawValue {
        case "public": self = .public
        case "unlisted": self = .unlisted
        case "private": self = .followers
        case "direct": self = .direct
        default: self = ._other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .public: return "public"
        case .unlisted: return "unlisted"
        case .followers: return "private"
        case .direct: return "direct"
        case ._other(let value): return value
        }
    }
}

enum MastodonQuoteApprovalPolicy: String, Encodable {
    case anyone = "public"
    case followers
    case nobody
}

enum MastodonSearchType: String, Codable {
    case accounts
    case statuses
    case hashtags
}

enum MastodonDirectoryOrder: String, Codable {
    case active
    case new
}

struct StatusPollPayload: Codable, Equatable {
    let options: [String]
    let expiresIn: Int
    let multiple: Bool
    let hideTotals: Bool?

    enum CodingKeys: String, CodingKey {
        case options
        case expiresIn = "expires_in"
        case multiple
        case hideTotals = "hide_totals"
    }
}

enum StatusPublishResult {
    case posted(Status)
    case scheduled(ScheduledStatus)
}

/// The exact creation payload, shared by transport encoding and retry identity.
struct StatusPublishPayload: Encodable {
    let status: String
    let visibility: MastodonVisibility
    let mediaIDs: [String]?
    let inReplyToID: String?
    let spoilerText: String?
    let sensitive: Bool?
    let quoteID: String?
    let quoteApprovalPolicy: MastodonQuoteApprovalPolicy?
    let language: String?
    let scheduledAt: String?
    let poll: StatusPollPayload?

    enum CodingKeys: String, CodingKey {
        case status, visibility, sensitive, language, poll
        case mediaIDs = "media_ids"
        case inReplyToID = "in_reply_to_id"
        case spoilerText = "spoiler_text"
        case quoteID = "quoted_status_id"
        case quoteApprovalPolicy = "quote_approval_policy"
        case scheduledAt = "scheduled_at"
    }
}

protocol MastodonAPI {
    func fetchTimelinePage(
        timeline: TimelineType, maxID: String?, sinceID: String?, limit: Int
    ) async throws -> TimelinePage
    /// Stable identifier for instance-scoped metadata caches.
    /// Test doubles and clients without a stable server identity may keep the default `nil`.
    var instanceMetadataCacheKey: String? { get }

    // OAuth & Instance
    func fetchInstance() async throws -> MastodonInstance
    func fetchInstanceV2() async throws -> MastodonInstanceV2
    func createOAuthApp(clientName: String, redirectURIs: String, scopes: String, website: String?)
        async throws -> OAuthApp
    func exchangeOAuthToken(
        code: String, clientID: String, clientSecret: String, redirectURI: String,
        codeVerifier: String?
    ) async throws -> OAuthTokenResponse
    func verifyCredentials() async throws -> Account

    // Editable profile data and curation
    func fetchEditableProfile() async throws -> EditableProfile
    func updateProfileDisplay(_ update: ProfileDisplayUpdate) async throws -> EditableProfile
    func fetchAccountFeaturedTags(accountID: String) async throws -> [FeaturedTag]
    func fetchOwnFeaturedTags() async throws -> [FeaturedTag]
    func fetchFeaturedTagSuggestions() async throws -> [SearchTag]
    func featureTag(name: String) async throws -> FeaturedTag
    func unfeatureTag(id: String) async throws
    func fetchAccountStatuses(
        id: String, maxID: String?, sinceID: String?, limit: Int, excludeReplies: Bool,
        excludeReblogs: Bool, onlyMedia: Bool, pinned: Bool, tagged: String?
    ) async throws -> [Status]

    // Account
    func fetchAccount(id: String) async throws -> Account
    func lookupAccount(acct: String) async throws -> Account
    func fetchAccountStatuses(
        id: String, maxID: String?, sinceID: String?, limit: Int, excludeReplies: Bool,
        excludeReblogs: Bool, onlyMedia: Bool, pinned: Bool
    ) async throws -> [Status]
    func fetchAccountFollowers(id: String, maxID: String?, limit: Int) async throws -> [Account]
    func fetchAccountFollowing(id: String, maxID: String?, limit: Int) async throws -> [Account]
    func fetchRelationships(accountIDs: [String]) async throws -> [Relationship]
    func followAccount(id: String, reblogs: Bool?, notify: Bool?) async throws -> Relationship
    func unfollowAccount(id: String) async throws -> Relationship
    func authorizeFollowRequest(accountID: String) async throws -> Relationship
    func rejectFollowRequest(accountID: String) async throws -> Relationship
    func muteAccount(id: String) async throws -> Relationship
    func unmuteAccount(id: String) async throws -> Relationship
    func blockAccount(id: String) async throws -> Relationship
    func unblockAccount(id: String) async throws -> Relationship
    func updateAccountCredentials(
        discoverable: Bool?,
        locked: Bool?,
        indexable: Bool?,
        hideCollections: Bool?,
        privacy: String?
    ) async throws -> Account
    func updateAccountProfile(
        displayName: String?,
        note: String?,
        avatar: AccountProfileImageUpload?,
        header: AccountProfileImageUpload?,
        removeAvatar: Bool,
        removeHeader: Bool,
        fields: [AccountField]?
    ) async throws -> Account

    // Timeline & Status
    func fetchHomeTimeline(maxID: String?, sinceID: String?, limit: Int) async throws -> [Status]
    func fetchPublicTimeline(
        local: Bool, maxID: String?, sinceID: String?, minID: String?, limit: Int
    ) async throws -> [Status]
    func fetchHashtagTimeline(tag: String, maxID: String?, sinceID: String?, limit: Int)
        async throws -> [Status]
    func search(
        query: String,
        type: MastodonSearchType?,
        resolve: Bool,
        limit: Int,
        offset: Int?
    ) async throws -> SearchResults
    func fetchTag(name: String) async throws -> SearchTag
    func setTagFollowed(name: String, followed: Bool) async throws -> SearchTag
    func fetchFollowedTags(maxID: String?, limit: Int) async throws -> FollowedTagsPage
    func fetchTrendingTags(limit: Int?) async throws -> [SearchTag]
    func fetchTrendingStatuses(limit: Int?) async throws -> [Status]
    func fetchDirectoryAccounts(
        limit: Int?,
        offset: Int?,
        order: MastodonDirectoryOrder?,
        local: Bool?
    ) async throws -> [Account]
    func fetchAnnouncements() async throws -> [Announcement]
    func dismissAnnouncement(id: String) async throws
    func addAnnouncementReaction(id: String, name: String) async throws
    func removeAnnouncementReaction(id: String, name: String) async throws
    func fetchStatusDetail(id: String) async throws -> Status
    func fetchStatusContext(id: String) async throws -> StatusContext
    func fetchStatusHistory(id: String) async throws -> [StatusEditHistoryItem]
    func fetchStatusSource(id: String) async throws -> StatusSource
    func translateStatus(id: String, targetLanguage: String?) async throws -> StatusTranslationPayload
    /// Source → supported-target map from the instance translation backend.
    func fetchTranslationLanguages() async throws -> [String: [String]]
    func fetchScheduledStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [ScheduledStatus]
    func cancelScheduledStatus(id: String) async throws
    func fetchNotifications(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [NotificationItem]
    func fetchNotification(id: String) async throws -> NotificationItem
    func fetchUnreadNotificationCount() async throws -> Int
    func fetchConversations(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Conversation]
    func fetchConversationsPage(maxID: String?, limit: Int) async throws -> ConversationsPage
    func fetchBookmarkedPage(maxID: String?, limit: Int) async throws -> BookmarkedStatusesPage
    func fetchBookmarkedStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    func fetchFavouritedStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    func fetchLists() async throws -> [MastodonList]
    /// Lists owned by the user that contain the given account.
    func fetchAccountLists(accountID: String) async throws -> [MastodonList]
    func createList(title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    func updateList(id: String, title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    func deleteList(id: String) async throws
    func fetchListAccounts(listID: String, maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Account]
    func addAccountsToList(listID: String, accountIDs: [String]) async throws
    func removeAccountsFromList(listID: String, accountIDs: [String]) async throws
    func fetchListTimeline(id: String, maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    func fetchPushSubscription() async throws -> PushSubscription
    func createPushSubscription(
        endpoint: String, p256dh: String, auth: String,
        alerts: PushSubscription.Alerts, policy: String?
    ) async throws -> PushSubscription
    func updatePushSubscription(alerts: PushSubscription.Alerts, policy: String?) async throws
        -> PushSubscription
    func deletePushSubscription() async throws
    func fetchFilters() async throws -> [ServerFilter]
    func createFilter(
        title: String,
        keyword: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter
    func updateFilter(
        id: String,
        title: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter
    func deleteFilter(id: String) async throws
    func addFilterKeyword(
        filterID: String,
        keyword: String,
        wholeWord: Bool
    ) async throws -> ServerFilter.Keyword
    func updateFilterKeyword(
        keywordID: String,
        keyword: String,
        wholeWord: Bool
    ) async throws -> ServerFilter.Keyword
    func deleteFilterKeyword(keywordID: String) async throws
    func fetchMutedAccounts(maxID: String?, sinceID: String?, limit: Int?) async throws -> [Account]
    func fetchBlockedAccounts(maxID: String?, sinceID: String?, limit: Int?) async throws -> [Account]
    func fetchDomainBlocks(maxID: String?, sinceID: String?, limit: Int?) async throws -> [String]
    func blockDomain(_ domain: String) async throws
    func unblockDomain(_ domain: String) async throws
    func markConversationRead(id: String) async throws -> Conversation
    func deleteConversation(id: String) async throws

    // Interactions
    func favouriteStatus(id: String) async throws -> Status
    func unfavouriteStatus(id: String) async throws -> Status
    func reblogStatus(id: String) async throws -> Status
    func unreblogStatus(id: String) async throws -> Status
    func bookmarkStatus(id: String) async throws -> Status
    func unbookmarkStatus(id: String) async throws -> Status

    // Polls
    func votePoll(pollID: String, choices: [Int]) async throws -> Status.Poll

    // Media
    func uploadMedia(data: Data, mimeType: String, description: String?) async throws
        -> Status.Attachment
    func updateMedia(id: String, description: String?, focus: String?) async throws
        -> Status.Attachment

    // Custom Emojis
    func fetchCustomEmojis() async throws -> [CustomEmoji]

    // Extended Post Status
    func postStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status
    func editStatus(
        id: String,
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status
    func publishStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        quoteApprovalPolicy: MastodonQuoteApprovalPolicy?,
        language: String?,
        scheduledAt: Date?,
        poll: StatusPollPayload?,
        idempotencyKey: String?
    ) async throws -> StatusPublishResult

    // Reports
    func report(accountID: String, statusIDs: [String], comment: String) async throws
        -> ReportResponse

    // Own Status Actions
    func deleteStatus(id: String) async throws
    func pinStatus(id: String) async throws -> Status
    func unpinStatus(id: String) async throws -> Status

    // Markers (reading position)
    func fetchMarkers(timelines: [MarkerTimeline]) async throws -> Marker
    func saveMarker(home: String?, notifications: String?) async throws -> Marker
}

extension MastodonAPI {
    func fetchConversationsPage(maxID: String?, limit: Int) async throws -> ConversationsPage {
        let conversations = try await fetchConversations(maxID: maxID, sinceID: nil, limit: limit)
        return ConversationsPage(conversations: conversations, nextMaxID: nil)
    }

    func fetchTimelinePage(
        timeline: TimelineType, maxID: String?, sinceID: String?, limit: Int
    ) async throws -> TimelinePage {
        let statuses: [Status]
        switch timeline {
        case .home:
            statuses = try await fetchHomeTimeline(maxID: maxID, sinceID: sinceID, limit: limit)
        case .local, .federated:
            statuses = try await fetchPublicTimeline(local: timeline == .local,
                maxID: maxID, sinceID: sinceID, minID: nil, limit: limit)
        case .list(let id, _):
            statuses = try await fetchListTimeline(id: id, maxID: maxID, sinceID: sinceID, limit: limit)
        }
        return TimelinePage(statuses: statuses)
    }
    func fetchNotification(id: String) async throws -> NotificationItem {
        throw APIError.http(statusCode: 501, data: nil)
    }
    var instanceMetadataCacheKey: String? { nil }
    func fetchEditableProfile() async throws -> EditableProfile {
        try EditableProfile.credentials(await verifyCredentials())
    }
    func updateProfileDisplay(_ update: ProfileDisplayUpdate) async throws -> EditableProfile {
        throw ProfileEditingError.unsupported
    }
    func fetchAccountFeaturedTags(accountID: String) async throws -> [FeaturedTag] {
        throw ProfileEditingError.unsupported
    }
    func fetchOwnFeaturedTags() async throws -> [FeaturedTag] { throw ProfileEditingError.unsupported }
    func fetchFeaturedTagSuggestions() async throws -> [SearchTag] { throw ProfileEditingError.unsupported }
    func featureTag(name: String) async throws -> FeaturedTag { throw ProfileEditingError.unsupported }
    func unfeatureTag(id: String) async throws { throw ProfileEditingError.unsupported }
    func fetchAccountStatuses(
        id: String, maxID: String?, sinceID: String?, limit: Int, excludeReplies: Bool,
        excludeReblogs: Bool, onlyMedia: Bool, pinned: Bool, tagged: String?
    ) async throws -> [Status] {
        guard tagged == nil else { throw ProfileEditingError.unsupported }
        return try await fetchAccountStatuses(id: id, maxID: maxID, sinceID: sinceID, limit: limit,
            excludeReplies: excludeReplies, excludeReblogs: excludeReblogs, onlyMedia: onlyMedia, pinned: pinned)
    }
}

struct AccountProfileImageUpload {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct NotificationItem: Identifiable, Codable {
    let id: String
    let type: String
    let groupKey: String?
    let createdAt: Date
    let account: Account
    let status: Status?
    let fallback: NotificationFallback?
    let collection: NotificationCollectionSummary?

    init(
        id: String,
        type: String,
        groupKey: String? = nil,
        createdAt: Date,
        account: Account,
        status: Status?,
        fallback: NotificationFallback? = nil,
        collection: NotificationCollectionSummary? = nil
    ) {
        self.id = id
        self.type = type
        self.groupKey = groupKey
        self.createdAt = createdAt
        self.account = account
        self.status = status
        self.fallback = fallback
        self.collection = collection
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case groupKey = "group_key"
        case createdAt = "created_at"
        case account
        case status
        case fallback
        case collection
    }
}

struct NotificationFallback: Codable, Equatable {
    let title: String
    let summary: String?
    let details: String?
}

struct NotificationCollectionSummary: Codable, Equatable {
    let id: String?
    let accountID: String?
    let name: String?
    let description: String?
    let itemCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case name
        case description
        case itemCount = "item_count"
    }
}

struct SearchResults: Codable {
    let accounts: [Account]
    let statuses: [Status]
    let hashtags: [SearchTag]

    init(
        accounts: [Account] = [],
        statuses: [Status] = [],
        hashtags: [SearchTag] = []
    ) {
        self.accounts = accounts
        self.statuses = statuses
        self.hashtags = hashtags
    }

    private enum CodingKeys: String, CodingKey {
        case accounts
        case statuses
        case hashtags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        statuses = try container.decodeIfPresent([Status].self, forKey: .statuses) ?? []
        hashtags = try container.decodeIfPresent([SearchTag].self, forKey: .hashtags) ?? []
    }
}

struct SearchTag: Codable, Hashable, Identifiable {
    let name: String
    let url: URL
    let history: [SearchTagHistory]?

    let following: Bool?

    init(name: String, url: URL, history: [SearchTagHistory]?, following: Bool? = nil) {
        self.name = name
        self.url = url
        self.history = history
        self.following = following
    }

    var id: String { name.lowercased() }
}

struct BookmarkedStatusesPage {
    let statuses: [Status]
    let nextMaxID: String?
}

struct FollowedTagsPage {
    let tags: [SearchTag]
    /// Relationship cursor from the response Link header, never the tag id.
    let nextMaxID: String?
}

struct SearchTagHistory: Codable, Hashable {
    let day: String
    let uses: String
    let accounts: String
}

/// Custom emoji from Mastodon instance
struct CustomEmoji: Identifiable, Codable, Hashable {
    let shortcode: String
    let url: URL
    let staticURL: URL
    let visibleInPicker: Bool
    let category: String?

    var id: String { shortcode }

    enum CodingKeys: String, CodingKey {
        case shortcode
        case url
        case staticURL = "static_url"
        case visibleInPicker = "visible_in_picker"
        case category
    }
}

/// Relationship between accounts
struct Relationship: Identifiable, Codable {
    let id: String
    let following: Bool
    let followedBy: Bool
    let blocking: Bool
    let blockedBy: Bool
    let muting: Bool
    let mutingNotifications: Bool
    let requested: Bool
    let domainBlocking: Bool
    let endorsed: Bool
    let notifying: Bool  // Whether notifications are enabled for this user
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case following
        case followedBy = "followed_by"
        case blocking
        case blockedBy = "blocked_by"
        case muting
        case mutingNotifications = "muting_notifications"
        case requested
        case domainBlocking = "domain_blocking"
        case endorsed
        case notifying
        case note
    }
}

/// Report response from Mastodon API
struct ReportResponse: Codable {
    let id: String
    let actionTaken: Bool?
    let actionTakenAt: Date?
    let category: String?
    let comment: String?
    let forwarded: Bool?
    let statusIds: [String]?
    let ruleIds: [String]?
    let targetAccount: Account?

    enum CodingKeys: String, CodingKey {
        case id
        case actionTaken = "action_taken"
        case actionTakenAt = "action_taken_at"
        case category
        case comment
        case forwarded
        case statusIds = "status_ids"
        case ruleIds = "rule_ids"
        case targetAccount = "target_account"
    }
}
