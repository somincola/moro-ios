//
//  Announcement.swift
//  moro
//
//  Mastodon announcement models.
//

import Foundation

nonisolated struct Announcement: Identifiable, Codable, Hashable {
    let id: String
    let content: String
    let startsAt: Date?
    let endsAt: Date?
    let allDay: Bool
    let publishedAt: Date
    let updatedAt: Date
    let read: Bool
    let mentions: [AnnouncementMention]
    let tags: [AnnouncementTag]
    let emojis: [AnnouncementEmoji]
    let reactions: [AnnouncementReaction]

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case content
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
        case read
        case mentions
        case tags
        case emojis
        case reactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        publishedAt = try container.decode(Date.self, forKey: .publishedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
        mentions = try container.decodeIfPresent([AnnouncementMention].self, forKey: .mentions) ?? []
        tags = try container.decodeIfPresent([AnnouncementTag].self, forKey: .tags) ?? []
        emojis = try container.decodeIfPresent([AnnouncementEmoji].self, forKey: .emojis) ?? []
        reactions = try container.decodeIfPresent([AnnouncementReaction].self, forKey: .reactions) ?? []
    }
}

nonisolated struct AnnouncementReaction: Codable, Hashable {
    let name: String
    let count: Int
    let me: Bool
    let url: URL?
    let staticURL: URL?

    nonisolated enum CodingKeys: String, CodingKey {
        case name
        case count
        case me
        case url
        case staticURL = "static_url"
    }
}

nonisolated struct AnnouncementMention: Codable, Hashable {
    let id: String
    let username: String
    let url: URL
    let acct: String
}

nonisolated struct AnnouncementTag: Codable, Hashable {
    let name: String
    let url: URL
}

nonisolated struct AnnouncementEmoji: Codable, Hashable {
    let shortcode: String
    let url: URL
    let staticURL: URL

    nonisolated enum CodingKeys: String, CodingKey {
        case shortcode
        case url
        case staticURL = "static_url"
    }
}
