//
//  StatusTranslationPayload.swift
//  moro
//
//  Server-side status translation payload returned by Mastodon.
//

import Foundation

struct StatusTranslationPayload: Codable, Equatable, Sendable {
    let content: String?
    let detectedSourceLanguage: String?
    let provider: String?
    let spoilerText: String?

    enum CodingKeys: String, CodingKey {
        case content
        case detectedSourceLanguage = "detected_source_language"
        case provider
        case spoilerText = "spoiler_text"
    }
}
