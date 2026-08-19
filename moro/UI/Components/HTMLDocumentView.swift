//
//  HTMLDocumentView.swift
//  moro
//
//  Renders the small "document" HTML that Mastodon's
//  `/api/v1/instance/extended_description` returns (headings, paragraphs, bullet
//  lists, <hr>, inline bold/italic/links) as themed SwiftUI views.
//
//  Block structure is laid out natively (so headings/lists actually look like
//  headings/lists and respect the Moro theme + dark mode); inline formatting is
//  handed to SwiftUI's own Markdown parser. We deliberately avoid
//  `NSAttributedString(html:)` — its defaults render black text that vanishes in
//  dark mode and ignore the app's typography.
//

import SwiftUI

struct HTMLDocumentView: View {
    let html: String

    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            ForEach(Array(HTMLDocumentParser.blocks(from: html).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: HTMLDocumentParser.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 1 ? theme.typography.title : (level == 2 ? theme.typography.subtitle : theme.typography.bodyStrong))
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            Text(inline(text))
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .listItem(let text):
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Text("•")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primary500)
                Text(inline(text))
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .rule:
            Divider()
        }
    }

    /// Render a block's inline Markdown (**bold**, *italic*, [links](url)). Falls back
    /// to plain text if the fragment isn't valid Markdown.
    private func inline(_ markdown: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(markdown)
    }
}

enum HTMLDocumentParser {
    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String)
        case rule
    }

    /// Convert the document HTML to a flat list of themed blocks. Inline emphasis is
    /// carried through as Markdown so the view layer can render it.
    static func blocks(from html: String) -> [Block] {
        var s = html

        // Inline links → Markdown links (must run before tags are stripped).
        s = s.replacing(#"<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)</a>"#, with: "[$2]($1)")

        // Inline emphasis → Markdown.
        for (pattern, repl) in [
            (#"</?(strong|b)\b[^>]*>"#, "**"),
            (#"</?(em|i)\b[^>]*>"#, "*"),
            (#"</?code\b[^>]*>"#, "`"),
        ] {
            s = s.replacing(pattern, with: repl)
        }

        // Block tags → line markers.
        let blockReplacements: [(String, String)] = [
            (#"<h1\b[^>]*>"#, "\n# "), (#"</h1>"#, "\n"),
            (#"<h2\b[^>]*>"#, "\n## "), (#"</h2>"#, "\n"),
            (#"<h[3-6]\b[^>]*>"#, "\n### "), (#"</h[3-6]>"#, "\n"),
            (#"<li\b[^>]*>"#, "\n- "), (#"</li>"#, "\n"),
            (#"<p\b[^>]*>"#, "\n"), (#"</p>"#, "\n"),
            (#"<br\b[^>]*/?>"#, "\n"),
            (#"<hr\b[^>]*/?>"#, "\n---\n"),
        ]
        for (pattern, repl) in blockReplacements {
            s = s.replacing(pattern, with: repl)
        }

        // Remaining tags (ul/ol/blockquote wrappers, spans, …) → gone.
        s = s.replacing(#"<[^>]+>"#, with: "")
        s = decodeEntities(s)

        var blocks: [Block] = []
        for rawLine in s.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line == "---" {
                blocks.append(.rule)
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                blocks.append(.listItem(String(line.dropFirst(2))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    private static func decodeEntities(_ input: String) -> String {
        var out = input
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
            "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
        ]
        for (entity, value) in named {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        // Numeric entities (&#1234;).
        out = out.replacing(#"&#(\d+);"#) { match in
            guard let code = UInt32(match), let scalar = Unicode.Scalar(code) else { return "" }
            return String(Character(scalar))
        }
        return out
    }
}

private extension String {
    /// Regex replace with a literal/template replacement string (supports `$1` groups).
    func replacing(_ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: template)
    }

    /// Regex replace where each first capture group is transformed by `transform`.
    func replacing(_ pattern: String, _ transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return self
        }
        let nsString = self as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length)) {
            result += nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let captured = match.numberOfRanges > 1 ? nsString.substring(with: match.range(at: 1)) : ""
            result += transform(captured)
            lastEnd = match.range.location + match.range.length
        }
        result += nsString.substring(from: lastEnd)
        return result
    }
}
