import Foundation

/// Shared parsing for the conversation body and the inbox's one-line preview.
/// Keep anchor labels (including Mastodon's ellipsis spans) and destinations intact.
enum ConversationMessageContent {
    static func elements(for status: Status) -> [ContentElement] {
        ContentParser.parseToElements(
            html: status.content,
            mentions: status.mentions,
            tags: status.tags,
            emojis: status.emojis,
            contentBaseURL: status.url,
            options: [.preserveInlineWhitespace, .preserveCodeSemantics,
                      .separateMentionsFromFollowingText, .autoDetectPlainLinks]
        )
    }

    static func summary(for status: Status) -> String {
        let body = elements(for: status).normalizedInlinePlainText
        if !body.isEmpty { return body }
        if let card = status.card {
            let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? card.url.absoluteString : title
        }
        if !status.mediaAttachments.isEmpty {
            return status.mediaAttachments.count == 1
                ? MoroL10n.DirectMessages.sentMedia1
                : MoroL10n.DirectMessages.sentMediaCount(status.mediaAttachments.count)
        }
        if status.poll != nil { return MoroL10n.DirectMessages.sentPoll }
        return MoroL10n.DirectMessages.noContent
    }
}
