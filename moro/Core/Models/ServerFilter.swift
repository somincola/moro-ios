//
//  ServerFilter.swift
//  moro
//
//  Server-side content filter model (Mastodon v2 filters API).
//

import Foundation

struct ServerFilter: Identifiable, Codable, Hashable {
    enum Action: String, Codable, CaseIterable {
        case warn
        case hide
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = Action(rawValue: value) ?? .unknown
        }

        var localizedTitle: String {
            switch self {
            case .warn:
                return MoroL10n.ServerFilter.actionWarn
            case .hide:
                return MoroL10n.ServerFilter.actionHide
            case .unknown:
                return MoroL10n.ServerFilter.actionUnknown
            }
        }
    }

    enum Context: String, Codable, CaseIterable, Hashable {
        case home
        case notifications
        case `public` = "public"
        case thread
        case account
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = Context(rawValue: value) ?? .unknown
        }

        var localizedTitle: String {
            switch self {
            case .home:
                return MoroL10n.ServerFilter.contextHome
            case .notifications:
                return MoroL10n.ServerFilter.contextNotifications
            case .public:
                return MoroL10n.ServerFilter.contextPublic
            case .thread:
                return MoroL10n.ServerFilter.contextThread
            case .account:
                return MoroL10n.ServerFilter.contextAccount
            case .unknown:
                return MoroL10n.ServerFilter.contextUnknown
            }
        }
    }

    struct Keyword: Identifiable, Codable, Hashable {
        let id: String
        let keyword: String
        let wholeWord: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case keyword
            case wholeWord = "whole_word"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keyword = try container.decode(String.self, forKey: .keyword)
            wholeWord = try container.decodeIfPresent(Bool.self, forKey: .wholeWord) ?? false
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? keyword
        }
    }

    let id: String
    let title: String
    let context: [Context]
    let expiresAt: Date?
    let filterAction: Action
    let keywords: [Keyword]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case context
        case expiresAt = "expires_at"
        case filterAction = "filter_action"
        case keywords
    }
}
