import Foundation
import Testing
import UIKit
@testable import moro

@MainActor
struct RichTextImmediateRenderingTests {
    @Test func compactBioParagraphsKeepLineBreaksLinksAndEmojiWithoutChangingPostSpacing() throws {
        let url = URL(string: "https://example.com/article")!
        let emojiURL = URL(string: "https://example.com/cat.png")!
        let elements = ContentParser.parseToElements(
            html: "<p>First 😀<br>Second</p><p><a href=\"\(url)\">全文 👋</a></p><p>Last :cat:</p>",
            emojis: [.init(shortcode: "cat", url: emojiURL, staticURL: emojiURL)],
            options: .accountRichText)
        var view = MixedTextEmojiView(elements: elements, emojiSize: 16, textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground,
            font: .systemFont(ofSize: 15), lineSpacing: 2)
        let original = view.buildAttributedString(emojiAssets: [:], textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground, underlinesLinks: true)
        view.paragraphSpacing = 6
        let compact = view.buildAttributedString(emojiAssets: [:], textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground, underlinesLinks: true)

        #expect(original.string == "First 😀\nSecond\n\n全文 👋\n\nLast  :cat:")
        #expect(compact.string == "First 😀\nSecond\n全文 👋\nLast  :cat:")
        for (text, spacing) in [("First", 0.0), ("Second", 6.0), ("全文 👋", 6.0), ("Last", 0.0)] {
            let range = (compact.string as NSString).range(of: text)
            let style = try #require(compact.attribute(.paragraphStyle, at: range.location,
                effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.paragraphSpacing == CGFloat(spacing))
            #expect(style.lineSpacing == 2)
        }
        let linkRange = (compact.string as NSString).range(of: "全文 👋")
        var effectiveRange = NSRange()
        #expect(compact.attribute(.link, at: linkRange.location,
            effectiveRange: &effectiveRange) as? URL == url)
        #expect(effectiveRange == linkRange)
        #expect(compact.attribute(.underlineStyle, at: linkRange.location,
            effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(elements.plainTextValue == "First 😀\nSecond\n\n全文 👋\n\nLast :cat:")
    }

    @Test func coldEmojiDoesNotDelayTheTextAndLinks() async throws {
        let url = URL(string: "https://\(UUID().uuidString).example/emoji.png")!
        let response = AsyncStream<Data?>.makeStream()
        defer { response.continuation.finish() }
        let coordinator = MixedTextEmojiView.Coordinator { _ in
            for await data in response.stream { return data }
            return nil
        }
        let elements: [ContentElement] = [
            .text(String(repeating: "Long body 中文 😀 ", count: 150)),
            .emoji(shortcode: "cat", url: url, staticURL: url),
            .link(text: "Article", url: URL(string: "https://example.com/article")!),
        ]
        let view = MixedTextEmojiView(elements: elements, emojiSize: 20, textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground)
        var initialText: NSAttributedString?
        let completed = AsyncStream<Void>.makeStream()
        coordinator.loadEmojiAssets(elements: elements, emojiSize: 20, initial: { assets in
            initialText = view.buildAttributedString(emojiAssets: assets, textColor: .label,
                linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground, underlinesLinks: false)
        }, completion: { _ in completed.continuation.yield(()); completed.continuation.finish() })

        let immediate = try #require(initialText)
        #expect(immediate.string.contains("Long body 中文 😀"))
        #expect(immediate.string.contains(":cat:"))
        #expect(immediate.string.hasSuffix("Article"))
        // The network result has deliberately not arrived at this point.
        response.continuation.yield(nil)
        for await _ in completed.stream { break }
    }

    @Test func anOldEmojiLoadCannotOverwriteReusedContent() async {
        let url = URL(string: "https://\(UUID().uuidString).example/emoji.png")!
        let response = AsyncStream<Data?>.makeStream()
        defer { response.continuation.finish() }
        let coordinator = MixedTextEmojiView.Coordinator { _ in
            for await data in response.stream { return data }
            return nil
        }
        var displayed = ""
        coordinator.loadEmojiAssets(elements: [.emoji(shortcode: "old", url: url, staticURL: url)],
            emojiSize: 20, initial: { _ in displayed = "old placeholder" },
            completion: { _ in displayed = "stale content" })
        #expect(displayed == "old placeholder")
        coordinator.loadEmojiAssets(elements: [.text("new content")], emojiSize: 20) { _ in displayed = "new content" }
        response.continuation.yield(nil)
        await Task.yield()
        #expect(displayed == "new content")
    }
}
