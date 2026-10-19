//
//  ScheduledStatus.swift
//  moro
//
//  Mastodon scheduled status model.
//

import Foundation

nonisolated struct ScheduledStatus: Identifiable, Codable {
    nonisolated struct Parameters: Codable {
        let text: String?
        let spoilerText: String?
        let visibility: MastodonVisibility?
        let inReplyToID: String?

        nonisolated enum CodingKeys: String, CodingKey {
            case text
            case spoilerText = "spoiler_text"
            case visibility
            case inReplyToID = "in_reply_to_id"
        }
    }

    let id: String
    let scheduledAt: Date
    let params: Parameters?
    let mediaAttachments: [Status.Attachment]

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case scheduledAt = "scheduled_at"
        case params
        case mediaAttachments = "media_attachments"
    }

    var previewText: String {
        let text = params?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return HTMLParser.stripHTML(text)
        }
        let spoiler = params?.spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spoiler.isEmpty {
            return spoiler
        }
        if !mediaAttachments.isEmpty {
            return MoroL10n.ScheduledStatus.mediaOnly
        }
        return MoroL10n.ScheduledStatus.noText
    }
}
