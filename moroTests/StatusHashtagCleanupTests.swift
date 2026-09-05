import Foundation
import Testing
@testable import moro

@MainActor
struct StatusHashtagCleanupTests {
    private let tagURL = URL(string: "https://social.example/tags/Swift")!
    private let anchor = #"<a href="https://social.example/tags/Swift" class="mention hashtag" rel="tag">#<span>Swift</span></a>"#

    @Test func inlineHashtagsKeepTheirPositionAndSurroundingText() {
        let adjacent = parse("<p>我用\(anchor)写了一个 App。</p>")
        #expect(adjacent.plainTextValue == "我用#Swift写了一个 App。")
        #expect(adjacent.contains(.hashtag(tag: "#Swift", url: tagURL)))

        let spaced = parse("<p>我用 \(anchor) 写了一个 App。</p>")
        #expect(spaced.plainTextValue == "我用 #Swift 写了一个 App。")
    }

    @Test func ordinaryLinkWithTheSameLastPathComponentIsPreserved() {
        let url = URL(string: "https://news.example/articles/Swift")!
        let result = parse(#"<p>阅读 <a href="https://news.example/articles/Swift">Swift 教程</a>。</p>"#)
        #expect(result.plainTextValue == "阅读 Swift 教程。")
        #expect(result.contains(.link(text: "Swift 教程", url: url)))
        let tagLikeLabel = parse(#"<p><a href="https://news.example/articles/Swift">#Swift</a></p>"#)
        #expect(tagLikeLabel == [.link(text: "#Swift", url: url)])
    }

    @Test func onlyAnUnambiguousTrailingTagRunIsRemoved() {
        #expect(parse("<p>正文</p><p>\(anchor) \(anchor)</p>").plainTextValue == "正文")
        #expect(parse("<p>正文<br>\(anchor)</p>").plainTextValue == "正文")
        #expect(parse("<p>\(anchor)</p><p>后面还有正文</p>").plainTextValue == "#Swift\n\n后面还有正文")
        #expect(parse("<p>正文</p><p>\(anchor)！</p>").plainTextValue == "正文\n\n#Swift！")
    }

    @Test func unknownTagsAndLinkedLabelsAreNotDeleted() {
        let unknown = #"<a href="https://social.example/tags/Other">#Other</a>"#
        #expect(parse("<p>正文</p><p>\(anchor) \(unknown)</p>").plainTextValue == "正文\n\n#Swift #Other")
        let prose = #"<a href="https://social.example/tags/Swift">更多教程</a>"#
        #expect(!parse("<p>正文</p><p>\(prose)</p>").plainTextValue.isEmpty)
        #expect(parse("<p>正文</p><p>\(prose)</p>").plainTextValue.contains("更多教程"))
    }

    @Test func codeAndInlineMediaPreventTagOnlyCleanup() {
        let code = parse("<p>正文</p><p><code>#Swift</code> \(anchor)</p>")
        #expect(code.contains(.inlineCode("#Swift")))
        #expect(code.contains(.hashtag(tag: "#Swift", url: tagURL)))
        let image = parse("<p><img src=\"https://example.com/emoji.png\" alt=\":wave:\"> \(anchor)</p>")
        #expect(image.contains(.hashtag(tag: "#Swift", url: tagURL)))
    }

    @Test func tagMatchingSupportsRelativeAndEncodedURLs() {
        let relative = #"<p>正文</p><p><a href="/tags/Swift">#Swift</a></p>"#
        #expect(parse(relative).plainTextValue == "正文")
        let chineseURL = URL(string: "https://social.example/tags/%E5%BC%80%E5%8F%91")!
        let result = ContentParser.parseToElements(
            html: #"<p>中文正文</p><p><a href="https://remote.example/tags/%E5%BC%80%E5%8F%91">#<span>开发</span></a></p>"#,
            tags: [Status.Tag(name: "开发", url: chineseURL)],
            options: .statusBody
        )
        #expect(result.plainTextValue == "中文正文")
    }

    private func parse(_ html: String) -> [ContentElement] {
        ContentParser.parseToElements(
            html: html,
            tags: [Status.Tag(name: "Swift", url: tagURL)],
            contentBaseURL: URL(string: "https://social.example"),
            options: .statusBody
        )
    }
}
