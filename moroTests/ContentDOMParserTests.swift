import Foundation
import Testing
@testable import moro

@MainActor
struct ContentDOMParserTests {
    private let base = URL(string: "https://social.example")!

    @Test func attributeVariantsAndNestedLabelsKeepTheFullDestination() {
        let destination = URL(string: "https://social.example/article?one=1&two=2")!
        for html in [
            "<p>阅读 <a title='a > b' href='/article?one=1&amp;two=2'><strong>完整</strong>链接</a>。</p>",
            "<p>阅读 <A HREF=\"/article?one=1&amp;two=2\"><span>完整链接</span></A>。</p>",
        ] {
            #expect(parse(html) == [.text("阅读 "), .link(text: "完整链接", url: destination), .text("。")])
        }
    }

    @Test func nestedInvisibleSpansAndMultipleClassesStayHidden() {
        let html = "<a href='/very/long/path'><span class='url invisible'><b>https://</b></span><span class='ellipsis url'>social.example/very</span><span class='invisible'>/long/path</span></a>"
        #expect(parse(html) == [.link(text: "social.example/very", url: URL(string: "https://social.example/very/long/path")!)])
    }

    @Test func whitespaceIsPreservedAcrossInlineNodes() {
        #expect(parse("<p>Hello <b>world</b> <i>and</i> 中文</p>").plainTextValue == "Hello world and 中文")
        #expect(parse("<p><a href='/a'>A</a> <a href='/b'>B</a></p>").plainTextValue == "A B")
        #expect(parse("<p>左<b>中</b>右</p>").plainTextValue == "左中右")
        #expect(parse("<p>A&nbsp;&nbsp;B</p>").plainTextValue == "A\u{00A0}\u{00A0}B")
    }

    @Test func entitiesDecodeExactlyOnceAndPlaceholdersStayLiteral() {
        #expect(parse("<p>&amp;lt;tag&amp;gt; &lt;tag&gt; &copy; &#x1F680; {{LINEBREAK}} {{MORO_PRESERVED_CODE_0}}</p>").plainTextValue
            == "&lt;tag&gt; <tag> © 🚀 {{LINEBREAK}} {{MORO_PRESERVED_CODE_0}}")
    }

    @Test func malformedHTMLUsesHTML5RecoveryInDocumentOrder() {
        #expect(parse("<p>第一段<p>第二段 <b>粗体<i>斜体</b>结尾</i>").plainTextValue == "第一段\n\n第二段 粗体斜体结尾")
        #expect(parse("<div>第一行</div><div>第二行<br/>第三行</div>").plainTextValue == "第一行\n第二行\n第三行")
    }

    @Test func codePreservesLiteralURLsShortcodesAndIndentation() {
        let result = parse("<p>Run <code>a &amp;lt; b</code>:</p><pre><code>  let x = &lt;value&gt;\n\n    https://example.com :wave:</code></pre>")
        #expect(result.contains(.inlineCode("a &lt; b")))
        #expect(result.contains(.codeBlock("  let x = <value>\n\n    https://example.com :wave:")))
        #expect(!result.contains { if case .link = $0 { true } else { false } })
    }

    @Test func adjacentBlockBoundariesDoNotMultiplyParagraphGaps() {
        #expect(parse("<p>一</p>\n  <p>二</p><p><br></p><p>三</p>").plainTextValue == "一\n\n二\n\n三")
        #expect(parse("<p>一<br>二</p>").plainTextValue == "一\n二")
    }

    @Test func quoteFallbackAndNonContentNodesAreExcluded() {
        let html = "<!-- comment --><script>bad()</script><style>body{}</style><p class='other quote-inline'>RE: <a href='/q'>quoted</a></p><p>正文<template>hidden</template></p>"
        #expect(parse(html).plainTextValue == "正文")
    }

    @Test func inlineImagesResolveKnownEmojiAndRespectAltOption() {
        let emoji = Status.Emoji(shortcode: "wave", url: URL(string: "https://cdn.example/wave.gif")!, staticURL: URL(string: "https://cdn.example/wave.png")!)
        let html = "<p>:wave: <img class='custom-emoji' alt=':wave:' src='ignored'> <img alt='描述'></p>"
        let elements = ContentParser.parseToElements(html: html, emojis: [emoji], options: .accountRichText)
        #expect(elements.filter { if case .emoji = $0 { true } else { false } }.count == 2)
        #expect(elements.plainTextValue == ":wave: :wave: 描述")
        #expect(parse("<p><img alt='描述'>正文</p>").plainTextValue == "正文")
    }

    @Test func nestedTagFooterIsRemovedButInlineProseAndMediaAreKept() {
        let tag = Status.Tag(name: "Swift", url: URL(string: "https://social.example/tags/Swift")!)
        let anchor = "<a href='/tags/Swift' rel='tag'>#<span>Swift</span></a>"
        func tagged(_ html: String) -> [ContentElement] {
            ContentParser.parseToElements(html: html, tags: [tag], contentBaseURL: base, options: .statusBody)
        }
        #expect(tagged("<p>正文</p><p><strong>\(anchor)</strong></p>").plainTextValue == "正文")
        #expect(tagged("<p>正文 \(anchor)</p>").plainTextValue == "正文 #Swift")
        #expect(tagged("<p>\(anchor)<img src='/image'></p>").plainTextValue == "#Swift")
        #expect(tagged("<p><a href='/tags/Swift'>阅读教程</a></p>").plainTextValue == "阅读教程")
    }

    @Test func parsingCacheKeepsAccountBaseURLAndOptionsSeparate() {
        let html = "<p><a href='/target'>link</a> <code>code</code></p>"
        let first = parse(html)
        let second = ContentParser.parseToElements(html: html, contentBaseURL: URL(string: "https://other.example"), options: [])
        #expect(first != second)
        #expect(second.contains(.link(text: "link", url: URL(string: "https://other.example/target")!)))
        #expect(second.plainTextValue == "link code")
        #expect(parse(html) == first)
    }

    @Test func deeplyNestedFormattingDoesNotRecurseInTheRendererAdapter() {
        let html = String(repeating: "<span>", count: 800) + "文本" + String(repeating: "</span>", count: 800)
        #expect(parse(html).plainTextValue == "文本")
    }

    private func parse(_ html: String) -> [ContentElement] {
        ContentParser.parseToElements(html: html, contentBaseURL: base, options: .statusBody)
    }
}
