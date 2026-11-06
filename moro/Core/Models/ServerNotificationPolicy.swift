//
//  ServerNotificationPolicy.swift
//  moro
//
//  Server-owned notification intake policy and filtered notification requests.
//

import Foundation

nonisolated struct ServerNotificationPolicy: Codable, Equatable {
    nonisolated enum Disposition: String, Codable, CaseIterable, Identifiable {
        case accept
        case filter
        case drop

        var id: String { rawValue }
    }

    nonisolated struct Summary: Codable, Equatable {
        let pendingRequestsCount: Int
        let pendingNotificationsCount: Int

        nonisolated enum CodingKeys: String, CodingKey {
            case pendingRequestsCount = "pending_requests_count"
            case pendingNotificationsCount = "pending_notifications_count"
        }
    }

    var forNotFollowing: Disposition
    var forNotFollowers: Disposition
    var forNewAccounts: Disposition
    var forPrivateMentions: Disposition
    var forLimitedAccounts: Disposition
    var forBots: Disposition?
    var summary: Summary

    nonisolated enum CodingKeys: String, CodingKey {
        case forNotFollowing = "for_not_following"
        case forNotFollowers = "for_not_followers"
        case forNewAccounts = "for_new_accounts"
        case forPrivateMentions = "for_private_mentions"
        case forLimitedAccounts = "for_limited_accounts"
        case forBots = "for_bots"
        case summary
    }
}

nonisolated struct ServerNotificationRequest: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let notificationsCount: Int
    let account: Account
    let lastStatus: Status?

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notificationsCount = "notifications_count"
        case account
        case lastStatus = "last_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        account = try container.decode(Account.self, forKey: .account)
        lastStatus = try container.decodeIfPresent(Status.self, forKey: .lastStatus)
        if let value = try? container.decode(Int.self, forKey: .notificationsCount) {
            notificationsCount = value
        } else {
            notificationsCount = Int(try container.decode(String.self, forKey: .notificationsCount)) ?? 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(notificationsCount, forKey: .notificationsCount)
        try container.encode(account, forKey: .account)
        try container.encodeIfPresent(lastStatus, forKey: .lastStatus)
    }
}
