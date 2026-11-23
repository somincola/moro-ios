import Foundation
import Testing
@testable import moro

@MainActor struct ComposeReadingTests {
    @Test func previewPreservesLiteralMarkupEntitiesEmojiAndFullLinks() {
        let text = "显示 <script>alert('x')</script> &lt; 😀\nhttps://example.com/path?a=1&b=2\n我用 #Swift 写作"
        let elements = ComposePreviewContent.elements(for: text)
        #expect(elements.plainTextValue == text)
        #expect(elements.contains { if case .link(_, let url) = $0 { return url.absoluteString == "https://example.com/path?a=1&b=2" }; return false })
    }

    @Test func previewUsesTheCurrentServersEmojiAndKeepsUnknownCodesAndLinks() {
        let original = URL(string: "https://example.org/cat.gif")!
        let still = URL(string: "https://example.org/cat.png")!
        let emoji = CustomEmoji(shortcode: "cat", url: original, staticURL: still, visibleInPicker: true, category: nil)
        let text = ":cat: :unknown: word:cat: :CAT: :cat: https://example.org/:cat:"
        let elements = ComposePreviewContent.elements(for: text, emojiLookup: ["cat": [emoji]])
        #expect(elements.filter { $0 == .emoji(shortcode: "cat", url: original, staticURL: still) }.count == 2)
        #expect(elements.contains(.text(" :unknown: word:cat: :CAT: ")))
        #expect(elements.contains { if case .link = $0 { return true }; return false })
    }

    @Test func reorderingPreservesMediaIdentityMetadataAndDraftOrder() {
        let model = ComposeViewModel(context: .newPost, apiClient: SearchFixtureProtocol.makeClient())
        model.mediaAttachments = (1...3).map { index in
            MediaAttachment(id: "\(index)", url: URL(string: "https://example.com/\(index).png")!,
                previewURL: nil, type: "image", description: "ALT \(index)", focus: "0,0", uploadState: .uploaded)
        }
        model.moveMedia(from: IndexSet(integer: 0), to: 3)
        #expect(model.mediaAttachments.map(\.id) == ["2", "3", "1"])
        #expect(model.mediaAttachments.map(\.description) == ["ALT 2", "ALT 3", "ALT 1"])
        #expect(model.mediaAttachments.allSatisfy { $0.focus == "0,0" && $0.uploadState.isUploaded })
        let restored = ComposeViewModel(context: .newPost, apiClient: SearchFixtureProtocol.makeClient(), initialDraft: model.makeDraft(category: .manual))
        #expect(restored.mediaAttachments.map(\.id) == ["2", "3", "1"])
        model.isPublishing = true
        model.moveMedia(from: IndexSet(integer: 0), to: 3)
        #expect(model.mediaAttachments.map(\.id) == ["2", "3", "1"])
    }
}
