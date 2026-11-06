import Foundation

/// The author's original text, before Mastodon formats links and mentions as HTML.
nonisolated struct StatusSource: Decodable, Equatable {
    let id: String
    let text: String
    let spoilerText: String

    nonisolated enum CodingKeys: String, CodingKey {
        case id, text
        case spoilerText = "spoiler_text"
    }
}
