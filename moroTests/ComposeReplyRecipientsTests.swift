import Foundation
import Testing
@testable import moro

@MainActor
struct ComposeReplyRecipientsTests {
    @Test func replyParticipantsAreCompleteBeforeTheEditorOpens() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchAccountHandler = { _ in requests += 1; return account("alice") }
        let model = makeModel(
            status(mentions: [mention("alice"), mention("me"), mention("bob"), mention("carol")]),
            api: api
        )

        #expect(model.isComposerReady)
        #expect(model.content == "@alice@example.com @bob@example.com @carol@example.com ")
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
        model.content += "Hello"
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
        #expect(model.content == "@alice@example.com @bob@example.com @carol@example.com Hello")
        #expect(requests == 0)
    }

    @Test func loadedThreadAccountsAvoidAnotherRequest() async {
        let cache = AccountCache()
        cache.cacheFromStatuses([status(author: "alice", parent: nil)])
        let model = makeModel(status(), cache: cache)
        #expect(model.isComposerReady)
        #expect(model.content == "@alice@example.com @bob@example.com ")
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
    }

    @Test(arguments: ["me", "bob"])
    func selfOrSameAuthorParentDoesNotRequireLookup(parent: String) async {
        let model = makeModel(status(parent: parent))
        #expect(model.isComposerReady)
        #expect(model.content == "@bob@example.com ")
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
    }

    @Test func replyingToSelfDoesNotAddOwnMentionOrWhitespace() {
        let model = makeModel(status(author: "me", parent: "me"))
        #expect(model.isComposerReady)
        #expect(model.content.isEmpty)
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

    @Test func missingRecipientKeepsPartialTextHiddenUntilReady() async throws {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(mentions: [mention("carol")]), api: api)
        #expect(model.replyRecipientsState == .pending)
        #expect(model.content.isEmpty)
        #expect(model.publishBlocker == .replyRecipientsUnavailable)
        do {
            _ = try await model.publish()
            Issue.record("Publishing must wait for reply recipients")
        } catch ComposeError.replyRecipientsUnavailable { }

        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        #expect(model.replyRecipientsState == .loading)
        #expect(model.content.isEmpty)
        gate.succeed(account("alice"))
        #expect(await preparation.value)
        #expect(model.isComposerReady)
        #expect(model.content == "@alice@example.com @bob@example.com @carol@example.com ")
    }

    @Test func concurrentAndRepeatedRepliesReuseTheAccountLookup() async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        let cache = AccountCache()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let first = makeModel(status(), api: api, cache: cache)
        let second = makeModel(status(), api: api, cache: cache)
        let firstTask = Task { await first.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        let started = AsyncStream<Void>.makeStream()
        let secondTask = Task {
            started.continuation.yield(())
            return await second.prepareReplyRecipientsIfNeeded()
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        gate.succeed(account("alice"))
        #expect(await firstTask.value)
        #expect(await secondTask.value)
        #expect(first.content == second.content)
        let reopened = makeModel(status(), api: api, cache: cache)
        #expect(reopened.isComposerReady)
        #expect(reopened.content == first.content)
        #expect(gate.requests == 1)
    }

    @Test func failedLookupCanRetryWithoutShowingPartialRecipients() async {
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchAccountHandler = { _ in
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return account("alice")
        }
        let model = makeModel(status(), api: api)
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
        #expect(model.replyRecipientsState == .failed)
        #expect(model.content.isEmpty)
        #expect(model.canPublish == false)
        #expect(await model.prepareReplyRecipientsIfNeeded())
        #expect(model.content == "@alice@example.com @bob@example.com ")
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
        #expect(requests == 2)
    }

    @Test func continuingWithKnownRecipientsFreezesAutomaticPrefill() async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(), api: api)
        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        #expect(model.continueWithKnownReplyRecipients())
        model.content += "Hello  \n"
        gate.succeed(account("alice"))
        #expect(await preparation.value == false)
        #expect(model.content == "@bob@example.com Hello  \n")
        #expect(model.isComposerReady)
    }

    @Test(arguments: [false, true])
    func lateLookupNeverOverwritesUserEdits(evenIfClearedAgain: Bool) async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(), api: api)
        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        model.content = "👋 已写的正文  \n"
        if evenIfClearedAgain { model.content = "" }
        let edited = model.content
        gate.succeed(account("alice"))
        #expect(await preparation.value == false)
        #expect(model.content == edited)
        #expect(model.isComposerReady)
    }

    @Test func restoringDraftDuringLookupIgnoresTheLateResponse() async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(), api: api)
        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        let source = makeModel(status(mentions: [mention("alice")]))
        source.content = "@bob@example.com 👋 草稿  \n"
        let draft = source.makeDraft(category: .manual)
        model.applyRestoredDraft(draft)
        gate.succeed(account("alice"))
        #expect(await preparation.value == false)
        #expect(model.content == draft.payload.content)
        #expect(model.activeDraftID == draft.id)
        #expect(model.isComposerReady)
    }

    @Test func initialDraftSkipsReplyRecipientPreparation() async {
        let source = makeModel(status())
        source.content = "@bob@example.com 未完成的草稿  \n"
        let draft = source.makeDraft(category: .manual)
        let model = ComposeViewModel(
            context: .reply(to: status()), apiClient: MockMastodonAPI(), currentUserID: "me",
            accountCache: AccountCache(), initialDraft: draft
        )
        #expect(model.isComposerReady)
        #expect(model.content == draft.payload.content)
        #expect(await model.prepareReplyRecipientsIfNeeded() == false)
    }

    @Test func cancellationDoesNotPopulateADismissedEditor() async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        let cache = AccountCache()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(), api: api, cache: cache)
        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        preparation.cancel()
        gate.succeed(account("alice"))
        #expect(await preparation.value == false)
        #expect(model.content.isEmpty)
        #expect(model.replyRecipientsState == .pending)
        // The shared request remains useful if the user opens another reply.
        #expect(makeModel(status(), api: api, cache: cache).isComposerReady)
    }

    @Test func clearingAccountCacheRejectsLateResults() async {
        let gate = ReplyAccountGate()
        let api = MockMastodonAPI()
        let cache = AccountCache()
        api.fetchAccountHandler = { try await gate.fetch(id: $0) }
        let model = makeModel(status(), api: api, cache: cache)
        let preparation = Task { await model.prepareReplyRecipientsIfNeeded() }
        await gate.waitForRequest()
        cache.clear()
        gate.succeed(account("alice"))
        #expect(await preparation.value == false)
        #expect(cache.count == 0)
        #expect(model.content.isEmpty)
        #expect(model.replyRecipientsState == .failed)
        api.fetchAccountHandler = { _ in account("alice") }
        #expect(await model.prepareReplyRecipientsIfNeeded())
        #expect(model.isComposerReady)
        #expect(model.content == "@alice@example.com @bob@example.com ")
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

@MainActor
private final class ReplyAccountGate {
    private let started = AsyncStream<Void>.makeStream()
    private var continuations: [CheckedContinuation<Account, Error>] = []
    private(set) var requests = 0

    func fetch(id: String) async throws -> Account {
        requests += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            started.continuation.yield(())
        }
    }

    func waitForRequest() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func succeed(_ account: Account) {
        continuations.forEach { $0.resume(returning: account) }
        continuations.removeAll()
    }
}
