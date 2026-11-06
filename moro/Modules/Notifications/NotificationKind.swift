//
//  NotificationKind.swift
//  moro
//
//  Central notification type and presentation mapping.
//

import Foundation

nonisolated enum NotificationLayoutFamily: Equatable {
    case postAction
    case personEvent
    case contentEvent
    case systemEvent
}

nonisolated enum NotificationFilterCategory: Equatable {
    case mentions
    case interactions
    case follows
    case updates
    case allOnly
}

nonisolated enum NotificationAccent: Equatable {
    case favourite
    case reblog
    case quote
    case standard
    case warning
}

nonisolated struct NotificationPresentationDescriptor: Equatable {
    let layoutFamily: NotificationLayoutFamily
    let filterCategory: NotificationFilterCategory
    let iconName: String
    let accent: NotificationAccent
    let showsStatusPreview: Bool
    let canGroupActors: Bool
}

nonisolated enum NotificationKind: Hashable {
    case follow
    case followRequest
    case mention
    case reblog
    case favourite
    case quote
    case quotedUpdate
    case poll
    case status
    case update
    case adminSignUp
    case adminReport
    case severedRelationships
    case moderationWarning
    case addedToCollection
    case collectionUpdate
    case unknown(String)

    /// Types this client renders natively. Sent to Mastodon so newer servers can
    /// include a localized fallback payload for future, unsupported types.
    static let supportedRawValues: [String] = [
        "mention",
        "status",
        "reblog",
        "follow",
        "follow_request",
        "favourite",
        "poll",
        "update",
        "admin.sign_up",
        "admin.report",
        "severed_relationships",
        "moderation_warning",
        "quote",
        "quoted_update",
        "added_to_collection",
        "collection_update",
    ]

    init(rawValue: String) {
        switch rawValue {
        case "follow": self = .follow
        case "follow_request": self = .followRequest
        case "mention": self = .mention
        case "reblog": self = .reblog
        case "favourite": self = .favourite
        case "quote": self = .quote
        case "quoted_update": self = .quotedUpdate
        case "poll": self = .poll
        case "status": self = .status
        case "update": self = .update
        case "admin.sign_up": self = .adminSignUp
        case "admin.report": self = .adminReport
        case "severed_relationships": self = .severedRelationships
        case "moderation_warning": self = .moderationWarning
        case "added_to_collection": self = .addedToCollection
        case "collection_update": self = .collectionUpdate
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .follow: return "follow"
        case .followRequest: return "follow_request"
        case .mention: return "mention"
        case .reblog: return "reblog"
        case .favourite: return "favourite"
        case .quote: return "quote"
        case .quotedUpdate: return "quoted_update"
        case .poll: return "poll"
        case .status: return "status"
        case .update: return "update"
        case .adminSignUp: return "admin.sign_up"
        case .adminReport: return "admin.report"
        case .severedRelationships: return "severed_relationships"
        case .moderationWarning: return "moderation_warning"
        case .addedToCollection: return "added_to_collection"
        case .collectionUpdate: return "collection_update"
        case .unknown(let rawValue): return rawValue
        }
    }

    var descriptor: NotificationPresentationDescriptor {
        switch self {
        case .favourite:
            return .init(
                layoutFamily: .postAction,
                filterCategory: .interactions,
                iconName: "heart.fill",
                accent: .favourite,
                showsStatusPreview: true,
                canGroupActors: true
            )
        case .reblog:
            return .init(
                layoutFamily: .postAction,
                filterCategory: .interactions,
                iconName: "repeat",
                accent: .reblog,
                showsStatusPreview: true,
                canGroupActors: true
            )
        case .quote:
            return .init(
                layoutFamily: .postAction,
                filterCategory: .interactions,
                iconName: "quote.bubble.fill",
                accent: .quote,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .mention:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .mentions,
                iconName: "at",
                accent: .standard,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .follow:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .follows,
                iconName: "person.fill.badge.plus",
                accent: .standard,
                showsStatusPreview: false,
                canGroupActors: false
            )
        case .followRequest:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .follows,
                iconName: "person.fill.badge.plus",
                accent: .standard,
                showsStatusPreview: false,
                canGroupActors: false
            )
        case .status:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .updates,
                iconName: "bell.fill",
                accent: .standard,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .adminSignUp:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .updates,
                iconName: "person.fill.badge.plus",
                accent: .standard,
                showsStatusPreview: false,
                canGroupActors: false
            )
        case .addedToCollection:
            return .init(
                layoutFamily: .personEvent,
                filterCategory: .updates,
                iconName: "person.2.fill",
                accent: .standard,
                showsStatusPreview: false,
                canGroupActors: false
            )
        case .poll:
            return .init(
                layoutFamily: .contentEvent,
                filterCategory: .interactions,
                iconName: "chart.bar.fill",
                accent: .standard,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .update:
            return .init(
                layoutFamily: .contentEvent,
                filterCategory: .updates,
                iconName: "pencil",
                accent: .standard,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .quotedUpdate:
            return .init(
                layoutFamily: .contentEvent,
                filterCategory: .updates,
                iconName: "quote.bubble",
                accent: .quote,
                showsStatusPreview: true,
                canGroupActors: false
            )
        case .collectionUpdate:
            return .init(
                layoutFamily: .contentEvent,
                filterCategory: .updates,
                iconName: "rectangle.stack.fill",
                accent: .standard,
                showsStatusPreview: false,
                canGroupActors: false
            )
        case .adminReport:
            return systemDescriptor(iconName: "flag.fill", accent: .warning)
        case .severedRelationships:
            return systemDescriptor(iconName: "person.badge.minus", accent: .warning)
        case .moderationWarning:
            return systemDescriptor(iconName: "exclamationmark.shield.fill", accent: .warning)
        case .unknown:
            return systemDescriptor(iconName: "bell.fill", accent: .standard)
        }
    }

    func actionText(isReply: Bool = false) -> String {
        switch self {
        case .follow: return MoroL10n.Notifications.actionFollowed
        case .followRequest: return MoroL10n.Notifications.actionFollowRequest
        case .mention:
            return isReply
                ? MoroL10n.Notifications.actionReplied
                : MoroL10n.Notifications.actionMentioned
        case .reblog: return MoroL10n.Notifications.actionReblogged
        case .favourite: return MoroL10n.Notifications.actionFavourited
        case .quote: return MoroL10n.Notifications.actionQuoted
        case .quotedUpdate: return MoroL10n.Notifications.actionQuotedUpdate
        case .poll: return MoroL10n.Notifications.actionPollEnded
        case .status: return MoroL10n.Notifications.actionNewStatus
        case .update: return MoroL10n.Notifications.actionEdited
        case .adminSignUp: return MoroL10n.Notifications.actionSignUp
        case .adminReport: return MoroL10n.Notifications.actionReport
        case .severedRelationships: return MoroL10n.Notifications.actionSeveredRelationships
        case .moderationWarning: return MoroL10n.Notifications.actionWarning
        case .addedToCollection: return MoroL10n.Notifications.actionAddedToCollection
        case .collectionUpdate: return MoroL10n.Notifications.actionCollectionUpdated
        case .unknown: return MoroL10n.Notifications.actionUnknown
        }
    }

    private func systemDescriptor(
        iconName: String,
        accent: NotificationAccent
    ) -> NotificationPresentationDescriptor {
        .init(
            layoutFamily: .systemEvent,
            filterCategory: .allOnly,
            iconName: iconName,
            accent: accent,
            showsStatusPreview: false,
            canGroupActors: false
        )
    }
}
