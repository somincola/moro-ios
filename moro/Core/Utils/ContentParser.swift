//
//  ContentParser.swift
//  moro
//
//  Parses Mastodon HTML content into AttributedString with clickable links.
//  Handles mentions, hashtags, and regular links.
//

import Foundation
import SwiftUI

/// Content element types for rendering
enum ContentElement: Equatable {
    case text(String)
    case link(text: String, url: URL)
    case mention(username: String, url: URL)
    case hashtag(tag: String, url: URL)
    case emoji(shortcode: String, url: URL, staticURL: URL)
    case inlineCode(String)
    case codeBlock(String)
    case lineBreak
}

struct ContentParsingOptions: OptionSet {
    let rawValue: Int

    static let preserveInlineImageAltText = ContentParsingOptions(rawValue: 1 << 0)
    static let autoDetectPlainLinks = ContentParsingOptions(rawValue: 1 << 1)
    static let autoDetectRemoteMentions = ContentParsingOptions(rawValue: 1 << 2)
    static let autoDetectPlainHashtags = ContentParsingOptions(rawValue: 1 << 3)
    static let omitKnownHashtagLinks = ContentParsingOptions(rawValue: 1 << 4)
    static let separateMentionsFromFollowingText = ContentParsingOptions(rawValue: 1 << 5)
    static let preserveCodeSemantics = ContentParsingOptions(rawValue: 1 << 6)

    static let accountRichText: ContentParsingOptions = [
        .preserveInlineImageAltText,
        .autoDetectPlainLinks,
        .autoDetectRemoteMentions,
        .autoDetectPlainHashtags,
    ]

    static let statusBody: ContentParsingOptions = [
        .omitKnownHashtagLinks,
        .separateMentionsFromFollowingText,
        .preserveCodeSemantics,
    ]
}

extension Array where Element == ContentElement {
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
struct ContentParser {
    private final class CachedElementsBox {
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

    private static let quoteInlineRegex = try? NSRegularExpression(
        pattern: "<p class=\"quote-inline\">.*?</p>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let preCodeRegex = try? NSRegularExpression(
        pattern: #"<pre\b[^>]*>\s*<code\b[^>]*>(.*?)</code>\s*</pre\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let preRegex = try? NSRegularExpression(
        pattern: #"<pre\b[^>]*>(.*?)</pre\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let inlineCodeRegex = try? NSRegularExpression(
        pattern: #"<code\b[^>]*>(.*?)</code\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let linkRegex = try? NSRegularExpression(
        pattern: "<a\\s+[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlTagRegex = try? NSRegularExpression(pattern: "<[^>]+>")
    private static let invisibleSpanRegex = try? NSRegularExpression(
        pattern: "<span class=\"invisible\">[^<]*</span>",
        options: [.caseInsensitive]
    )
    private static let ellipsisSpanRegex = try? NSRegularExpression(
        pattern: "<span class=\"ellipsis\">([^<]*)</span>",
        options: [.caseInsensitive]
    )
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

        var elements: [ContentElement] = []
        var workingHTML = html
        
        // Step 1: Remove invisible spans
        workingHTML = removeInvisibleSpans(workingHTML)

        if options.contains(.preserveInlineImageAltText) {
            workingHTML = HTMLParser.replacingInlineImageTagsWithAltText(workingHTML)
        }
        
        // Step 2: Remove quote-inline paragraphs
        if let quoteInlineRegex {
            workingHTML = quoteInlineRegex.stringByReplacingMatches(
                in: workingHTML,
                options: [],
                range: NSRange(workingHTML.startIndex..., in: workingHTML),
                withTemplate: ""
            )
        }

        let preservedCode: PreservedCodeResult
        if options.contains(.preserveCodeSemantics) {
            preservedCode = preservingCodeSemantics(in: workingHTML)
            workingHTML = preservedCode.html
        } else {
            preservedCode = PreservedCodeResult(html: workingHTML, fragments: [])
        }
        
        // Step 3: Preserve HTML semantics. A paragraph boundary leaves one
        // empty line (two newline markers); <br> remains one newline marker.
        workingHTML = HTMLParser.replacingParagraphTags(
            in: workingHTML,
            with: "{{LINEBREAK}}{{LINEBREAK}}"
        )
        workingHTML = HTMLParser.replacingLineBreakTags(in: workingHTML, with: "{{LINEBREAK}}")

        if options.contains(.omitKnownHashtagLinks) {
            workingHTML = removingKnownHashtagAnchors(
                from: workingHTML,
                tags: tags,
                contentBaseURL: contentBaseURL
            )
        }
        
        // Step 4: Extract and process links
        if let linkRegex {
            var lastEnd = workingHTML.startIndex
            let matches = linkRegex.matches(
                in: workingHTML,
                options: [],
                range: NSRange(workingHTML.startIndex..., in: workingHTML)
            )
            
            for match in matches {
                guard let fullRange = Range(match.range, in: workingHTML),
                      let hrefRange = Range(match.range(at: 1), in: workingHTML),
                      let textRange = Range(match.range(at: 2), in: workingHTML) else {
                    continue
                }
                
                // Add text before this link
                if lastEnd < fullRange.lowerBound {
                    let textBefore = String(workingHTML[lastEnd..<fullRange.lowerBound])
                    elements.append(
                        contentsOf: processTextSegment(
                            textBefore,
                            emojis: emojis,
                            contentBaseURL: contentBaseURL,
                            options: options,
                            codeFragments: preservedCode.fragments
                        )
                    )
                }
                
                let href = String(workingHTML[hrefRange])
                var linkText = String(workingHTML[textRange])
                
                // Clean up link text (remove remaining HTML tags and spans)
                if let htmlTagRegex {
                    linkText = htmlTagRegex.stringByReplacingMatches(
                        in: linkText,
                        options: [],
                        range: NSRange(linkText.startIndex..., in: linkText),
                        withTemplate: ""
                    )
                }
                linkText = HTMLParser.decodeEntities(linkText)
                
                guard let url = resolvedURL(from: href, contentBaseURL: contentBaseURL) else {
                    elements.append(.text(linkText))
                    lastEnd = fullRange.upperBound
                    continue
                }
                
                // Determine link type
                if let mention = mentions?.first(where: { $0.url.absoluteString == href }) {
                    // It's a mention
                    elements.append(.mention(username: "@\(mention.username)", url: url))
                } else if isHashtagURL(href, tags: tags) {
                    // It's a hashtag
                    let tagName = linkText.hasPrefix("#") ? linkText : "#\(linkText)"
                    elements.append(.hashtag(tag: tagName, url: url))
                } else {
                    // Regular link - show display text
                    elements.append(.link(text: linkText, url: url))
                }
                
                lastEnd = fullRange.upperBound
            }
            
            // Add remaining text after last link
            if lastEnd < workingHTML.endIndex {
                let remainingText = String(workingHTML[lastEnd...])
                elements.append(
                    contentsOf: processTextSegment(
                        remainingText,
                        emojis: emojis,
                        contentBaseURL: contentBaseURL,
                        options: options,
                        codeFragments: preservedCode.fragments
                    )
                )
            }
        } else {
            // No regex match, process as plain text
            elements.append(
                contentsOf: processTextSegment(
                    workingHTML,
                    emojis: emojis,
                    contentBaseURL: contentBaseURL,
                    options: options,
                    codeFragments: preservedCode.fragments
                )
            )
        }
        
        // Clean up: merge adjacent text elements and remove empty ones
        let cleaned = cleanupElements(elements)
        let normalized = options.contains(.separateMentionsFromFollowingText)
            ? separatingMentionsFromFollowingText(cleaned)
            : cleaned
        parseCache.setObject(CachedElementsBox(normalized), forKey: cacheKey)
        return normalized
    }

    /// Mastodon HTML commonly preserves a visual space after a mention as whitespace
    /// between the closing anchor and the next text node. Text-segment cleanup trims that
    /// boundary, so status bodies can render `@usertext` even though the source contained
    /// `@user text`. Restore exactly one separator before ordinary following text while
    /// keeping sentence punctuation, line breaks, and adjacent rich-text tokens untouched.
    private static func separatingMentionsFromFollowingText(
        _ elements: [ContentElement]
    ) -> [ContentElement] {
        guard elements.count > 1 else { return elements }

        var result = elements
        for index in elements.indices.dropLast() {
            guard case .mention = elements[index],
                  case .text(let text) = elements[elements.index(after: index)],
                  let firstScalar = text.unicodeScalars.first,
                  !CharacterSet.whitespacesAndNewlines.contains(firstScalar),
                  !mentionAttachedPunctuation.contains(firstScalar)
            else {
                continue
            }

            result[result.index(after: index)] = .text(" " + text)
        }
        return result
    }
    
    /// Check if URL is a hashtag URL
    private static func isHashtagURL(_ href: String, tags: [Status.Tag]?) -> Bool {
        guard let url = URL(string: href) else { return false }
        
        // Check if URL path contains "tags"
        let pathComponents = url.pathComponents
        guard pathComponents.contains("tags") || pathComponents.contains("tag") else {
            return false
        }
        
        // Match against known tags if available
        if let tags = tags {
            let lastComponent = url.lastPathComponent.lowercased()
            return tags.contains { $0.name.lowercased() == lastComponent }
        }
        
        return true
    }

    /// Status hashtag chips are rendered from the API's `tags` collection.
    /// Remove only anchors that can be matched back to that authoritative data;
    /// unknown tag-looking links remain visible instead of silently losing text.
    private static func removingKnownHashtagAnchors(
        from html: String,
        tags: [Status.Tag]?,
        contentBaseURL: URL?
    ) -> String {
        guard let linkRegex, let tags, !tags.isEmpty else { return html }

        let source = html as NSString
        let matches = linkRegex.matches(
            in: html,
            options: [],
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return html }

        let result = NSMutableString(string: html)
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let href = source.substring(with: match.range(at: 1))
            guard isKnownHashtagURL(
                href,
                tags: tags,
                contentBaseURL: contentBaseURL
            ) else {
                continue
            }
            result.replaceCharacters(in: match.range, with: "")
        }
        return result as String
    }

    private static func isKnownHashtagURL(
        _ href: String,
        tags: [Status.Tag],
        contentBaseURL: URL?
    ) -> Bool {
        guard let candidateURL = resolvedURL(from: href, contentBaseURL: contentBaseURL) else {
            return false
        }

        let candidateURLString = normalizedTagURLString(candidateURL)
        let candidateName = candidateURL.lastPathComponent.removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? candidateURL.lastPathComponent

        return tags.contains { tag in
            normalizedTagURLString(tag.url) == candidateURLString
                || tag.name.caseInsensitiveCompare(candidateName) == .orderedSame
        }
    }

    private static func normalizedTagURLString(_ url: URL) -> String {
        var value = (url.absoluteString.removingPercentEncoding ?? url.absoluteString)
            .lowercased()
        while value.last == "/" {
            value.removeLast()
        }
        return value
    }
    
    /// Remove invisible and ellipsis spans
    private static func removeInvisibleSpans(_ html: String) -> String {
        var result = html
        
        // Remove invisible spans
        if let invisibleSpanRegex {
            result = invisibleSpanRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        
        // Process ellipsis spans (keep content but remove span tags)
        if let ellipsisSpanRegex {
            result = ellipsisSpanRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        
        return result
    }

    private struct PreservedCodeFragment {
        let token: String
        let element: ContentElement
    }

    private struct PreservedCodeResult {
        let html: String
        let fragments: [PreservedCodeFragment]
    }

    /// Protect code from the general HTML/link parser so indentation, line breaks,
    /// punctuation, URLs, and emoji-like shortcodes remain literal code.
    private static func preservingCodeSemantics(in html: String) -> PreservedCodeResult {
        var result = html
        var fragments: [PreservedCodeFragment] = []

        replaceCodeMatches(
            in: &result,
            regex: preCodeRegex,
            isBlock: true,
            fragments: &fragments
        )
        replaceCodeMatches(
            in: &result,
            regex: preRegex,
            isBlock: true,
            fragments: &fragments
        )
        replaceCodeMatches(
            in: &result,
            regex: inlineCodeRegex,
            isBlock: false,
            fragments: &fragments
        )

        return PreservedCodeResult(html: result, fragments: fragments)
    }

    private static func replaceCodeMatches(
        in html: inout String,
        regex: NSRegularExpression?,
        isBlock: Bool,
        fragments: inout [PreservedCodeFragment]
    ) {
        guard let regex else { return }

        let matches = regex.matches(
            in: html,
            options: [],
            range: NSRange(html.startIndex..., in: html)
        )
        guard !matches.isEmpty else { return }

        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: html),
                  let contentRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let code = normalizedCode(String(html[contentRange]), isBlock: isBlock)
            guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                html.replaceSubrange(fullRange, with: "")
                continue
            }

            var token = "{{MORO_PRESERVED_CODE_\(fragments.count)}}"
            while html.contains(token) {
                token += "_"
            }
            let element: ContentElement = isBlock ? .codeBlock(code) : .inlineCode(code)
            fragments.append(PreservedCodeFragment(token: token, element: element))
            html.replaceSubrange(fullRange, with: token)
        }
    }

    private static func normalizedCode(_ html: String, isBlock: Bool) -> String {
        var code = HTMLParser.replacingLineBreakTags(in: html, with: "\n")
        if let htmlTagRegex {
            code = htmlTagRegex.stringByReplacingMatches(
                in: code,
                options: [],
                range: NSRange(code.startIndex..., in: code),
                withTemplate: ""
            )
        }
        code = HTMLParser.decodeEntities(code)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if isBlock {
            return code.trimmingCharacters(in: .newlines)
        }

        return code
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Process a text segment into elements
    private static func processTextSegment(
        _ text: String,
        emojis: [Status.Emoji]? = nil,
        contentBaseURL: URL? = nil,
        options: ContentParsingOptions = [],
        codeFragments: [PreservedCodeFragment] = []
    ) -> [ContentElement] {
        var elements: [ContentElement] = []
        
        // Split by line break markers
        let parts = text.components(separatedBy: "{{LINEBREAK}}")
        for (index, part) in parts.enumerated() {
            // Remove remaining HTML tags
            var cleanText = part
            if let htmlTagRegex {
                cleanText = htmlTagRegex.stringByReplacingMatches(
                    in: cleanText,
                    options: [],
                    range: NSRange(cleanText.startIndex..., in: cleanText),
                    withTemplate: ""
                )
            }
            cleanText = HTMLParser.decodeEntities(cleanText)
            cleanText = cleanText.trimmingCharacters(in: .whitespaces)
            
            if !cleanText.isEmpty {
                elements.append(
                    contentsOf: processTextWithCodeFragments(
                        cleanText,
                        emojis: emojis,
                        contentBaseURL: contentBaseURL,
                        options: options,
                        codeFragments: codeFragments
                    )
                )
            }
            
            // Add line break between parts (not after last)
            if index < parts.count - 1 {
                elements.append(.lineBreak)
            }
        }
        
        return elements
    }

    private static func processTextWithCodeFragments(
        _ text: String,
        emojis: [Status.Emoji]?,
        contentBaseURL: URL?,
        options: ContentParsingOptions,
        codeFragments: [PreservedCodeFragment]
    ) -> [ContentElement] {
        guard !codeFragments.isEmpty else {
            return processInlineText(
                text,
                emojis: emojis,
                contentBaseURL: contentBaseURL,
                options: options
            )
        }

        var elements: [ContentElement] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let nextFragment = codeFragments.compactMap { fragment -> (PreservedCodeFragment, Range<String.Index>)? in
                guard let range = text.range(
                    of: fragment.token,
                    range: cursor..<text.endIndex
                ) else {
                    return nil
                }
                return (fragment, range)
            }.min { $0.1.lowerBound < $1.1.lowerBound }

            guard let (fragment, range) = nextFragment else {
                elements.append(
                    contentsOf: processInlineText(
                        String(text[cursor...]),
                        emojis: emojis,
                        contentBaseURL: contentBaseURL,
                        options: options
                    )
                )
                break
            }

            if cursor < range.lowerBound {
                elements.append(
                    contentsOf: processInlineText(
                        String(text[cursor..<range.lowerBound]),
                        emojis: emojis,
                        contentBaseURL: contentBaseURL,
                        options: options
                    )
                )
            }
            elements.append(fragment.element)
            cursor = range.upperBound
        }

        return elements
    }

    private enum InlineTokenMatch {
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

    private static func resolvedURL(from href: String, contentBaseURL: URL?) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }

        guard let contentBaseURL else {
            return URL(string: href)
        }

        return URL(string: href, relativeTo: contentBaseURL)?.absoluteURL
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
    
    /// Process emoji shortcodes in text
    private static func processEmojis(in text: String, emojis: [Status.Emoji]) -> [ContentElement] {
        var elements: [ContentElement] = []
        var lastEnd = text.startIndex
        
        // Pattern to match :shortcode: format
        if let emojiShortcodeRegex {
            let matches = emojiShortcodeRegex.matches(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text)
            )
            
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let shortcodeRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                
                // Add text before this emoji
                if lastEnd < fullRange.lowerBound {
                    let textBefore = String(text[lastEnd..<fullRange.lowerBound])
                    if !textBefore.isEmpty {
                        elements.append(.text(textBefore))
                    }
                }
                
                let shortcode = String(text[shortcodeRange])
                
                // Find matching emoji (case-insensitive per Mastodon spec)
                if let emoji = emojis.first(where: { $0.shortcode.caseInsensitiveCompare(shortcode) == .orderedSame }) {
                    // Store both url and staticURL in the element
                    // We'll choose which one to use at render time based on settings
                    elements.append(.emoji(shortcode: shortcode, url: emoji.url, staticURL: emoji.staticURL))
                } else {
                    // Emoji not found, keep as text
                    elements.append(.text(String(text[fullRange])))
                }
                
                lastEnd = fullRange.upperBound
            }
            
            // Add remaining text after last emoji
            if lastEnd < text.endIndex {
                let remaining = String(text[lastEnd...])
                if !remaining.isEmpty {
                    elements.append(.text(remaining))
                }
            }
        } else {
            // No emoji pattern match, return as text
            elements.append(.text(text))
        }
        
        return elements.isEmpty ? [.text(text)] : elements
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

extension ContentElement {
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
