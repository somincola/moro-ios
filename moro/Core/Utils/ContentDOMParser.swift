import Foundation
import SwiftSoup

/// Converts HTML into the existing native rendering vocabulary. HTML entities are
/// decoded once by SwiftSoup; no HTML rewriting or synthetic text placeholders occur.
enum ContentDOMParser {
    private struct Token {
        let element: ContentElement?
        var isKnownTag = false
    }

    static func parse(
        html: String,
        mentions: [Status.Mention]?,
        tags: [Status.Tag]?,
        emojis: [Status.Emoji]?,
        contentBaseURL: URL?,
        options: ContentParsingOptions
    ) -> [ContentElement] {
        guard let document = try? SwiftSoup.parseBodyFragment(
            html, contentBaseURL?.absoluteString ?? ""
        ), let body = document.body() else {
            return [.text(HTMLParser.stripHTML(html))]
        }

        var tokens: [Token] = []
        // An explicit stack avoids adding call-stack depth for deeply nested input.
        var pending: [(node: Node, closing: Bool)] = [(body, false)]
        while let (node, closing) = pending.popLast() {
            if let text = node as? TextNode {
                tokens.append(Token(element: .text(collapsingHTMLWhitespace(text.getWholeText()))))
                continue
            }
            guard let element = node as? Element, !isHidden(element) else { continue }
            let name = element.tagNameNormal()
            let breaks = blockSpacing(name)
            if closing {
                ensureBreaks(breaks, in: &tokens)
                continue
            }

            if name == "br" {
                tokens.append(Token(element: .lineBreak))
                continue
            }
            if options.contains(.preserveCodeSemantics), name == "pre" || name == "code" {
                let raw = visibleText(in: element, preserveBreaks: true)
                let code = name == "pre"
                    ? raw.trimmingCharacters(in: .newlines)
                    : collapsingHTMLWhitespace(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    tokens.append(Token(element: name == "pre" ? .codeBlock(code) : .inlineCode(code)))
                } else {
                    tokens.append(Token(element: nil))
                }
                continue
            }
            if name == "img" {
                // Even an image without a displayable ALT must prevent tag-only cleanup.
                tokens.append(Token(element: nil))
                let alt = (try? element.attr("alt")) ?? ""
                let shortcode = alt.hasPrefix(":") && alt.hasSuffix(":")
                    ? String(alt.dropFirst().dropLast()) : ""
                if let emoji = emojis?.first(where: {
                    $0.shortcode.caseInsensitiveCompare(shortcode) == .orderedSame
                }), !shortcode.isEmpty {
                    tokens.append(Token(element: .emoji(
                        shortcode: shortcode, url: emoji.url, staticURL: emoji.staticURL
                    )))
                } else if options.contains(.preserveInlineImageAltText), !alt.isEmpty {
                    tokens.append(Token(element: .text(alt)))
                }
                continue
            }
            if name == "a", let href = try? element.attr("href"), !href.isEmpty,
               let url = resolvedURL(href, baseURL: contentBaseURL) {
                let label = collapsingHTMLWhitespace(visibleText(in: element))
                let knownTag = label.hasPrefix("#") && (tags ?? []).contains { tag in
                    tag.name.caseInsensitiveCompare(String(label.dropFirst())) == .orderedSame
                        && (normalizedURL(tag.url) == normalizedURL(url)
                            || (isTagPath(url) && tag.name.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame))
                }
                let parsed: ContentElement
                if let mention = mentions?.first(where: { $0.url == url }) {
                    parsed = .mention(username: "@\(mention.username)", url: url)
                } else if label.hasPrefix("#"), knownTag || isTagPath(url) {
                    parsed = .hashtag(tag: label, url: url)
                } else if element.hasClass("mention"), label.hasPrefix("@") {
                    parsed = .mention(username: label, url: url)
                } else {
                    parsed = .link(text: label, url: url)
                }
                tokens.append(Token(element: parsed, isKnownTag: knownTag))
                continue
            }

            ensureBreaks(breaks, in: &tokens)
            if name == "li" { tokens.append(Token(element: .text("• "))) }
            if breaks > 0 { pending.append((element, true)) }
            pending.append(contentsOf: element.getChildNodes().reversed().map { ($0, false) })
        }

        if options.contains(.omitKnownHashtagLinks) { removeTrailingTagLines(from: &tokens) }
        return trimLineEdges(tokens.compactMap(\.element))
    }

    private static func isHidden(_ element: Element) -> Bool {
        element.hasClass("invisible") || element.hasClass("quote-inline")
            || ["script", "style", "template", "noscript"].contains(element.tagNameNormal())
    }

    private static func visibleText(in root: Element, preserveBreaks: Bool = false) -> String {
        var result = ""
        var pending = Array(root.getChildNodes().reversed())
        while let node = pending.popLast() {
            if let text = node as? TextNode {
                result += text.getWholeText()
            } else if let element = node as? Element, !isHidden(element) {
                if element.tagNameNormal() == "br" {
                    result += preserveBreaks ? "\n" : " "
                } else if element.tagNameNormal() == "img" {
                    result += (try? element.attr("alt")) ?? ""
                } else {
                    pending.append(contentsOf: element.getChildNodes().reversed())
                }
            }
        }
        return result.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func blockSpacing(_ name: String) -> Int {
        if name == "p" { return 2 }
        return ["div", "blockquote", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "hr"].contains(name) ? 1 : 0
    }

    private static func ensureBreaks(_ count: Int, in tokens: inout [Token]) {
        guard count > 0 else { return }
        while let last = tokens.last?.element, case .text(let text) = last,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tokens.removeLast()
        }
        let existing = tokens.reversed().prefix { $0.element == .lineBreak }.count
        if existing < count {
            tokens.append(contentsOf: Array(repeating: Token(element: .lineBreak), count: count - existing))
        }
    }

    /// Work backwards by displayed line. A barrier or any prose, code, unknown
    /// hashtag, or ordinary link stops removal, even if it has no visible output.
    private static func removeTrailingTagLines(from tokens: inout [Token]) {
        var end = tokens.count
        while end > 0 {
            if tokens[end - 1].element == .lineBreak { end -= 1; continue }
            var start = end - 1
            while start > 0, tokens[start - 1].element != .lineBreak { start -= 1 }
            let line = tokens[start..<end]
            let whitespaceOnly: (Token) -> Bool = { token in
                if case .text(let value) = token.element {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
            if line.allSatisfy(whitespaceOnly) { end = start; continue }
            guard line.contains(where: \.isKnownTag),
                  line.allSatisfy({ $0.isKnownTag || whitespaceOnly($0) }) else { break }
            tokens.removeSubrange(start..<end)
            end = start
        }
    }

    private static func trimLineEdges(_ elements: [ContentElement]) -> [ContentElement] {
        var result: [ContentElement] = []
        for element in elements {
            if element == .lineBreak {
                trimEnd(&result)
                result.append(element)
            } else if case .text(let value) = element {
                let text = result.isEmpty || result.last == .lineBreak
                    ? String(value.drop(while: { $0.isWhitespace })) : value
                if !text.isEmpty {
                    if case .text(let previous)? = result.last {
                        result[result.count - 1] = .text(previous + text)
                    } else {
                        result.append(.text(text))
                    }
                }
            } else {
                result.append(element)
            }
        }
        trimEnd(&result)
        return result
    }

    private static func trimEnd(_ elements: inout [ContentElement]) {
        guard case .text(let value)? = elements.last else { return }
        let trimmed = String(value.reversed().drop(while: { $0.isWhitespace }).reversed())
        elements.removeLast()
        if !trimmed.isEmpty { elements.append(.text(trimmed)) }
    }

    private static func collapsingHTMLWhitespace(_ text: String) -> String {
        // HTML collapses ASCII layout whitespace; NBSP and other Unicode spaces remain.
        text.replacingOccurrences(of: "[\\t\\r\\n\\x{000C} ]+", with: " ", options: .regularExpression)
    }

    private static func resolvedURL(_ href: String, baseURL: URL?) -> URL? {
        URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL
    }

    private static func isTagPath(_ url: URL) -> Bool {
        let path = url.pathComponents.filter { $0 != "/" }
        return path.count >= 2 && ["tag", "tags"].contains(path[path.count - 2].lowercased())
    }

    private static func normalizedURL(_ url: URL) -> String {
        (url.absoluteString.removingPercentEncoding ?? url.absoluteString)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
