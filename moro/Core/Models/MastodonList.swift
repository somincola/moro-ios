//
//  MastodonList.swift
//  moro
//
//  Mastodon list model for list management and list timelines.
//

import Foundation

struct MastodonList: Identifiable, Codable, Hashable {
    enum RepliesPolicy: String, Codable, CaseIterable, Hashable {
        case followed = "followed"
        case list = "list"
        case none = "none"
    }

    let id: String
    let title: String
    let repliesPolicy: RepliesPolicy?
    let exclusive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case repliesPolicy = "replies_policy"
        case exclusive
    }
}
