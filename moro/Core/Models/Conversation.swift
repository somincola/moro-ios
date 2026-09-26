//
//  Conversation.swift
//  moro
//
//  Mastodon direct-message conversation model.
//

import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: String
    let unread: Bool
    let accounts: [Account]
    let lastStatus: Status?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case unread
        case accounts
        case lastStatus = "last_status"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        unread: Bool,
        accounts: [Account],
        lastStatus: Status?,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.unread = unread
        self.accounts = accounts
        self.lastStatus = lastStatus
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        unread = try container.decodeIfPresent(Bool.self, forKey: .unread) ?? false
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        lastStatus = try container.decodeIfPresent(Status.self, forKey: .lastStatus)

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = DateFormatting.parseISO8601(updatedAtString)
        } else {
            updatedAt = nil
        }
    }
}

struct ConversationsPage {
    let conversations: [Conversation]
    /// Opaque cursor from the response Link header. Conversation entity IDs are not pagination cursors.
    let nextMaxID: String?
}

extension Conversation {
    var isDraft: Bool {
        id.hasPrefix("draft:")
    }

    static func draft(participants: [Account]) -> Conversation {
        let participantIDs = participants.map(\.id).sorted()
        let suffix = participantIDs.isEmpty ? UUID().uuidString : participantIDs.joined(separator: ",")
        return Conversation(
            id: "draft:\(suffix)",
            unread: false,
            accounts: participants,
            lastStatus: nil,
            updatedAt: Date()
        )
    }
}
