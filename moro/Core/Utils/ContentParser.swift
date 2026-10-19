//
//  ContentParser.swift
//  moro
//
//  Parses Mastodon HTML content into AttributedString with clickable links.
//  Handles mentions, hashtags, and regular links.
//

import Foundation
import SwiftUI

/// Preserve the parser's link semantics through navigation.
nonisolated enum LinkAction: Equatable {
    case mention(username: String, url: URL)
    case hashtag(tag: String, url: URL)
    case link(url: URL)

    var url: URL {
        switch self {
        case .mention(_, let url), .hashtag(_, let url), .link(let url):
            return url
        }
    }
}

/// Content element types for rendering
nonisolated enum ContentElement: Equatable {
    case text(String)
    case link(text: String, url: URL)
    case mention(username: String, url: URL)
    case hashtag(tag: String, url: URL)
    case emoji(shortcode: String, url: URL, staticURL: URL)
    case inlineCode(String)
    case codeBlock(String)
    case lineBreak
}

nonisolated struct ContentParsingOptions: OptionSet {
    let rawValue: Int

    static let preserveInlineImageAltText = ContentParsingOptions(rawValue: 1 << 0)
    static let autoDetectPlainLinks = ContentParsingOptions(rawValue: 1 << 1)
    static let autoDetectRemoteMentions = ContentParsingOptions(rawValue: 1 << 2)
    static let autoDetectPlainHashtags = ContentParsingOptions(rawValue: 1 << 3)
    static let omitKnownHashtagLinks = ContentParsingOptions(rawValue: 1 << 4)
    static let separateMentionsFromFollowingText = ContentParsingOptions(rawValue: 1 << 5)
    static let preserveCodeSemantics = ContentParsingOptions(rawValue: 1 << 6)
    static let separateAdjacentHashtags = ContentParsingOptions(rawValue: 1 << 7)
    static let preserveInlineWhitespace = ContentParsingOptions(rawValue: 1 << 8)

    static let accountRichText: ContentParsingOptions = [
        .preserveInlineImageAltText,
        .autoDetectPlainLinks,
        .autoDetectRemoteMentions,
        .autoDetectPlainHashtags,
        .separateAdjacentHashtags,
    ]

    static let statusBody: ContentParsingOptions = [
        .omitKnownHashtagLinks,
        .separateMentionsFromFollowingText,
        .preserveCodeSemantics,
        .preserveInlineWhitespace,
    ]
}

nonisolated extension Array where Element == ContentElement {
    var containsCustomEmoji: Bool {
        contains {
            if case .emoji = $0 { return true }
            return false
        }
    }

    var plainTextValue: String {
        var result = ""
        for (index, element) in enumerated() {
            switch element {
            case .text(let text):
                result += text
            case .link(let text, _):
                result += text
            case .mention(let username, _):
                result += username
            case .hashtag(let tag, _):
                result += tag
            case .emoji(let shortcode, _, _):
                result += ":\(shortcode):"
            case .inlineCode(let code):
                result += code
            case .codeBlock(let code):
                if !result.isEmpty, !result.hasSuffix("\n") {
                    result += "\n"
                }
                result += code
                if index < count - 1, self[index + 1] != .lineBreak {
                    result += "\n"
                }
            case .lineBreak:
                result += "\n"
            }
        }
        return result
    }

    var normalizedInlinePlainText: String {
        plainTextValue
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Parser for Mastodon HTML content
nonisolated struct ContentParser {
    private final class CachedElementsBox {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let elements: [ContentElement]

        init(_ elements: [ContentElement]) {
            self.elements = elements
        }
    }

    private static let parseCache: NSCache<NSString, CachedElementsBox> = {
        let cache = NSCache<NSString, CachedElementsBox>()
        cache.countLimit = 1200
        return cache
    }()

    private static let plainURLRegex = try? NSRegularExpression(
        pattern: #"(?:(?:https?)://|www\.)[^\s<]+"#,
        options: [.caseInsensitive]
    )
    private static let remoteMentionRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_./])@([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})(?![A-Za-z0-9_@.-])"#,
        options: []
    )
    private static let plainHashtagRegex = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/])#([\p{L}\p{N}_][\p{L}\p{N}_.-]*)"#,
        options: []
    )
    private static let emojiShortcodeRegex = try? NSRegularExpression(pattern: ":([a-zA-Z0-9_]+):")
    private static let mentionAttachedPunctuation = CharacterSet(
        charactersIn: ".,!?;:，。！？；：、…—–-/\\)]}）］｝〉》」』】〗'\"’”"
    )
    
    /// Parse HTML content into AttributedString with clickable links
    /// - Parameters:
    ///   - html: Raw HTML content from Mastodon API
    ///   - mentions: Mention entities from status
    ///   - tags: Tag entities from status
    ///   - emojis: Emoji entities from status
    /// - Returns: AttributedString with proper formatting and links
    static func parse(
        html: String,
        mentions: [Status.Mention]? = nil,
        tags: [Status.Tag]? = nil,
        emojis: [Status.Emoji]? = nil,
        contentBaseURL: URL? = nil,
        options: ContentParsingOptions = []
    ) -> AttributedString {
        let elements = parseToElements(
            html: html,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            contentBaseURL: contentBaseURL,
            options: options
        )
        return buildAttributedString(from: elements)
    }
    
    /// Parse HTML into content elements
    static func parseToElements(
        html: String,
        mentions: [Status.Mention]? = nil,
        tags: [Status.Tag]? = nil,
        emojis: [Status.Emoji]? = nil,
        contentBaseURL: URL? = nil,
        options: ContentParsingOptions = []
    ) -> [ContentElement] {
        let cacheKey = cacheKey(
            html: html,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            contentBaseURL: contentBaseURL,
            options: options
        )
        if let cached = parseCache.object(forKey: cacheKey) {
            return cached.elements
        }

        // HTML extraction is document ordered. Only decoded text nodes enter the
        // inline detector; anchor destinations and code remain atomic elements.
        let documentElements = ContentDOMParser.parse(
            html: html, mentions: mentions, tags: tags, emojis: emojis,
            contentBaseURL: contentBaseURL, options: options
        )
        let elements = cleanupTextRunElements(documentElements).flatMap { element in
            if case .text(let text) = element {
                return processInlineText(
                    text, emojis: emojis, contentBaseURL: contentBaseURL, options: options
                )
            }
            return [element]
        }

        // Clean up: merge adjacent text elements and remove empty ones
        let cleaned = cleanupElements(elements)
        let hashtagSeparated = options.contains(.separateAdjacentHashtags)
            ? separatingAdjacentHashtags(cleaned)
            : cleaned
        let normalized = options.contains(.separateMentionsFromFollowingText)
            ? separatingMentionsFromFollowingText(hashtagSeparated)
            : hashtagSeparated
        parseCache.setObject(CachedElementsBox(normalized), forKey: cacheKey)
        return normalized
    }

    /// Preserve the account presentation fallback for adjacent anchors whose source
    /// omitted a separator. Existing DOM whitespace is left untouched.
    private static func separatingAdjacentHashtags(
        _ elements: [ContentElement]
    ) -> [ContentElement] {
        guard elements.count > 1 else { return elements }

        var result: [ContentElement] = []
        result.reserveCapacity(elements.count)

        for element in elements {
            if case .hashtag = element,
               let previous = result.last,
               case .hashtag = previous {
                result.append(.text(" "))
            }
            result.append(element)
        }

        return result
    }

    /// Preserve the status presentation fallback for mentions attached to prose or
    /// another mention. Existing DOM spaces and attached punctuation stay untouched.
    private static func separatingMentionsFromFollowingText(
        _ elements: [ContentElement]
    ) -> [ContentElement] {
        guard elements.count > 1 else { return elements }

        var result: [ContentElement] = []
        result.reserveCapacity(elements.count)

        for element in elements {
            var normalizedElement = element

            if let previous = result.last,
               case .mention = previous {
                switch element {
                case .mention:
                    result.append(.text(" "))
                case .text(let text):
                    if let firstScalar = text.unicodeScalars.first,
                       !CharacterSet.whitespacesAndNewlines.contains(firstScalar),
                       !mentionAttachedPunctuation.contains(firstScalar) {
                        normalizedElement = .text(" " + text)
                    }
                default:
                    break
                }
            }

            result.append(normalizedElement)
        }

        return result
    }
    
    nonisolated private enum InlineTokenMatch {
        case url(Range<String.Index>)
        case remoteMention(Range<String.Index>, username: String, domain: String)
        case hashtag(Range<String.Index>, tag: String)
        case emoji(Range<String.Index>, shortcode: String)

        var range: Range<String.Index> {
            switch self {
            case .url(let range):
                return range
            case .remoteMention(let range, _, _):
                return range
            case .hashtag(let range, _):
                return range
            case .emoji(let range, _):
                return range
            }
        }
    }

    private static func processInlineText(
        _ text: String,
        emojis: [Status.Emoji]? = nil,
        contentBaseURL: URL? = nil,
        options: ContentParsingOptions = []
    ) -> [ContentElement] {
        let shouldAutoDetectLinks = options.contains(.autoDetectPlainLinks)
        let shouldAutoDetectMentions = options.contains(.autoDetectRemoteMentions)
        let shouldAutoDetectHashtags = options.contains(.autoDetectPlainHashtags)
        let shouldResolveEmoji = emojis != nil

        guard shouldAutoDetectLinks || shouldAutoDetectMentions || shouldAutoDetectHashtags || shouldResolveEmoji else {
            return [.text(text)]
        }

        var elements: [ContentElement] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let match = nextInlineTokenMatch(
                in: text,
                from: cursor,
                shouldDetectLinks: shouldAutoDetectLinks,
                shouldDetectRemoteMentions: shouldAutoDetectMentions,
                shouldDetectPlainHashtags: shouldAutoDetectHashtags,
                shouldDetectEmoji: shouldResolveEmoji
            ) else {
                let tail = String(text[cursor...])
                if !tail.isEmpty {
                    elements.append(.text(tail))
                }
                break
            }

            if cursor < match.range.lowerBound {
                elements.append(.text(String(text[cursor..<match.range.lowerBound])))
            }

            switch match {
            case .emoji(let range, let shortcode):
                if let emojis,
                   let emoji = emojis.first(where: { $0.shortcode.caseInsensitiveCompare(shortcode) == .orderedSame }) {
                    elements.append(.emoji(shortcode: shortcode, url: emoji.url, staticURL: emoji.staticURL))
                } else {
                    elements.append(.text(String(text[range])))
                }

            case .url(let range):
                let matchedText = String(text[range])
                let (core, trailing) = splitTrailingURLPunctuation(from: matchedText)
                let resolvedURLString = core.lowercased().hasPrefix("www.") ? "https://\(core)" : core
                if let url = URL(string: resolvedURLString), !core.isEmpty {
                    elements.append(.link(text: core, url: url))
                    if !trailing.isEmpty {
                        elements.append(.text(trailing))
                    }
                } else {
                    elements.append(.text(matchedText))
                }

            case .remoteMention(let range, let username, let domain):
                let matchedText = String(text[range])
                let (core, trailing) = splitTrailingMentionPunctuation(from: matchedText)
                if !core.isEmpty, let url = URL(string: "https://\(domain)/@\(username)") {
                    elements.append(.mention(username: core, url: url))
                    if !trailing.isEmpty {
                        elements.append(.text(trailing))
                    }
                } else {
                    elements.append(.text(matchedText))
                }

            case .hashtag(let range, let tag):
                let matchedText = String(text[range])
                let (core, trailing) = splitTrailingHashtagPunctuation(from: matchedText)
                let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedTag.isEmpty,
                   let url = hashtagURL(for: normalizedTag, contentBaseURL: contentBaseURL) {
                    elements.append(.hashtag(tag: core, url: url))
                    if !trailing.isEmpty {
                        elements.append(.text(trailing))
                    }
                } else {
                    elements.append(.text(matchedText))
                }
            }

            cursor = match.range.upperBound
        }

        return cleanupTextRunElements(elements)
    }

    private static func nextInlineTokenMatch(
        in text: String,
        from startIndex: String.Index,
        shouldDetectLinks: Bool,
        shouldDetectRemoteMentions: Bool,
        shouldDetectPlainHashtags: Bool,
        shouldDetectEmoji: Bool
    ) -> InlineTokenMatch? {
        let searchRange = NSRange(startIndex..<text.endIndex, in: text)
        var candidates: [InlineTokenMatch] = []

        if shouldDetectLinks,
           let plainURLRegex,
           let match = plainURLRegex.firstMatch(in: text, options: [], range: searchRange),
           let range = Range(match.range, in: text) {
            candidates.append(.url(range))
        }

        if shouldDetectRemoteMentions,
           let remoteMentionRegex,
           let match = remoteMentionRegex.firstMatch(in: text, options: [], range: searchRange),
           let range = Range(match.range, in: text),
           let usernameRange = Range(match.range(at: 1), in: text),
           let domainRange = Range(match.range(at: 2), in: text) {
            candidates.append(
                .remoteMention(
                    range,
                    username: String(text[usernameRange]),
                    domain: String(text[domainRange])
                )
            )
        }

        if shouldDetectPlainHashtags,
           let plainHashtagRegex,
           let match = plainHashtagRegex.firstMatch(in: text, options: [], range: searchRange),
           let range = Range(match.range, in: text),
           let tagRange = Range(match.range(at: 1), in: text) {
            candidates.append(.hashtag(range, tag: String(text[tagRange])))
        }

        if shouldDetectEmoji,
           let emojiShortcodeRegex,
           let match = emojiShortcodeRegex.firstMatch(in: text, options: [], range: searchRange),
           let range = Range(match.range, in: text),
           let shortcodeRange = Range(match.range(at: 1), in: text) {
            candidates.append(.emoji(range, shortcode: String(text[shortcodeRange])))
        }

        return candidates.min {
            let lhsRange = $0.range
            let rhsRange = $1.range
            if lhsRange.lowerBound == rhsRange.lowerBound {
                return text.distance(from: lhsRange.lowerBound, to: lhsRange.upperBound)
                    < text.distance(from: rhsRange.lowerBound, to: rhsRange.upperBound)
            }
            return lhsRange.lowerBound < rhsRange.lowerBound
        }
    }

    private static func splitTrailingURLPunctuation(from token: String) -> (String, String) {
        splitTrailingPunctuation(
            from: token,
            punctuation: CharacterSet(charactersIn: ".,!?)]}:'\"")
        )
    }

    private static func splitTrailingMentionPunctuation(from token: String) -> (String, String) {
        splitTrailingPunctuation(
            from: token,
            punctuation: CharacterSet(charactersIn: ".,!?)]}:'\"")
        )
    }

    private static func splitTrailingHashtagPunctuation(from token: String) -> (String, String) {
        splitTrailingPunctuation(
            from: token,
            punctuation: CharacterSet(charactersIn: ".,!?)]}:'\"")
        )
    }

    private static func hashtagURL(for tag: String, contentBaseURL: URL?) -> URL? {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return nil }

        let fallbackBaseURL = URL(string: "https://mastodon.social")
        guard let baseURL = contentBaseURL ?? fallbackBaseURL,
              var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
              )
        else {
            return nil
        }

        components.path = "/tags/\(normalizedTag)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func splitTrailingPunctuation(
        from token: String,
        punctuation: CharacterSet
    ) -> (String, String) {
        var core = token
        var trailing = ""

        while let lastScalar = core.unicodeScalars.last, punctuation.contains(lastScalar) {
            trailing = String(lastScalar) + trailing
            core.removeLast()
        }

        return (core, trailing)
    }

    private static func cleanupTextRunElements(_ elements: [ContentElement]) -> [ContentElement] {
        var merged: [ContentElement] = []
        for element in elements {
            switch element {
            case .text(let text):
                guard !text.isEmpty else { continue }
                if case .text(let existing)? = merged.last {
                    merged.removeLast()
                    merged.append(.text(existing + text))
                } else {
                    merged.append(.text(text))
                }
            default:
                merged.append(element)
            }
        }
        return merged
    }
    
    private static func cacheKey(
        html: String,
        mentions: [Status.Mention]?,
        tags: [Status.Tag]?,
        emojis: [Status.Emoji]?,
        contentBaseURL: URL?,
        options: ContentParsingOptions
    ) -> NSString {
        var hasher = Hasher()
        hasher.combine(html)
        hasher.combine(options.rawValue)
        hasher.combine(contentBaseURL?.absoluteString ?? "")

        if let mentions {
            hasher.combine(mentions.count)
            for mention in mentions {
                hasher.combine(mention.id)
                hasher.combine(mention.username)
                hasher.combine(mention.acct)
                hasher.combine(mention.url.absoluteString)
            }
        } else {
            hasher.combine(0)
        }

        if let tags {
            hasher.combine(tags.count)
            for tag in tags {
                hasher.combine(tag.name)
                hasher.combine(tag.url.absoluteString)
            }
        } else {
            hasher.combine(0)
        }

        if let emojis {
            hasher.combine(emojis.count)
            for emoji in emojis {
                hasher.combine(emoji.shortcode)
                hasher.combine(emoji.url.absoluteString)
                hasher.combine(emoji.staticURL.absoluteString)
            }
        } else {
            hasher.combine(0)
        }

        return NSString(string: String(hasher.finalize()))
    }
    
    /// Clean up elements: merge adjacent texts, remove empty elements
    private static func cleanupElements(_ elements: [ContentElement]) -> [ContentElement] {
        var cleaned: [ContentElement] = []
        var pendingText = ""
        
        for element in elements {
            switch element {
            case .text(let text):
                pendingText += text
            case .lineBreak:
                if !pendingText.isEmpty {
                    cleaned.append(.text(pendingText))
                    pendingText = ""
                }
                // Ignore leading breaks, but retain up to two consecutive
                // markers so paragraph spacing remains distinct from <br>.
                if !cleaned.isEmpty {
                    cleaned.append(.lineBreak)
                }
            case .emoji, .link, .mention, .hashtag, .inlineCode, .codeBlock:
                if !pendingText.isEmpty {
                    cleaned.append(.text(pendingText))
                    pendingText = ""
                }
                cleaned.append(element)
            }
        }
        
        if !pendingText.isEmpty {
            cleaned.append(.text(pendingText))
        }
        
        // Remove trailing line breaks
        while cleaned.last == .lineBreak {
            cleaned.removeLast()
        }
        
        // Remove leading line breaks
        while cleaned.first == .lineBreak {
            cleaned.removeFirst()
        }
        
        // Collapse multiple consecutive line breaks to max 2
        var result: [ContentElement] = []
        var lineBreakCount = 0
        for element in cleaned {
            if element == .lineBreak {
                lineBreakCount += 1
                if lineBreakCount <= 2 {
                    result.append(element)
                }
            } else {
                lineBreakCount = 0
                result.append(element)
            }
        }
        
        return normalizingCodeBlockBoundaries(result)
    }

    /// One generated line break immediately next to a block is redundant with the
    /// block layout spacing. Preserve additional breaks so author-intended blank lines remain.
    private static func normalizingCodeBlockBoundaries(
        _ elements: [ContentElement]
    ) -> [ContentElement] {
        var result: [ContentElement] = []
        var skipNextLineBreak = false

        for element in elements {
            if case .codeBlock = element {
                if result.last == .lineBreak {
                    result.removeLast()
                }
                result.append(element)
                skipNextLineBreak = true
                continue
            }

            if element == .lineBreak, skipNextLineBreak {
                skipNextLineBreak = false
                continue
            }

            skipNextLineBreak = false
            result.append(element)
        }

        return result
    }
    
    /// Build AttributedString from elements
    private static func buildAttributedString(from elements: [ContentElement]) -> AttributedString {
        var result = AttributedString()
        
        for element in elements {
            switch element {
            case .text(let text):
                result += AttributedString(text)
                
            case .link(let text, let url):
                var linkAttr = AttributedString(text)
                linkAttr.link = url
                linkAttr.foregroundColor = .blue
                result += linkAttr
                
            case .mention(let username, let url):
                var mentionAttr = AttributedString(username)
                mentionAttr.link = url
                mentionAttr.foregroundColor = .blue
                result += mentionAttr
                
            case .hashtag(let tag, let url):
                var tagAttr = AttributedString(tag)
                tagAttr.link = url
                tagAttr.foregroundColor = .blue
                result += tagAttr
                
            case .emoji(let shortcode, let url, _):
                // For now, we'll use the shortcode text
                // In a full implementation, we'd load the image and use NSTextAttachment
                var emojiAttr = AttributedString(":\(shortcode):")
                // Store URL in custom attribute for later image loading
                emojiAttr.link = url
                result += emojiAttr

            case .inlineCode(let code):
                var codeAttr = AttributedString(code)
                codeAttr.font = .system(.body, design: .monospaced)
                result += codeAttr

            case .codeBlock(let code):
                var codeAttr = AttributedString(code)
                codeAttr.font = .system(.callout, design: .monospaced)
                result += codeAttr
                
            case .lineBreak:
                result += AttributedString("\n")
            }
        }
        
        return result
    }
}

// MARK: - ContentElement Extension

nonisolated extension ContentElement {
    var isSpaceOrLineBreak: Bool {
        switch self {
        case .text(let text):
            return text.trimmingCharacters(in: .whitespaces).isEmpty
        case .lineBreak:
            return true
        default:
            return false
        }
    }
}

nonisolated extension Array where Element == ContentElement {
    /// Whether the custom emoji at `index` needs a space added before it so it doesn't touch
    /// the text in front. Text that already ends with whitespace has one.
    func emojiNeedsSpace(before index: Int) -> Bool {
        guard index > 0 else { return false }
        switch self[index - 1] {
        case .lineBreak:
            return false
        case .text(let text):
            return !(text.last?.isWhitespace ?? true)
        default:
            return true
        }
    }

    /// Whether the custom emoji at `index` needs a space added after it. Text that already
    /// starts with whitespace has one.
    func emojiNeedsSpace(after index: Int) -> Bool {
        guard index < count - 1 else { return false }
        switch self[index + 1] {
        case .lineBreak:
            return false
        case .text(let text):
            return !(text.first?.isWhitespace ?? true)
        default:
            return true
        }
    }
}
