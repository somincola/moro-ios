import Foundation
import SwiftUI
import Testing
import UIKit
@testable import moro

@MainActor
struct RichTextImmediateRenderingTests {
    @Test func tapActionsPreserveParsedLinksMentionsAndHashtags() {
        let links = [
            "https://biplus.date/@Blocklist/117347208588612359",
            "https://example.com/@alice",
            "https://example.com/users/alice/statuses/123",
            "https://example.com/accounts/123",
            "https://example.com/article?next=/@alice",
        ].map { URL(string: $0)! }
        let mentionURL = URL(string: "https://example.com/people/bob")!
        let tagURL = URL(string: "https://example.com/tags/Swift")!
        let html = links.map { "<a href=\"\($0)\">链接</a>" }.joined(separator: " ")
            + " <a class=\"mention\" href=\"\(mentionURL)\">@bob</a>"
            + " <a class=\"hashtag\" href=\"\(tagURL)\">#Swift</a>"
        let view = RichTextContentView(html: html, parsingOptions: .statusBody)

        for url in links {
            #expect(view.linkAction(for: url) == .link(url: url))
        }
        #expect(view.linkAction(for: mentionURL) == .mention(username: "bob", url: mentionURL))
        #expect(view.linkAction(for: tagURL) == .hashtag(tag: "Swift", url: tagURL))
    }

    @Test func nativeFieldLinksRemainInteractiveWhenTextSelectionIsDisabled() async throws {
        let url = URL(string: "https://example.com/field")!
        var openedURLs: [URL] = []
        let view = MixedTextEmojiView(
            elements: [.link(text: "Field", url: url)], emojiSize: 16, textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground,
            isSelectable: false, onOpenURL: { openedURLs.append($0) })
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 280, height: 100))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(50))
        host.view.layoutIfNeeded()
        var pending = [host.view!]
        var found: UITextView?
        while let child = pending.popLast() {
            if let textView = child as? UITextView { found = textView; break }
            pending.append(contentsOf: child.subviews)
        }
        let textView = try #require(found)
        #expect(textView.isSelectable && textView.isUserInteractionEnabled)
        try #require(textView.attributedText.length > 0)
        #expect(textView.attributedText.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
        let coordinator = try #require(textView.delegate as? MixedTextEmojiView.Coordinator)
        #expect(!coordinator.textView(textView, shouldInteractWith: url,
            in: NSRange(location: 0, length: 5)))
        #expect(openedURLs == [url])
    }

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

        #expect(original.string == "First 😀\nSecond\n\n全文 👋\n\nLast :cat:")
        #expect(compact.string == "First 😀\nSecond\n全文 👋\nLast :cat:")
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

    @Test func aLoadingEmojiHoldsItsFinalSpaceSoTheTextDoesNotMove() throws {
        let url = URL(string: "https://\(UUID().uuidString).example/emoji.png")!
        let elements: [ContentElement] = [
            .text("开头的一段文字"),
            .emoji(shortcode: "a_rather_long_custom_emoji_shortcode", url: url, staticURL: url),
            .text("后面还有一些文字，看看会不会换行"),
        ]
        let view = MixedTextEmojiView(elements: elements, emojiSize: 20, textColor: .label,
            linkColor: .systemBlue, codeBackgroundColor: .secondarySystemBackground,
            font: .systemFont(ofSize: 16))
        func build(_ assets: [URL: UIImage], pending: Set<URL>) -> NSAttributedString {
            view.buildAttributedString(emojiAssets: assets, textColor: .label, linkColor: .systemBlue,
                codeBackgroundColor: .secondarySystemBackground, underlinesLinks: false,
                pendingEmojiURLs: pending)
        }
        func height(_ text: NSAttributedString) -> CGFloat {
            let textView = UITextView()
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.attributedText = text
            return ceil(textView.sizeThatFits(CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height)
        }
        func attachment(in text: NSAttributedString) -> NSTextAttachment? {
            var found: NSTextAttachment?
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if let value = value as? NSTextAttachment { found = value }
            }
            return found
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }

        let loading = build([:], pending: [url])
        let loaded = build([url: image], pending: [])
        let failed = build([:], pending: [])

        let placeholder = try #require(attachment(in: loading))
        let emoji = try #require(attachment(in: loaded))
        #expect(placeholder.bounds == emoji.bounds)
        #expect(loading.string == loaded.string)
        #expect(height(loading) == height(loaded))
        // Only a failed download falls back to the readable shortcode.
        #expect(attachment(in: failed) == nil)
        #expect(failed.string.contains(":a_rather_long_custom_emoji_shortcode:"))
        #expect(height(failed) > height(loaded))
    }

    @Test func aTwoLinePreviewWithEmojiShowsTwoLinesLikeThePlainOne() {
        // Search shows a two-line bio preview. With emoji it used to collapse to one line.
        let text = String(repeating: "独立开发者，做一个轻盈的长毛象客户端。", count: 4)
        let font = UIFont.systemFont(ofSize: 15)
        func lines(limit: Int) -> Int {
            let view = MixedTextEmojiView(elements: [.text(text)], emojiSize: 14, textColor: .label,
                linkColor: .label, codeBackgroundColor: .clear, font: font, lineSpacing: 1,
                lineLimit: limit, lineBreakMode: .byTruncatingTail, isSelectable: false)
            let textView = UITextView()
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.textContainer.maximumNumberOfLines = limit
            textView.textContainer.lineBreakMode = .byTruncatingTail
            textView.attributedText = view.buildAttributedString(emojiAssets: [:], textColor: .label,
                linkColor: .label, codeBackgroundColor: .clear, underlinesLinks: false)
            let height = textView.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height
            return Int((height / font.lineHeight).rounded())
        }
        #expect(lines(limit: 2) == 2)
        #expect(lines(limit: 1) == 1)
    }

    @Test func emojiTextGroupsTextIntoAsFewRunsAsPossible() throws {
        let a = URL(string: "https://example.com/a.png")!
        let b = URL(string: "https://example.com/b.png")!
        let site = URL(string: "https://example.com/site")!
        let elements: [ContentElement] = [
            .text("Hi"), .emoji(shortcode: "a", url: a, staticURL: a), .text("there"),
            .link(text: "site", url: site), .lineBreak, .emoji(shortcode: "b", url: b, staticURL: b),
        ]
        let style = InlineTextStyle(textColor: .primary, linkColor: .blue,
            codeBackgroundColor: .gray, codeFontSize: 15)
        let runs = InlineTextRunBuilder.runs(for: elements, style: style)

        #expect(runs.count == 4)
        guard case .text(let first) = runs[0], case .emoji("a", a) = runs[1],
              case .text(let middle) = runs[2], case .emoji("b", b) = runs[3] else {
            Issue.record("Unexpected runs: \(runs)")
            return
        }
        // A space keeps each emoji apart from the words around it.
        #expect(String(first.characters) == "Hi ")
        #expect(String(middle.characters) == " theresite\n")
        let linkRange = try #require(middle.range(of: "site"))
        #expect(middle[linkRange].link == site)
        #expect(String(InlineTextRunBuilder.flattened(runs).characters) == "Hi :a: theresite\n:b:")
        #expect(InlineTextRunBuilder.emojiURLs(in: runs) == [a, b])

        // In a tappable row (search previews) links stay plain text.
        var plain = style
        plain.linksAreInteractive = false
        let plainRuns = InlineTextRunBuilder.runs(for: elements, style: plain)
        guard case .text(let plainMiddle) = plainRuns[2] else {
            Issue.record("Unexpected runs: \(plainRuns)")
            return
        }
        #expect(plainMiddle.runs.allSatisfy { $0.link == nil })
    }

    @Test func plainTextRenderingIsUnchangedByTheEmojiRunBuilder() {
        // Text without custom emoji still renders as one attributed string, exactly as before.
        let url = URL(string: "https://example.com/tags/moro")!
        let view = RichTextContentView(
            elements: [.text("你好 "), .hashtag(tag: "#moro", url: url), .lineBreak, .inlineCode("x")])
        #expect(view.elements.count == 4)
        let runs = InlineTextRunBuilder.runs(
            for: view.elements,
            style: InlineTextStyle(textColor: .primary, linkColor: .blue, codeBackgroundColor: .gray, codeFontSize: 15))
        #expect(runs.count == 1)
        #expect(String(InlineTextRunBuilder.flattened(runs).characters) == "你好 #moro\nx")
    }

    @Test func theLoaderReportsWhichEmojiAreStillLoading() async throws {
        let url = URL(string: "https://\(UUID().uuidString).example/emoji.png")!
        let response = AsyncStream<Data?>.makeStream()
        let coordinator = MixedTextEmojiView.Coordinator { _ in
            for await data in response.stream { return data }
            return nil
        }
        var pendingDuringInitial: Set<URL> = []
        var pendingDuringCompletion: Set<URL> = [url]
        var deliveredAsync = false
        let completed = AsyncStream<Void>.makeStream()
        coordinator.loadEmojiAssets(
            elements: [.emoji(shortcode: "cat", url: url, staticURL: url)], emojiSize: 20,
            initial: { _ in pendingDuringInitial = coordinator.pendingEmojiURLs },
            completion: { _ in
                pendingDuringCompletion = coordinator.pendingEmojiURLs
                deliveredAsync = coordinator.isDeliveringLoadedEmoji
                completed.continuation.yield(())
                completed.continuation.finish()
            })

        #expect(pendingDuringInitial == [url])
        response.continuation.yield(nil)
        response.continuation.finish()
        for await _ in completed.stream { break }
        #expect(pendingDuringCompletion.isEmpty)
        #expect(deliveredAsync)
        #expect(!coordinator.isDeliveringLoadedEmoji)
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
