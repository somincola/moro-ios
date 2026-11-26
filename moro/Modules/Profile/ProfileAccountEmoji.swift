import SwiftUI

/// Only the profile owner can supply missing emoji for that author's pinned byline.
struct ProfileAccountEmoji {
    var accountID: String?
    var emojis: [Account.Emoji] = []

    func applying(to account: Account) -> Account {
        guard account.id == accountID, !emojis.isEmpty else { return account }
        var codes = Set(account.emojis.map(\.shortcode))
        let missing = emojis.filter { codes.insert($0.shortcode).inserted }
        return missing.isEmpty ? account : account.updating(emojis: account.emojis + missing)
    }
}

extension EnvironmentValues {
    @Entry var profileAccountEmoji = ProfileAccountEmoji()
}

/// Mastodon may omit emoji used only in profile fields from the account payload.
/// Resolve those codes against the signed-in server only for accounts local to it.
struct ProfileEmojiSource: Equatable {
    let id: String
    let domain: String
    let isLocal: Bool
    let texts: [String]
    let embedded: [Account.Emoji]

    init?(account: Account?, server: URL?) {
        guard let account else { return nil }
        id = account.id
        domain = server?.host?.lowercased() ?? ""
        let host = account.acct.split(separator: "@").dropFirst().first
        isLocal = host == nil || host?.lowercased() == domain
        texts = [account.displayName, account.note] + account.fields.flatMap { [$0.name, $0.value] }
        embedded = account.emojis
    }

    var missingCodes: Set<String> {
        guard isLocal, !domain.isEmpty else { return [] }
        var codes = Set<String>()
        for text in texts where text.contains(":") {
            for match in text.matches(of: #/:([a-zA-Z0-9_-]+):/#) {
                codes.insert(String(match.1))
            }
        }
        return codes.subtracting(embedded.map(\.shortcode))
    }
}
