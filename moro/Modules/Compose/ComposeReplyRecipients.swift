import Foundation

/// Builds a complete reply prefix before the editor becomes available.
struct ComposeReplyRecipients {
    private struct Recipient {
        let id: String
        let acct: String

        init(account: Account) {
            id = account.id
            acct = account.acct.isEmpty ? account.username : account.acct
        }

        init(mention: Status.Mention) {
            id = mention.id
            acct = mention.acct.isEmpty ? mention.username : mention.acct
        }
    }

    private let recipients: [Recipient]
    let missingAccountID: String?

    var text: String {
        var seenIDs = Set<String>()
        var seenAccounts = Set<String>()
        let mentions = recipients.compactMap { recipient -> String? in
            let acct = recipient.acct.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !acct.isEmpty else { return nil }
            let mention = acct.hasPrefix("@") ? acct : "@\(acct)"
            guard seenIDs.insert(recipient.id).inserted,
                  seenAccounts.insert(mention.lowercased()).inserted else { return nil }
            return mention
        }
        return mentions.isEmpty ? "" : mentions.joined(separator: " ") + " "
    }

    @MainActor
    static func prepare(for status: Status, currentUserID: String?, accountCache: AccountCache) -> Self {
        let target = status.displayStatus
        let available = [Recipient(account: target.account)]
            + (target.mentions ?? []).map { Recipient(mention: $0) }
        var recipients: [Recipient] = []
        var missingAccountID: String?

        // Preserve the existing order: parent author, reply author, other participants.
        if target.inReplyToID != nil,
           let parentID = target.inReplyToAccountID, parentID != currentUserID {
            if let parent = available.first(where: { $0.id == parentID && !$0.acct.isEmpty }) {
                recipients.append(parent)
            } else if let parent = accountCache.get(id: parentID) {
                recipients.append(Recipient(account: parent))
            } else {
                missingAccountID = parentID
            }
        }

        recipients += available.filter { $0.id != currentUserID }
        return Self(recipients: recipients, missingAccountID: missingAccountID)
    }

    func resolving(with account: Account) -> Self {
        Self(recipients: [Recipient(account: account)] + recipients, missingAccountID: nil)
    }
}
