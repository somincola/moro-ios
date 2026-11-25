import Foundation
import Testing
@testable import moro

@MainActor
struct QuoteAndNotificationPreviewTests {
    @Test func inlinePreviewCollapsesParagraphBreaksAndPreservesCustomEmoji() {
        let emojiURL = URL(string: "https://example.social/emoji/wave.png")!
        let emoji = Status.Emoji(shortcode: "wave", url: emojiURL, staticURL: emojiURL)
        let html = "<p>第一段内容 :wave:</p><p><br></p><p>第二段内容</p><p>第三段   有很多空格</p>"

        let compacted = ContentParser.parseToElements(
            html: html,
            emojis: [emoji],
            options: .statusBody
        )
        .compactedForInlinePreview

        #expect(compacted.containsCustomEmoji)
        #expect(!compacted.contains(.lineBreak))
        #expect(compacted.plainTextValue == "第一段内容 :wave: 第二段内容 第三段 有很多空格")
    }

    @Test func inlinePreviewFlattensWhitespaceOnlyHTMLToEmpty() {
        let html = "<p><br><br></p><p>   </p>"
        let compacted = ContentParser.parseToElements(html: html, options: .statusBody)
            .compactedForInlinePreview

        #expect(compacted.isEmpty)
    }

    @Test func inlinePreviewFlattensMultilineCodeBlocks() {
        let elements: [ContentElement] = [
            .text("Check this"),
            .lineBreak,
            .codeBlock("let a = 1\n\nlet b = 2"),
            .lineBreak,
            .text("done"),
        ]
        let compacted = elements.compactedForInlinePreview

        #expect(!compacted.contains(.lineBreak))
        #expect(compacted.plainTextValue == "Check this let a = 1 let b = 2 done")
    }

    @Test func quoteCardCompactionCollapsesDoubleParagraphGapsToSingleBreak() {
        let emojiURL = URL(string: "https://example.social/emoji/cat.png")!
        let emoji = Status.Emoji(shortcode: "cat", url: emojiURL, staticURL: emojiURL)
        let html = "<p>第一段 :cat:</p><p>第二段内容</p><p>第三段</p>"

        let compacted = ContentParser.parseToElements(
            html: html,
            emojis: [emoji],
            options: .statusBody
        )
        .compactedForQuoteCard

        #expect(compacted.containsCustomEmoji)
        #expect(compacted.plainTextValue == "第一段 :cat:\n第二段内容\n第三段")
        #expect(!compacted.plainTextValue.contains("\n\n"))
    }

    @Test func drawerPreferredWidthUsesSleekerProportionsAcrossScreenSizes() {
        #expect(MoroNavigationDrawer.preferredWidth(containerWidth: 375) == 270)
        #expect(MoroNavigationDrawer.preferredWidth(containerWidth: 402) == 288)
        #expect(MoroNavigationDrawer.preferredWidth(containerWidth: 440) == 288)
        #expect(MoroNavigationDrawer.preferredWidth(containerWidth: 874, leadingSafeInset: 62) == 350)
    }

    @Test func notificationQuotePresentationSeparatesInteractionsFromQuoteEventsAndAvoidsDoubleMedia() {
        let account = Account(
            id: "acc-1",
            username: "alice",
            acct: "alice",
            displayName: "Alice",
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 1,
            followingCount: 1,
            statusesCount: 1
        )
        let photo = Status.Attachment(
            id: "att-1",
            type: "image",
            url: URL(string: "https://example.social/photo.png")!
        )
        let quotedWithMedia = Status(
            id: "quoted-1",
            content: "<p>Quoted body</p>",
            createdAt: Date(),
            account: account,
            mediaAttachments: [photo],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false
        )
        let mainWithMediaAndQuote = Status(
            id: "main-1",
            content: "<p>Main body</p>",
            createdAt: Date(),
            account: account,
            mediaAttachments: [photo],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: Status.Quote(state: .accepted, quotedStatus: quotedWithMedia)
        )
        let mainWithoutMediaWithQuote = Status(
            id: "main-2",
            content: "<p>Main body</p>",
            createdAt: Date(),
            account: account,
            mediaAttachments: [],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: Status.Quote(state: .accepted, quotedStatus: quotedWithMedia)
        )
        let mainPendingQuote = Status(
            id: "main-3",
            content: "<p>Main body</p>",
            createdAt: Date(),
            account: account,
            mediaAttachments: [],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            quote: Status.Quote(state: .pending, quotedStatus: nil)
        )

        // Like / boost on a post that has both media and a quote -> compact 1-line inline hint (never a nested card).
        #expect(NotificationQuotePresentation.resolve(kind: .favourite, status: mainWithMediaAndQuote) == .inlineHint)
        #expect(NotificationQuotePresentation.resolve(kind: .reblog, status: mainWithMediaAndQuote) == .inlineHint)
        // Quote notification with NO main media -> full-width card WITH quoted thumbnail.
        #expect(
            NotificationQuotePresentation.resolve(kind: .quote, status: mainWithoutMediaWithQuote)
                == .fullWidthCard(showsQuotedThumbnail: true)
        )
        // Quote notification WITH main media -> full-width card WITHOUT second thumbnail (no double media).
        #expect(
            NotificationQuotePresentation.resolve(kind: .quote, status: mainWithMediaAndQuote)
                == .fullWidthCard(showsQuotedThumbnail: false)
        )
        // Quoted update already displays the quoted post as its primary preview -> no duplicate quote block.
        #expect(NotificationQuotePresentation.resolve(kind: .quotedUpdate, status: mainWithMediaAndQuote) == .none)
        // Pending quote renders placeholder badge.
        #expect(
            NotificationQuotePresentation.resolve(kind: .quote, status: mainPendingQuote)
                == .placeholder(.pending)
        )
    }
}
