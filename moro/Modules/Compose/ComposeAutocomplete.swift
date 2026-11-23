import Combine
import Foundation

/// Ranges use UTF-16, matching UITextView's selection (including emoji before a token).
struct ComposeAutocompleteToken: Hashable {
    enum Kind: String, Hashable {
        case account = "@"
        case hashtag = "#"
        case emoji = ":"

        // A search can use a localized display name; insertion uses the result's acct.
        private static let accountCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters)
            .union(CharacterSet(charactersIn: "_.-@"))
        private static let hashtagCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters)

        fileprivate func contains(_ character: Character) -> Bool {
            switch self {
            case .account:
                return character.unicodeScalars.allSatisfy {
                    Self.accountCharacters.contains($0)
                }
            case .hashtag:
                return character == "#" || character == "_" || character.unicodeScalars.allSatisfy {
                    Self.hashtagCharacters.contains($0)
                }
            case .emoji:
                return character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
            }
        }
    }

    let kind: Kind
    let query: String
    let range: NSRange

    static func active(in text: String, selection: NSRange, isComposing: Bool = false) -> Self? {
        guard !isComposing, selection.length == 0,
              selection.location >= 0, selection.location <= text.utf16.count,
              let caret = Range(selection, in: text)?.lowerBound,
              caret == text.endIndex || text.indices.contains(caret) else { return nil }

        for kind in [Kind.account, .hashtag, .emoji] {
            var start = caret
            while start > text.startIndex {
                let previous = text.index(before: start)
                guard kind.contains(text[previous]) else { break }
                start = previous
            }
            if kind == .emoji {
                guard start > text.startIndex, text[text.index(before: start)] == ":" else { continue }
                start = text.index(before: start)
            }
            guard start < caret, String(text[start]) == kind.rawValue else { continue }
            if start > text.startIndex {
                let previous = text[text.index(before: start)]
                // Do not treat an email address, URL path or fragment as a completion.
                let followsLocalizedText = kind == .emoji && !previous.isASCII
                guard followsLocalizedText || previous.isWhitespace || "([{\"'“‘，。！？；：、（【《「『,;!".contains(previous) else { continue }
            }
            if kind == .emoji, ComposeTextHighlighter.urlRanges(in: text).contains(where: {
                NSLocationInRange(start.utf16Offset(in: text), $0)
            }) { continue }

            var end = caret
            while end < text.endIndex, kind.contains(text[end]) {
                end = text.index(after: end)
            }
            let bodyStart = text.index(after: start)
            let body = text[bodyStart..<end]
            switch kind {
            case .account:
                let parts = body.split(separator: "@", omittingEmptySubsequences: false)
                guard parts.count <= 2, parts.count == 1 || !parts[0].isEmpty else { continue }
            case .hashtag:
                guard !body.contains("#") else { continue }
            case .emoji:
                // Also replace a closing colon when completing from the middle of a word.
                if end < text.endIndex, text[end] == ":" { end = text.index(after: end) }
            }
            return Self(kind: kind, query: String(text[bodyStart..<caret]), range: NSRange(start..<end, in: text))
        }
        return nil
    }

    func inserting(_ completion: String, into text: String, selection: NSRange) -> ComposeTextInsertionResult? {
        guard Self.active(in: text, selection: selection) == self,
              let tokenRange = Range(range, in: text) else { return nil }
        let tail = text[tokenRange.upperBound...]
        let needsSpace = tail.first.map { !$0.isWhitespace && !$0.isPunctuation } ?? true
        let replacement = completion + (needsSpace ? " " : "")
        return ComposeTextInsertionResult(
            text: text.replacingCharacters(in: tokenRange, with: replacement),
            selection: NSRange(location: range.location + replacement.utf16.count, length: 0)
        )
    }
}

enum ComposeSuggestion: Identifiable {
    case account(Account)
    case hashtag(SearchTag)
    case emoji(CustomEmoji)

    var id: String {
        switch self {
        case .account(let account): return "account.\(account.id)"
        case .hashtag(let tag): return "hashtag.\(tag.id)"
        case .emoji(let emoji): return "emoji.\(emoji.shortcode)"
        }
    }

    var completion: String {
        switch self {
        case .account(let account): return "@\(account.acct)"
        case .hashtag(let tag): return "#\(tag.name)"
        case .emoji(let emoji): return ":\(emoji.shortcode):"
        }
    }
}

@MainActor
final class ComposeAutocompleteModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    @Published private(set) var token: ComposeAutocompleteToken?
    @Published private(set) var suggestions: [ComposeSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchFailed = false

    private let apiClient: MastodonAPI
    private let debounce: Duration
    private(set) var emojiCatalog: CustomEmojiViewModel?
    private var catalogUpdates: AnyCancellable?

    init(apiClient: MastodonAPI, debounce: Duration = .milliseconds(250)) {
        self.apiClient = apiClient
        self.debounce = debounce
    }

    func useEmojiCatalog(for host: String?) {
        guard host != emojiCatalog?.domain else { return }
        objectWillChange.send()
        emojiCatalog = host.flatMap { EmojiService.shared.dequeueCustomEmojiViewModel(for: $0, apiClient: apiClient) }
        catalogUpdates = emojiCatalog?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Owned by SwiftUI's task(id:); changing text, caret or input mode cancels the old task.
    func load(for token: ComposeAutocompleteToken?) async {
        self.token = token
        suggestions = []
        searchFailed = false
        isSearching = false
        guard let token, token.kind != .emoji, !token.query.isEmpty else { return }
        isSearching = true

        do {
            try await Task.sleep(for: debounce)
            let results = try await apiClient.search(
                query: token.query,
                type: token.kind == .account ? .accounts : .hashtags,
                resolve: false,
                limit: 8,
                offset: nil
            )
            guard !Task.isCancelled, self.token == token else { return }
            var seen = Set<String>()
            let candidates = token.kind == .account
                ? results.accounts.map(ComposeSuggestion.account)
                : results.hashtags.map(ComposeSuggestion.hashtag)
            suggestions = candidates.filter { seen.insert($0.id).inserted }
            isSearching = false
        } catch {
            guard !Task.isCancelled, self.token == token else { return }
            isSearching = false
            searchFailed = true
        }
    }
}
