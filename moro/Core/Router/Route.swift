//
//  Route.swift
//  moro
//
//  Defines all navigable routes in the app.
//

import Foundation

struct RouteMediaGalleryItem: Hashable {
    let id: String
    let url: URL
    let altText: String?
}

enum ProfileConnectionKind: String, Hashable {
    case following
    case followers
}

/// All navigable routes in the application
/// Provides explicit, type-safe route definitions.
enum Route: Hashable {
    // MARK: - Timeline & Feed

    /// Navigate to status detail (thread view)
    case statusDetail(Status)

    /// Navigate to hashtag timeline
    case hashtag(String)

    /// Navigate to search/discovery
    case search(query: String?, scope: Int = 1)

    case savedSearches

    /// Resolve a handle-like acct string to a real account profile.
    case accountLookup(String)

    /// Navigate to announcement list
    case announcements

    /// Navigate to announcement detail
    case announcementDetail(Announcement)

    // MARK: - User Profile

    /// Navigate to mentioned user's profile
    case mentionUser(Status.Mention)

    /// Navigate to user profile by account
    case userProfile(Account)

    /// Navigate to the accounts this profile follows or is followed by.
    case profileConnections(accountID: String, kind: ProfileConnectionKind)

    // MARK: - Media

    /// Navigate to media preview
    case mediaPreview(url: URL)

    /// Navigate to in-app web preview for external links.
    case webPreview(URL)

    /// Navigate to media gallery preview with multiple images.
    case mediaGallery(items: [RouteMediaGalleryItem], initialIndex: Int)

    /// Navigate to direct-message conversation detail
    case conversationDetail(Conversation)

    // MARK: - Content Management

    /// Navigate to bookmarks list
    case bookmarks

    /// Navigate to favourites (liked statuses) list
    case favourites

    /// Navigate to lists management page
    case lists

    case followedTopics

    /// Navigate to scheduled statuses list
    case scheduledStatuses

    /// Navigate to current instance details
    case instanceDetails

    /// Navigate to current account edit profile page.
    case editProfile

    // MARK: - Hashable Conformance

    func hash(into hasher: inout Hasher) {
        switch self {
        case .statusDetail(let status):
            hasher.combine("statusDetail")
            hasher.combine(status.id)
        case .hashtag(let tag):
            hasher.combine("hashtag")
            hasher.combine(tag)
        case .search(let query, let scope):
            hasher.combine("search")
            hasher.combine(query)
            hasher.combine(scope)
        case .savedSearches:
            hasher.combine("savedSearches")
        case .accountLookup(let acct):
            hasher.combine("accountLookup")
            hasher.combine(acct)
        case .announcements:
            hasher.combine("announcements")
        case .announcementDetail(let announcement):
            hasher.combine("announcementDetail")
            hasher.combine(announcement.id)
        case .mentionUser(let mention):
            hasher.combine("mentionUser")
            hasher.combine(mention.id)
        case .userProfile(let account):
            hasher.combine("userProfile")
            hasher.combine(account.id)
        case .profileConnections(let accountID, let kind):
            hasher.combine("profileConnections")
            hasher.combine(accountID)
            hasher.combine(kind)
        case .mediaPreview(let url):
            hasher.combine("mediaPreview")
            hasher.combine(url)
        case .webPreview(let url):
            hasher.combine("webPreview")
            hasher.combine(url)
        case .mediaGallery(let items, let initialIndex):
            hasher.combine("mediaGallery")
            hasher.combine(items)
            hasher.combine(initialIndex)
        case .conversationDetail(let conversation):
            hasher.combine("conversationDetail")
            hasher.combine(conversation.id)
        case .bookmarks:
            hasher.combine("bookmarks")
        case .favourites:
            hasher.combine("favourites")
        case .followedTopics:
            hasher.combine("followedTopics")
        case .lists:
            hasher.combine("lists")
        case .scheduledStatuses:
            hasher.combine("scheduledStatuses")
        case .instanceDetails:
            hasher.combine("instanceDetails")
        case .editProfile:
            hasher.combine("editProfile")
        }
    }

    static func == (lhs: Route, rhs: Route) -> Bool {
        switch (lhs, rhs) {
        case (.statusDetail(let l), .statusDetail(let r)):
            return l.id == r.id
        case (.hashtag(let l), .hashtag(let r)):
            return l == r
        case (.search(let l, let ls), .search(let r, let rs)):
            return l == r && ls == rs
        case (.savedSearches, .savedSearches):
            return true
        case (.accountLookup(let l), .accountLookup(let r)):
            return l == r
        case (.announcements, .announcements):
            return true
        case (.announcementDetail(let l), .announcementDetail(let r)):
            return l.id == r.id
        case (.mentionUser(let l), .mentionUser(let r)):
            return l.id == r.id
        case (.userProfile(let l), .userProfile(let r)):
            return l.id == r.id
        case (.profileConnections(let lAccountID, let lKind), .profileConnections(let rAccountID, let rKind)):
            return lAccountID == rAccountID && lKind == rKind
        case (.mediaPreview(let l), .mediaPreview(let r)):
            return l == r
        case (.webPreview(let l), .webPreview(let r)):
            return l == r
        case (.mediaGallery(let lItems, let lInitialIndex), .mediaGallery(let rItems, let rInitialIndex)):
            return lItems == rItems && lInitialIndex == rInitialIndex
        case (.conversationDetail(let l), .conversationDetail(let r)):
            return l.id == r.id
        case (.bookmarks, .bookmarks):
            return true
        case (.favourites, .favourites):
            return true
        case (.followedTopics, .followedTopics):
            return true
        case (.lists, .lists):
            return true
        case (.scheduledStatuses, .scheduledStatuses):
            return true
        case (.instanceDetails, .instanceDetails):
            return true
        case (.editProfile, .editProfile):
            return true
        default:
            return false
        }
    }
}
