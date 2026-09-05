import Foundation

/// The author's original text, before Mastodon formats links and mentions as HTML.
struct StatusSource: Decodable, Equatable {
    let id: String
    let text: String
    let spoilerText: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case spoilerText = "spoiler_text"
    }
}
