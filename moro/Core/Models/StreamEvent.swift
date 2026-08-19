//
//  StreamEvent.swift
//  moro
//
//  WebSocket streaming event models for real-time Mastodon updates.
//

import Foundation

// MARK: - Raw Stream Event

/// Raw event received from the WebSocket connection
struct RawStreamEvent: Decodable, Sendable {
    let event: String
    let stream: [String]?
    let payload: String?
}

// MARK: - Stream Event Enum

/// Unified stream event enum for type-safe event handling
enum StreamEvent: Identifiable, Sendable {
    case update(status: Status)
    case statusUpdate(status: Status)
    case delete(statusId: String)
    case notification(notification: NotificationItem)
    case conversation(conversationId: String, unread: Bool, lastStatus: Status?)

    var id: String {
        switch self {
        case .update(let status):
            return "update_\(status.id)"
        case .statusUpdate(let status):
            return "edit_\(status.id)_\(Date().timeIntervalSince1970)"
        case .delete(let statusId):
            return "delete_\(statusId)_\(Date().timeIntervalSince1970)"
        case .notification(let notification):
            return "notification_\(notification.id)"
        case .conversation(let conversationId, let unread, let lastStatus):
            return "conversation_\(conversationId)_\(unread)_\(lastStatus?.id ?? "none")"
        }
    }

    var date: Date {
        Date()
    }

    /// The status associated with this event, if any
    var status: Status? {
        switch self {
        case .update(let status), .statusUpdate(let status):
            return status
        case .conversation(_, _, let lastStatus):
            return lastStatus
        default:
            return nil
        }
    }

    /// The status ID for delete events
    var deletedStatusId: String? {
        if case .delete(let statusId) = self {
            return statusId
        }
        return nil
    }

    /// The notification for notification events
    var notificationItem: NotificationItem? {
        if case .notification(let notification) = self {
            return notification
        }
        return nil
    }
}

// MARK: - Stream Message

/// Message sent to subscribe/unsubscribe from streams
struct StreamMessage: Encodable, Sendable {
    let type: String
    let stream: String

    init(type: String, stream: String) {
        self.type = type
        self.stream = stream
    }
}

// MARK: - Conversation Model (for streaming)

/// Simplified conversation model for streaming events
struct StreamConversation: Codable, Sendable {
    let id: String
    let unread: Bool
    let lastStatus: Status?

    enum CodingKeys: String, CodingKey {
        case id
        case unread
        case lastStatus = "last_status"
    }
}
