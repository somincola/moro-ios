import Foundation
import Testing
@testable import moro

@MainActor
struct ComposeAutocompleteTests {
    @Test(arguments: ["@", "Hi @han", "你好，@han", "(@han", "👋🏽 @hanna@remote.ex", "你好 @小明", "@山田太郎", "@用户@例子.中国"])
    func recognizesMentionAtCaret(_ text: String) throws {
        let token = try #require(ComposeAutocompleteToken.active(in: text, selection: end(of: text)))
        #expect(token.kind == .account)
        #expect((text as NSString).substring(with: token.range).hasPrefix("@"))
    }

    @Test(arguments: ["#", "试试 #中文话题", "👨‍👩‍👧‍👦 #Swift_UI", "#cafe\u{301}"])
    func recognizesUnicodeHashtags(_ text: String) throws {
        let token = try #require(ComposeAutocompleteToken.active(in: text, selection: end(of: text)))
        #expect(token.kind == .hashtag)
    }

    @Test(arguments: ["mail@example.com", "https://example.com/@han", "https://example.com/#tag", "https://example.com?q=@han", "name#tag", "@@han", "@han@@remote", "##tag", "@han ", "#tag\n", "Just text"])
    func ignoresNonTokensAndCompletedPrefills(_ text: String) {
        #expect(ComposeAutocompleteToken.active(in: text, selection: end(of: text)) == nil)
    }

    @Test func selectionAndMarkedTextDoNotTriggerSuggestions() {
        let text = "@han #话题"
        #expect(ComposeAutocompleteToken.active(in: text, selection: NSRange(location: 0, length: 4)) == nil)
        #expect(ComposeAutocompleteToken.active(in: text, selection: end(of: text), isComposing: true) == nil)
        #expect(ComposeAutocompleteToken.active(in: text, selection: NSRange(location: 100, length: 0)) == nil)
        #expect(ComposeAutocompleteToken.active(in: "👋 @h", selection: NSRange(location: 1, length: 0)) == nil)
    }

    @Test func replacingAtMiddleCaretKeepsUnicodePrefixAndTrailingBody() throws {
        let text = "👨‍👩‍👧‍👦 你好 @hanna 保留后面的正文"
        let selection = NSRange(location: ("👨‍👩‍👧‍👦 你好 @ha" as NSString).length, length: 0)
        let token = try #require(ComposeAutocompleteToken.active(in: text, selection: selection))
        #expect(token.query == "ha")
        let result = try #require(token.inserting("@hanna@remote.example", into: text, selection: selection))
        #expect(result.text == "👨‍👩‍👧‍👦 你好 @hanna@remote.example 保留后面的正文")
        #expect(result.selection == end(of: "👨‍👩‍👧‍👦 你好 @hanna@remote.example"))
    }

    @Test func insertingCompletionAddsOneTrailingSpaceAndStopsSuggestions() throws {
        let text = "👋 #Sw"
        let token = try #require(ComposeAutocompleteToken.active(in: text, selection: end(of: text)))
        let result = try #require(token.inserting("#SwiftUI", into: text, selection: end(of: text)))
        #expect(result.text == "👋 #SwiftUI ")
        #expect(result.selection == end(of: result.text))
        #expect(ComposeAutocompleteToken.active(in: result.text, selection: result.selection) == nil)
    }

    @Test func insertionPreservesPunctuationAndRejectsStaleSelection() throws {
        let text = "@han，你好"
        let selection = end(of: "@han")
        let token = try #require(ComposeAutocompleteToken.active(in: text, selection: selection))
        #expect(token.inserting("@hanna", into: text, selection: selection)?.text == "@hanna，你好")
        #expect(token.inserting("@hanna", into: text, selection: end(of: text)) == nil)
        #expect(token.inserting("@hanna", into: "@bob，你好", selection: selection) == nil)
    }

    @Test func searchesOnlyRequestedTypeWithoutResolvingPrefixes() async throws {
        let api = MockMastodonAPI()
        var queries: [String] = []
        api.searchHandler = { query, type, resolve, limit, offset in
            queries.append(query)
            #expect(!resolve)
            #expect(limit == 8)
            #expect(offset == nil)
            return SearchResults(hashtags: type == .hashtags ? [tag("SwiftUI"), tag("SwiftUI")] : [])
        }
        let model = ComposeAutocompleteModel(apiClient: api, debounce: .zero)
        await model.load(for: ComposeAutocompleteToken.active(in: "@", selection: end(of: "@")))
        #expect(queries.isEmpty)
        await model.load(for: ComposeAutocompleteToken.active(in: "@han", selection: end(of: "@han")))
        await model.load(for: ComposeAutocompleteToken.active(in: "#Sw", selection: end(of: "#Sw")))
        #expect(queries == ["han", "Sw"])
        #expect(api.searchCallTypes == [.accounts, .hashtags])
        #expect(model.suggestions.map(\.completion) == ["#SwiftUI"])
    }

    @Test func lateResponseCannotReopenSuggestionsAfterCaretMoves() async throws {
        let api = MockMastodonAPI()
        var continuation: CheckedContinuation<SearchResults, Error>?
        api.searchHandler = { _, _, _, _, _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let model = ComposeAutocompleteModel(apiClient: api, debounce: .zero)
        let token = ComposeAutocompleteToken.active(in: "#Sw", selection: end(of: "#Sw"))
        let pending = Task { await model.load(for: token) }
        while continuation == nil { await Task.yield() }
        pending.cancel()
        await model.load(for: nil)
        continuation?.resume(returning: SearchResults(hashtags: [tag("SwiftUI")]))
        await pending.value
        #expect(model.token == nil)
        #expect(model.suggestions.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func failedSearchRecoversWhenQueryChanges() async {
        let api = MockMastodonAPI()
        api.searchHandler = { _, _, _, _, _ in throw URLError(.notConnectedToInternet) }
        let model = ComposeAutocompleteModel(apiClient: api, debounce: .zero)
        await model.load(for: ComposeAutocompleteToken.active(in: "#Sw", selection: end(of: "#Sw")))
        #expect(model.searchFailed)
        #expect(!model.isSearching)
        api.searchHandler = { _, _, _, _, _ in SearchResults(hashtags: [tag("SwiftUI")]) }
        await model.load(for: ComposeAutocompleteToken.active(in: "#Swift", selection: end(of: "#Swift")))
        #expect(!model.searchFailed)
        #expect(model.suggestions.count == 1)
    }

    private func end(of text: String) -> NSRange { NSRange(location: text.utf16.count, length: 0) }
    private func tag(_ name: String) -> SearchTag {
        SearchTag(name: name, url: URL(string: "https://example.com/tags/\(name)")!, history: nil)
    }
}
