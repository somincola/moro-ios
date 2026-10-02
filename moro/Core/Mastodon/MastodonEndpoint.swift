//
//  MastodonEndpoint.swift
//  moro
//
//  Provides REST endpoints metadata.
//

import Foundation

enum MastodonEndpoint {
    // OAuth & Instance
    case instance
    case instanceV2
    case createOAuthApp(clientName: String, redirectURIs: String, scopes: String, website: String?)
    case oauthToken(code: String, clientID: String, clientSecret: String, redirectURI: String)
    case oauthTokenClientCredentials(clientID: String, clientSecret: String, redirectURI: String, scopes: String)
    case registerAccount

    // Account
    case verifyCredentials
    case editableProfile
    case updateProfileDisplay
    case accountFeaturedTags(id: String)
    case ownFeaturedTags
    case featuredTagSuggestions
    case featureTag
    case unfeatureTag(id: String)
    case account(id: String)
    case accountLists(id: String)
    case accountLookup(acct: String)
    case accountStatuses(
        id: String, maxID: String?, sinceID: String?, limit: Int, excludeReplies: Bool,
        excludeReblogs: Bool, onlyMedia: Bool, pinned: Bool, tagged: String? = nil)
    case accountFollowers(id: String, maxID: String?, limit: Int)
    case accountFollowing(id: String, maxID: String?, limit: Int)
    case relationships(accountIDs: [String])
    case followAccount(id: String)
    case unfollowAccount(id: String)
    case authorizeFollowRequest(id: String)
    case rejectFollowRequest(id: String)
    case muteAccount(id: String)
    case unmuteAccount(id: String)
    case blockAccount(id: String)
    case unblockAccount(id: String)
    case updateAccountCredentials
    case deleteProfileAvatar
    case deleteProfileHeader

    // Timeline & Status
    case homeTimeline(maxID: String?, sinceID: String?, limit: Int)
    case publicTimeline(local: Bool, maxID: String?, sinceID: String?, minID: String?, limit: Int)
    case hashtagTimeline(tag: String, maxID: String?, sinceID: String?, limit: Int)
    case search(query: String, type: String?, resolve: Bool, limit: Int, offset: Int?)
    case tag(name: String)
    case followTag(name: String)
    case unfollowTag(name: String)
    case followedTags(maxID: String?, limit: Int)
    case trendsTags(limit: Int?)
    case trendsStatuses(limit: Int?)
    case directory(limit: Int?, offset: Int?, order: String?, local: Bool?)
    case announcements
    case dismissAnnouncement(id: String)
    case addAnnouncementReaction(id: String, name: String)
    case removeAnnouncementReaction(id: String, name: String)
    case status(id: String)
    case statusContext(id: String)
    case statusHistory(id: String)
    case statusSource(id: String)
    case statusTranslate(id: String, targetLanguage: String?)
    case translationLanguages
    case postStatus
    case editStatus(id: String)
    case scheduledStatuses(maxID: String?, sinceID: String?, limit: Int)
    case cancelScheduledStatus(id: String)
    case notifications(
        maxID: String?,
        sinceID: String?,
        limit: Int,
        types: [String],
        supportedTypes: [String]
    )
    case notificationUnreadCount
    case notification(id: String)
    case notificationPolicy
    case updateNotificationPolicy
    case notificationRequests(maxID: String?, limit: Int)
    case acceptNotificationRequest(id: String)
    case dismissNotificationRequest(id: String)
    case conversations(maxID: String?, sinceID: String?, limit: Int)
    case bookmarks(maxID: String?, sinceID: String?, limit: Int)
    case favourites(maxID: String?, sinceID: String?, limit: Int)
    case lists
    case createList
    case updateList(id: String)
    case deleteList(id: String)
    case listAccounts(id: String, maxID: String?, sinceID: String?, limit: Int)
    case addAccountsToList(id: String)
    case removeAccountsFromList(id: String)
    case listTimeline(id: String, maxID: String?, sinceID: String?, limit: Int)
    case pushSubscription
    case createPushSubscription
    case updatePushSubscription
    case deletePushSubscription
    case filters
    case createFilter
    case updateFilter(id: String)
    case deleteFilter(id: String)
    case createFilterKeyword(filterID: String)
    case updateFilterKeyword(keywordID: String)
    case deleteFilterKeyword(keywordID: String)
    case mutedAccounts(maxID: String?, sinceID: String?, limit: Int?)
    case blockedAccounts(maxID: String?, sinceID: String?, limit: Int?)
    case domainBlocks(maxID: String?, sinceID: String?, limit: Int?)
    case blockDomain(domain: String)
    case unblockDomain(domain: String)
    case readConversation(id: String)
    case deleteConversation(id: String)
    case favouriteStatus(id: String)
    case unfavouriteStatus(id: String)
    case reblogStatus(id: String)
    case unreblogStatus(id: String)
    case bookmarkStatus(id: String)
    case unbookmarkStatus(id: String)

    // Polls
    case votePoll(pollID: String, choices: [Int])

    // Media
    case uploadMedia
    case updateMedia(id: String)

    // Custom Emojis
    case customEmojis

    // Reports
    case report

    // Own Status Actions
    case deleteStatus(id: String)
    case pinStatus(id: String)
    case unpinStatus(id: String)

    // Markers (reading position)
    case markers(timelines: [String])
    case saveMarker

    var method: String {
        switch self {
        case .createOAuthApp, .oauthToken, .postStatus, .favouriteStatus, .unfavouriteStatus,
            .reblogStatus, .unreblogStatus, .bookmarkStatus, .unbookmarkStatus, .votePoll,
            .uploadMedia, .followAccount, .unfollowAccount, .muteAccount, .unmuteAccount,
            .blockAccount, .unblockAccount, .report, .pinStatus, .unpinStatus, .saveMarker,
            .readConversation, .createFilter, .createFilterKeyword, .blockDomain,
            .oauthTokenClientCredentials, .registerAccount, .createList, .addAccountsToList,
            .authorizeFollowRequest, .rejectFollowRequest, .dismissAnnouncement, .statusTranslate,
            .createPushSubscription, .followTag, .unfollowTag, .featureTag,
            .acceptNotificationRequest, .dismissNotificationRequest:
            return "POST"
        case .updateMedia, .updateAccountCredentials, .updateProfileDisplay,
            .updateNotificationPolicy:
            return "PATCH"
        case .updateFilter, .updatePushSubscription, .updateFilterKeyword, .updateList,
            .addAnnouncementReaction, .editStatus:
            return "PUT"
        case .deleteStatus, .deleteConversation, .deleteProfileAvatar, .deleteProfileHeader,
            .cancelScheduledStatus:
            return "DELETE"
        case .deleteFilter, .deletePushSubscription, .deleteFilterKeyword, .deleteList,
            .removeAccountsFromList, .removeAnnouncementReaction,
            .unblockDomain, .unfeatureTag:
            return "DELETE"
        default:
            return "GET"
        }
    }

    var path: String {
        switch self {
        case .instance:
            return "/api/v1/instance"
        case .instanceV2:
            return "/api/v2/instance"
        case .translationLanguages:
            return "/api/v1/instance/translation_languages"
        case .createOAuthApp:
            return "/api/v1/apps"
        case .oauthToken:
            return "/oauth/token"
        case .oauthTokenClientCredentials:
            return "/oauth/token"
        case .registerAccount:
            return "/api/v1/accounts"
        case .verifyCredentials:
            return "/api/v1/accounts/verify_credentials"
        case .editableProfile, .updateProfileDisplay:
            return "/api/v1/profile"
        case .accountFeaturedTags(let id):
            return "/api/v1/accounts/\(id)/featured_tags"
        case .ownFeaturedTags, .featureTag:
            return "/api/v1/featured_tags"
        case .featuredTagSuggestions:
            return "/api/v1/featured_tags/suggestions"
        case .unfeatureTag(let id):
            return "/api/v1/featured_tags/\(id)"
        case .account(let id):
            return "/api/v1/accounts/\(id)"
        case .accountLists(let id):
            return "/api/v1/accounts/\(id)/lists"
        case .accountLookup:
            return "/api/v1/accounts/lookup"
        case .accountStatuses(let id, _, _, _, _, _, _, _, _):
            return "/api/v1/accounts/\(id)/statuses"
        case .accountFollowers(let id, _, _):
            return "/api/v1/accounts/\(id)/followers"
        case .accountFollowing(let id, _, _):
            return "/api/v1/accounts/\(id)/following"
        case .relationships:
            return "/api/v1/accounts/relationships"
        case .followAccount(let id):
            return "/api/v1/accounts/\(id)/follow"
        case .unfollowAccount(let id):
            return "/api/v1/accounts/\(id)/unfollow"
        case .authorizeFollowRequest(let id):
            return "/api/v1/follow_requests/\(id)/authorize"
        case .rejectFollowRequest(let id):
            return "/api/v1/follow_requests/\(id)/reject"
        case .muteAccount(let id):
            return "/api/v1/accounts/\(id)/mute"
        case .unmuteAccount(let id):
            return "/api/v1/accounts/\(id)/unmute"
        case .blockAccount(let id):
            return "/api/v1/accounts/\(id)/block"
        case .unblockAccount(let id):
            return "/api/v1/accounts/\(id)/unblock"
        case .updateAccountCredentials:
            return "/api/v1/accounts/update_credentials"
        case .deleteProfileAvatar:
            return "/api/v1/profile/avatar"
        case .deleteProfileHeader:
            return "/api/v1/profile/header"
        case .homeTimeline:
            return "/api/v1/timelines/home"
        case .publicTimeline:
            return "/api/v1/timelines/public"
        case .hashtagTimeline(let tag, _, _, _):
            return "/api/v1/timelines/tag/\(tag)"
        case .search:
            return "/api/v2/search"
        case .tag(let name):
            return "/api/v1/tags/\(name)"
        case .followTag(let name):
            return "/api/v1/tags/\(name)/follow"
        case .unfollowTag(let name):
            return "/api/v1/tags/\(name)/unfollow"
        case .followedTags:
            return "/api/v1/followed_tags"
        case .trendsTags:
            return "/api/v1/trends/tags"
        case .trendsStatuses:
            return "/api/v1/trends/statuses"
        case .directory:
            return "/api/v1/directory"
        case .announcements:
            return "/api/v1/announcements"
        case .dismissAnnouncement(let id):
            return "/api/v1/announcements/\(id)/dismiss"
        case .addAnnouncementReaction(let id, let name):
            return "/api/v1/announcements/\(id)/reactions/\(name)"
        case .removeAnnouncementReaction(let id, let name):
            return "/api/v1/announcements/\(id)/reactions/\(name)"
        case .status(let id):
            return "/api/v1/statuses/\(id)"
        case .statusContext(let id):
            return "/api/v1/statuses/\(id)/context"
        case .statusHistory(let id):
            return "/api/v1/statuses/\(id)/history"
        case .statusSource(let id):
            return "/api/v1/statuses/\(id)/source"
        case .statusTranslate(let id, _):
            return "/api/v1/statuses/\(id)/translate"
        case .postStatus:
            return "/api/v1/statuses"
        case .editStatus(let id):
            return "/api/v1/statuses/\(id)"
        case .scheduledStatuses:
            return "/api/v1/scheduled_statuses"
        case .cancelScheduledStatus(let id):
            return "/api/v1/scheduled_statuses/\(id)"
        case .notifications:
            return "/api/v1/notifications"
        case .notification(let id):
            return "/api/v1/notifications/\(id)"
        case .notificationUnreadCount:
            return "/api/v1/notifications/unread_count"
        case .notificationPolicy, .updateNotificationPolicy:
            return "/api/v2/notifications/policy"
        case .notificationRequests:
            return "/api/v1/notifications/requests"
        case .acceptNotificationRequest(let id):
            return "/api/v1/notifications/requests/\(id)/accept"
        case .dismissNotificationRequest(let id):
            return "/api/v1/notifications/requests/\(id)/dismiss"
        case .conversations:
            return "/api/v1/conversations"
        case .bookmarks:
            return "/api/v1/bookmarks"
        case .favourites:
            return "/api/v1/favourites"
        case .lists, .createList:
            return "/api/v1/lists"
        case .updateList(let id), .deleteList(let id):
            return "/api/v1/lists/\(id)"
        case .listAccounts(let id, _, _, _), .addAccountsToList(let id), .removeAccountsFromList(let id):
            return "/api/v1/lists/\(id)/accounts"
        case .listTimeline(let id, _, _, _):
            return "/api/v1/timelines/list/\(id)"
        case .pushSubscription, .createPushSubscription, .updatePushSubscription,
            .deletePushSubscription:
            return "/api/v1/push/subscription"
        case .filters, .createFilter:
            return "/api/v2/filters"
        case .updateFilter(let id), .deleteFilter(let id):
            return "/api/v2/filters/\(id)"
        case .createFilterKeyword(let filterID):
            return "/api/v2/filters/\(filterID)/keywords"
        case .updateFilterKeyword(let keywordID), .deleteFilterKeyword(let keywordID):
            return "/api/v2/filters/keywords/\(keywordID)"
        case .mutedAccounts:
            return "/api/v1/mutes"
        case .blockedAccounts:
            return "/api/v1/blocks"
        case .domainBlocks, .blockDomain, .unblockDomain:
            return "/api/v1/domain_blocks"
        case .readConversation(let id):
            return "/api/v1/conversations/\(id)/read"
        case .deleteConversation(let id):
            return "/api/v1/conversations/\(id)"
        case .favouriteStatus(let id):
            return "/api/v1/statuses/\(id)/favourite"
        case .unfavouriteStatus(let id):
            return "/api/v1/statuses/\(id)/unfavourite"
        case .reblogStatus(let id):
            return "/api/v1/statuses/\(id)/reblog"
        case .unreblogStatus(let id):
            return "/api/v1/statuses/\(id)/unreblog"
        case .bookmarkStatus(let id):
            return "/api/v1/statuses/\(id)/bookmark"
        case .unbookmarkStatus(let id):
            return "/api/v1/statuses/\(id)/unbookmark"
        case .votePoll(let pollID, _):
            return "/api/v1/polls/\(pollID)/votes"
        case .uploadMedia:
            return "/api/v2/media"
        case .updateMedia(let id):
            return "/api/v1/media/\(id)"
        case .customEmojis:
            return "/api/v1/custom_emojis"
        case .report:
            return "/api/v1/reports"
        case .deleteStatus(let id):
            return "/api/v1/statuses/\(id)"
        case .pinStatus(let id):
            return "/api/v1/statuses/\(id)/pin"
        case .unpinStatus(let id):
            return "/api/v1/statuses/\(id)/unpin"
        case .markers, .saveMarker:
            return "/api/v1/markers"
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .homeTimeline(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .publicTimeline(let local, let maxID, let sinceID, let minID, let limit):
            return [
                URLQueryItem(name: "local", value: local ? "true" : "false"),
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                minID.map { URLQueryItem(name: "min_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .hashtagTimeline(_, let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .search(let query, let type, let resolve, let limit, let offset):
            return [
                URLQueryItem(name: "q", value: query),
                type.map { URLQueryItem(name: "type", value: $0) },
                URLQueryItem(name: "resolve", value: resolve ? "true" : "false"),
                URLQueryItem(name: "limit", value: "\(limit)"),
                offset.map { URLQueryItem(name: "offset", value: "\($0)") },
            ].compactMap { $0 }
        case .followedTags(let maxID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .trendsTags(let limit):
            return [
                limit.map { URLQueryItem(name: "limit", value: "\($0)") }
            ].compactMap { $0 }
        case .trendsStatuses(let limit):
            return [
                limit.map { URLQueryItem(name: "limit", value: "\($0)") }
            ].compactMap { $0 }
        case .directory(let limit, let offset, let order, let local):
            return [
                limit.map { URLQueryItem(name: "limit", value: "\($0)") },
                offset.map { URLQueryItem(name: "offset", value: "\($0)") },
                order.map { URLQueryItem(name: "order", value: $0) },
                local.map { URLQueryItem(name: "local", value: $0 ? "true" : "false") },
            ].compactMap { $0 }
        case .accountStatuses(
            _, let maxID, let sinceID, let limit, let excludeReplies, let excludeReblogs,
            let onlyMedia, let pinned, let tagged):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "exclude_replies", value: excludeReplies ? "true" : "false"),
                URLQueryItem(name: "exclude_reblogs", value: excludeReblogs ? "true" : "false"),
                onlyMedia ? URLQueryItem(name: "only_media", value: "true") : nil,
                pinned ? URLQueryItem(name: "pinned", value: "true") : nil,
                tagged.map { URLQueryItem(name: "tagged", value: $0) },
            ].compactMap { $0 }
        case .accountLookup(let acct):
            return [URLQueryItem(name: "acct", value: acct)]
        case .accountFollowers(_, let maxID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .accountFollowing(_, let maxID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .relationships(let accountIDs):
            return accountIDs.map { URLQueryItem(name: "id[]", value: $0) }
        case .followAccount, .unfollowAccount:
            // Query items will be handled in MastodonClient for followAccount (reblogs, notify)
            return nil
        case .notifications(let maxID, let sinceID, let limit, let types, let supportedTypes):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
                + types.map { URLQueryItem(name: "types[]", value: $0) }
                + supportedTypes.map { URLQueryItem(name: "supported_types[]", value: $0) }
        case .notificationUnreadCount:
            return nil
        case .notificationRequests(let maxID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .scheduledStatuses(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)")
            ].compactMap { $0 }
        case .statusTranslate(_, let targetLanguage):
            return [
                targetLanguage.map { URLQueryItem(name: "lang", value: $0) }
            ].compactMap { $0 }
        case .conversations(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)"),
            ].compactMap { $0 }
        case .bookmarks(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)")
            ].compactMap { $0 }
        case .favourites(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)")
            ].compactMap { $0 }
        case .listTimeline(_, let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)")
            ].compactMap { $0 }
        case .listAccounts(_, let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                URLQueryItem(name: "limit", value: "\(limit)")
            ].compactMap { $0 }
        case .mutedAccounts(let maxID, let sinceID, let limit),
            .blockedAccounts(let maxID, let sinceID, let limit),
            .domainBlocks(let maxID, let sinceID, let limit):
            return [
                maxID.map { URLQueryItem(name: "max_id", value: $0) },
                sinceID.map { URLQueryItem(name: "since_id", value: $0) },
                limit.map { URLQueryItem(name: "limit", value: "\($0)") }
            ].compactMap { $0 }
        case .blockDomain(let domain), .unblockDomain(let domain):
            return [
                URLQueryItem(name: "domain", value: domain)
            ]
        case .markers(let timelines):
            return timelines.map { URLQueryItem(name: "timeline[]", value: $0) }
        default:
            return nil
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .instance, .instanceV2, .createOAuthApp, .oauthToken, .oauthTokenClientCredentials:
            return false
        default:
            return true
        }
    }
}
