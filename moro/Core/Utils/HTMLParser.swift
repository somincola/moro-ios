//
//  HTMLParser.swift
//  moro
//
//  Simple HTML parser for Mastodon status content.
//  Strips HTML tags and extracts plain text, preserving mentions, tags, and links.
//

import Foundation

nonisolated struct HTMLParser {
    private static let inlineImageAltRegex = try? NSRegularExpression(
        pattern: #"<img\b[^>]*\balt=(?:"([^"]*)"|'([^']*)')[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let invisibleSpanRegex = try? NSRegularExpression(
        pattern: "<span class=\"invisible\">.*?</span>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let ellipsisSpanRegex = try? NSRegularExpression(
        pattern: "<span class=\"ellipsis\">.*?</span>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let lineBreakTagRegex = try? NSRegularExpression(
        pattern: #"<br\b[^>]*\/?>"#,
        options: [.caseInsensitive]
    )
    private static let openingParagraphTagRegex = try? NSRegularExpression(
        pattern: #"<p\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let closingParagraphTagRegex = try? NSRegularExpression(
        pattern: #"<\/p\s*>"#,
        options: [.caseInsensitive]
    )

    /// Memoizes stripped output — the same post body is re-stripped on every scroll render.
    private static let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 500
        return c
    }()

    /// Strip HTML tags and decode HTML entities, returning plain text
    /// Handles invisible spans, preserves paragraph breaks, and removes ellipsis
    static func stripHTML(_ html: String) -> String {
        let cacheKey = html as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached as String
        }

        var text = replacingInlineImageTagsWithAltText(html)

        // Remove the blockquote inline class.
        text = text.replacingOccurrences(of: "<p class=\"quote-inline\">", with: "<p>")

        // Remove invisible spans (class="invisible" or class="ellipsis").
        // These are used for screen readers and should not be displayed
        // Use NSRegularExpression for dotMatchesLineSeparators support
        if let invisibleSpanRegex {
            text = invisibleSpanRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        if let ellipsisSpanRegex {
            text = ellipsisSpanRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        // Paragraphs are blocks: adjacent paragraphs retain one empty line,
        // while <br> remains a single intra-paragraph line break.
        text = replacingParagraphTags(in: text, with: "\n\n")
        text = replacingLineBreakTags(in: text, with: "\n")
        
        // Convert other block elements
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<div[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        
        // Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        text = decodeEntities(text)
        
        // Clean up multiple spaces (but preserve newlines)
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        // Clean up multiple consecutive newlines (max 2)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        // Trim leading/trailing whitespace but preserve internal newlines
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        cache.setObject(text as NSString, forKey: cacheKey)
        return text
    }

    /// Replace inline HTML image tags with their `alt` text so custom emoji survive stripping.
    static func replacingInlineImageTagsWithAltText(_ html: String) -> String {
        guard let inlineImageAltRegex else { return html }

        let matches = inlineImageAltRegex.matches(
            in: html,
            options: [],
            range: NSRange(html.startIndex..., in: html)
        )
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }

            let altRange: Range<String.Index>?
            if let doubleQuotedRange = Range(match.range(at: 1), in: result),
               !doubleQuotedRange.isEmpty {
                altRange = doubleQuotedRange
            } else if let singleQuotedRange = Range(match.range(at: 2), in: result),
                      !singleQuotedRange.isEmpty {
                altRange = singleQuotedRange
            } else {
                altRange = nil
            }

            let replacement = altRange.map { decodeEntities(String(result[$0])) } ?? ""
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// Replace HTML line break tags, including variants like `<br/>`, `<br />`, and `<br class="...">`.
    static func replacingLineBreakTags(in html: String, with replacement: String) -> String {
        guard let lineBreakTagRegex else {
            return html
                .replacingOccurrences(of: "<br>", with: replacement, options: .caseInsensitive)
                .replacingOccurrences(of: "<br/>", with: replacement, options: .caseInsensitive)
                .replacingOccurrences(of: "<br />", with: replacement, options: .caseInsensitive)
        }

        return lineBreakTagRegex.stringByReplacingMatches(
            in: html,
            options: [],
            range: NSRange(html.startIndex..., in: html),
            withTemplate: replacement
        )
    }

    /// Remove opening paragraph tags and replace closing tags with a semantic block break.
    static func replacingParagraphTags(in html: String, with paragraphBreak: String) -> String {
        var result = html

        if let closingParagraphTagRegex {
            result = closingParagraphTagRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: paragraphBreak
            )
        } else {
            result = result.replacingOccurrences(
                of: "</p>",
                with: paragraphBreak,
                options: .caseInsensitive
            )
        }

        if let openingParagraphTagRegex {
            result = openingParagraphTagRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        } else {
            result = result.replacingOccurrences(of: "<p>", with: "", options: .caseInsensitive)
        }

        return result
    }

    /// Decode common and numeric HTML entities.
    static func decodeEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = decodeNumericEntities(result)
        return result
    }

    /// Decode numeric HTML entities like &#123; or &#x1F600;
    private static func decodeNumericEntities(_ text: String) -> String {
        var result = text
        
        // Handle decimal entities (&#123;)
        let decimalPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2,
                   let numberRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[numberRange]),
                   let unicodeScalar = UnicodeScalar(number),
                   let matchRange = Range(match.range, in: result) {
                    result.replaceSubrange(matchRange, with: String(Character(unicodeScalar)))
                }
            }
        }
        
        // Handle hexadecimal entities (&#x1F600;)
        let hexPattern = "&#x([0-9A-Fa-f]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2,
                   let hexRange = Range(match.range(at: 1), in: result),
                   let number = Int(result[hexRange], radix: 16),
                   let unicodeScalar = UnicodeScalar(number),
                   let matchRange = Range(match.range, in: result) {
                    result.replaceSubrange(matchRange, with: String(Character(unicodeScalar)))
                }
            }
        }
        
        return result
    }
    
    /// Extract mentions from HTML content
    static func extractMentions(_ html: String) -> [String] {
        let pattern = "<span class=\"h-card\">.*?<a href=\"([^\"]+)\".*?>@([^<]+)</a>"
        var mentions: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if match.numberOfRanges >= 3,
                   let usernameRange = Range(match.range(at: 2), in: html) {
                    mentions.append(String(html[usernameRange]))
                }
            }
        }
        
        return mentions
    }
    
    /// Extract hashtags from HTML content
    static func extractHashtags(_ html: String) -> [String] {
        let pattern = "<a href=\"[^\"]*tag/[^\"]+\".*?>#([^<]+)</a>"
        var tags: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if match.numberOfRanges >= 2,
                   let tagRange = Range(match.range(at: 1), in: html) {
                    tags.append(String(html[tagRange]))
                }
            }
        }
        
        return tags
    }
}
