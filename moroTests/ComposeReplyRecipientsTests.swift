import Foundation
import Testing
@testable import moro

@MainActor
struct ComposeReplyRecipientsTests {
    @Test func replyingToOriginalMentionsOnlyItsAuthor() {
        let model = makeModel(status(author: "alice", parent: nil))
        #expect(model.content == "@alice@example.com ")
        #expect(model.publishBlocker == nil)
    }

    @Test func replyingToReplyIncludesItsParentAuthorAndOtherMentions() {
        let model = makeModel(
            status(mentions: [mention("alice"), mention("me"), mention("bob"), mention("carol")])
        )
        #expect(model.content == "@alice@example.com @bob@example.com @carol@example.com ")
    }

    @Test(arguments: [false, true])
    func loadedDetailContextSuppliesParentAccount(focusOnReply: Bool) async {
        let root = status(author: "alice", parent: nil)
        let reply = status()
        let focused = focusOnReply ? reply : root
        let thread = ThreadedConversationModel(
            focusedStatus: focused,
            context: .init(ancestors: focusOnReply ? [root] : [], descendants: focusOnReply ? [] : [reply])
        )
        let threadCache = ThreadCache()
        threadCache.set(thread, for: focused.id)
        let cache = AccountCache()
        let api = MockMastodonAPI()
        let detail = StatusDetailViewModel(
            status: focused, apiClient: api, threadCache: threadCache, accountCache: cache
        )
        await detail.loadThread()

        let model = makeModel(reply, api: api, cache: cache)
        #expect(model.content == "@alice@example.com @bob@example.com ")
    }

    @Test(arguments: ["me", "bob"])
    func selfOrSameAuthorParentIsExcludedOrDeduplicated(parent: String) {
        let model = makeModel(status(parent: parent))
        #expect(model.content == "@bob@example.com ")
    }

    @Test func replyingToSelfDoesNotAddOwnMentionOrWhitespace() {
        let model = makeModel(status(author: "me", parent: "me"))
        #expect(model.content.isEmpty)
    }

    @Test func nestedReplyUsesItsKnownReplyAccountInsteadOfAlwaysMentioningRoot() {
        let cache = AccountCache()
        cache.cacheFromStatuses([status(author: "alice", parent: nil), status(author: "bob")])
        let model = makeModel(status(author: "carol", parent: "bob"), cache: cache)
        #expect(model.content == "@bob@example.com @carol@example.com ")
    }

    @Test func reblogUsesCanonicalParticipantsAndPreservesRemoteDomains() {
        let target = status(parent: nil, mentions: [mention("other-bob", acct: "bob@remote.example"), mention("me")])
        let wrapper = status(author: "booster", parent: nil, reblog: target)
        let model = makeModel(wrapper)
        #expect(model.content == "@bob@example.com @bob@remote.example ")
        #expect(model.originalStatus?.id == target.id)
    }

    @Test func mentionIDsAndNormalizedHandlesAreDeduplicated() {
        let model = makeModel(status(mentions: [
            mention("alice", acct: "@alice@example.com"),
            mention("alice", acct: "old-alice@example.com"),
            mention("alias", acct: "ALICE@example.com"),
            mention("bob"), mention("me")
        ]))
        #expect(model.content == "@alice@example.com @bob@example.com ")
    }

    @Test func emptyMentionHandleUsesItsUsername() {
        let model = makeModel(status(parent: nil, mentions: [mention("local-user", acct: "")]))
        #expect(model.content == "@bob@example.com @local-user ")
    }

    @Test func missingAccountUsesKnownRecipientsWithoutRequestOrBlocker() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchAccountHandler = { _ in requests += 1; return account("alice") }
        let model = makeModel(status(mentions: [mention("carol")]), api: api)

        #expect(model.content == "@bob@example.com @carol@example.com ")
        #expect(model.publishBlocker == nil)
        #expect(model.draftPersistenceBlocker == nil)
        model.content += "Hello"
        await Task.yield()
        #expect(model.content == "@bob@example.com @carol@example.com Hello")
        #expect(requests == 0)
    }

    @Test(arguments: [false, true])
    func laterCacheChangesLeaveTypedOrClearedContentAlone(clearText: Bool) {
        let cache = AccountCache()
        let model = makeModel(status(), cache: cache)
        model.content = clearText ? "" : "@bob@example.com 👋 已写的正文  \n"
        let edited = model.content
        cache.set(account("alice"))
        #expect(model.content == edited)
        cache.clear()
        #expect(model.content == edited)
    }

    @Test func reopeningUsesCurrentCacheWithoutChangingThePreviousEditor() {
        let cache = AccountCache()
        let first = makeModel(status(), cache: cache)
        #expect(first.content == "@bob@example.com ")
        cache.set(account("alice"))
        let reopened = makeModel(status(), cache: cache)
        #expect(reopened.content == "@alice@example.com @bob@example.com ")
        #expect(first.content == "@bob@example.com ")
    }

    @Test(arguments: [false, true])
    func restoredDraftKeepsItsExactText(initialDraft: Bool) {
        let source = makeModel(status())
        source.content = "@bob@example.com 👋 草稿  \n"
        let draft = source.makeDraft(category: .manual)
        let cache = AccountCache()
        cache.set(account("alice"))
        let model = ComposeViewModel(
            context: .reply(to: status()), apiClient: MockMastodonAPI(), currentUserID: "me",
            accountCache: cache, initialDraft: initialDraft ? draft : nil
        )
        if !initialDraft { model.applyRestoredDraft(draft) }
        cache.clear()
        #expect(model.content == draft.payload.content)
        #expect(model.activeDraftID == draft.id)
        #expect(model.draftPersistenceBlocker == nil)
    }

    private func makeModel(_ status: Status, api: MastodonAPI? = nil, cache: AccountCache? = nil) -> ComposeViewModel {
        ComposeViewModel(context: .reply(to: status), apiClient: api ?? MockMastodonAPI(),
                         currentUserID: "me", accountCache: cache ?? AccountCache())
    }

    private func account(_ id: String) -> Account {
        Account(id: id, username: id, acct: "\(id)@example.com", displayName: id, note: "",
                avatar: "", avatarStatic: "", header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 0)
    }

    private func mention(_ id: String, acct: String? = nil) -> Status.Mention {
        Status.Mention(id: id, username: id, url: URL(string: "https://example.com/@\(id)")!, acct: acct ?? "\(id)@example.com")
    }

    private func status(author: String = "bob", parent: String? = "alice", mentions: [Status.Mention] = [], reblog: Status? = nil) -> Status {
        Status(id: "status-\(author)", content: "<p>Reply</p>", createdAt: Date(), account: account(author),
               mediaAttachments: [], favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
               bookmarked: false, favourited: false, reblogged: false, reblog: reblog.map(Indirect.init),
               inReplyToID: parent.map { "status-\($0)" }, inReplyToAccountID: parent,
               mentions: mentions, filtered: nil)
    }
}
