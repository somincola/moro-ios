//
//  MastodonTextCounter.swift
//  moro
//
//  Counts status text the way Mastodon does, so the compose character counter matches the
//  server: every URL counts as a fixed 23 characters (regardless of its real length), and
//  the @domain part of a remote mention is excluded from the count.
//

import Foundation

enum MastodonTextCounter {
    /// Mastodon's default `characters_reserved_per_url`.
    static let charactersReservedPerURL = 23

    private static let urlRegex = try? NSRegularExpression(
        pattern: "https?://[^\\s]+",
        options: [.caseInsensitive]
    )

    /// `@user@domain` — captures the local `@user`; the `@domain` is dropped from the count.
    private static let remoteMentionRegex = try? NSRegularExpression(
        pattern: "@([a-zA-Z0-9_]+)@[a-zA-Z0-9.-]+",
        options: []
    )

    /// The Mastodon-equivalent character count of `text`.
    static func count(_ text: String) -> Int {
        var transformed = text

        if let urlRegex {
            let placeholder = String(repeating: "x", count: charactersReservedPerURL)
            transformed = urlRegex.stringByReplacingMatches(
                in: transformed,
                range: NSRange(transformed.startIndex..., in: transformed),
                withTemplate: placeholder
            )
        }

        if let remoteMentionRegex {
            transformed = remoteMentionRegex.stringByReplacingMatches(
                in: transformed,
                range: NSRange(transformed.startIndex..., in: transformed),
                withTemplate: "@$1"
            )
        }

        return transformed.count
    }
}
