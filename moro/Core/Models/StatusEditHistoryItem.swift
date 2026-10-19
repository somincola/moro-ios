//
//  StatusEditHistoryItem.swift
//  moro
//
//  Model for Mastodon status edit-history entries.
//

import Foundation

nonisolated struct StatusEditHistoryItem: Codable, Identifiable {
    let content: String
    let spoilerText: String?
    let createdAt: Date?
    let account: Account?
    let mediaAttachments: [Status.Attachment]

    var id: String {
        let timePart = createdAt?.ISO8601Format() ?? "unknown-time"
        return "\(timePart)-\(content.hashValue)"
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case content
        case spoilerText = "spoiler_text"
        case createdAt = "created_at"
        case account
        case mediaAttachments = "media_attachments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        spoilerText = try container.decodeIfPresent(String.self, forKey: .spoilerText)
        account = try container.decodeIfPresent(Account.self, forKey: .account)
        mediaAttachments =
            try container.decodeIfPresent([Status.Attachment].self, forKey: .mediaAttachments) ?? []

        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = dateValue
        } else if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = DateFormatting.parseISO8601(createdAtString)
        } else {
            createdAt = nil
        }
    }

    init(
        content: String,
        spoilerText: String? = nil,
        createdAt: Date? = nil,
        account: Account? = nil,
        mediaAttachments: [Status.Attachment] = []
    ) {
        self.content = content
        self.spoilerText = spoilerText
        self.createdAt = createdAt
        self.account = account
        self.mediaAttachments = mediaAttachments
    }
}
