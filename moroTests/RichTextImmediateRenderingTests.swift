import Foundation
import Testing
import UIKit
@testable import moro

@MainActor
struct RichTextImmediateRenderingTests {
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
