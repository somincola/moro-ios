import Combine
import Foundation
import Testing
@testable import moro

@MainActor
struct ComposePublishingTests {
    @Test func successfulSubmissionCannotPublishTwiceOrAutosaveAgain() async throws {
        let api = MockMastodonAPI()
        let status = try makeStatus()
        let feed = FeedCoordinator()
        var updates = 0
        let observation = feed.updates.sink { _ in updates += 1 }
        defer { observation.cancel() }
        api.publishStatusResultHandler = { _, _, _, _, _, _, _, _, _, _ in .posted(status) }
        let model = makeModel(api, feed: feed)

        _ = try await model.publish()
        _ = try await model.publish()
        #expect(api.publishIdempotencyKeys.count == 1)
        #expect(updates == 1)
        #expect(model.hasPublished && !model.isPublishing)
        #expect(!model.canPublish && !model.hasDraftableContent)
    }

    @Test func uncertainSubmissionAndRestoredDraftReuseTheSameRequestKey() async throws {
        let status = try makeStatus()
        for context: ComposeViewModel.ComposeContext in [.newPost, .reply(to: status), .quote(original: status)] {
            let api = MockMastodonAPI()
            var serverPosts = Set<String>()
            api.publishStatusResultHandler = { _, _, _, _, _, _, _, _, _, _ in
                let key = try #require(api.publishIdempotencyKeys.last ?? nil)
                if serverPosts.insert(key).inserted { throw APIError.timeout }
                return .posted(status)
            }
            let model = makeModel(api, context: context)
            do { _ = try await model.publish(); Issue.record("Expected the lost response") }
            catch { #expect(error is APIError) }
            #expect(model.canPublish && !model.hasPublished)
            let draft = model.makeDraft(category: .auto)
            let restoredDraft = try JSONDecoder().decode(ComposeDraft.self, from: JSONEncoder().encode(draft))
            let restored = ComposeViewModel(context: context, apiClient: api, currentUserID: "me", initialDraft: restoredDraft)
            restored.maxCharacters = 5_000
            _ = try await restored.publish()
            #expect(api.publishIdempotencyKeys.count == 2)
            #expect(api.publishIdempotencyKeys[0] == api.publishIdempotencyKeys[1])
            #expect(serverPosts.count == 1)
        }
    }

    @Test func changedContentAndPublishingOptionsGetNewKeys() async throws {
        let api = MockMastodonAPI()
        api.publishStatusResultHandler = { _, _, _, _, _, _, _, _, _, _ in throw APIError.timeout }
        let model = makeModel(api)
        let changes: [() -> Void] = [
            {}, { model.content += " changed" }, { model.visibility = .unlisted },
            { model.isContentWarningActive = true; model.contentWarning = "CW" },
            { model.selectedLanguageCode = "fr" }, { model.quotePolicy = .none },
            { model.isPollActive = true; model.pollOptions = ["One", "Two"] },
            { model.pollOptions.reverse() }, { model.pollMultiple = true },
        ]
        for change in changes {
            change()
            _ = try? await model.publish()
        }
        #expect(api.publishIdempotencyKeys.count == changes.count)
        #expect(Set(api.publishIdempotencyKeys.compactMap { $0 }).count == changes.count)
    }

    @Test func overlappingSubmitIsRejectedBeforeASecondRequest() async throws {
        let api = MockMastodonAPI()
        let status = try makeStatus()
        let started = AsyncStream<Void>.makeStream()
        let response = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish(); response.continuation.finish() }
        api.publishStatusResultHandler = { _, _, _, _, _, _, _, _, _, _ in
            started.continuation.yield(())
            for await _ in response.stream { break }
            return .posted(status)
        }
        let model = makeModel(api)
        let first = Task { try await model.publish() }
        for await _ in started.stream { break }
        #expect(model.isPublishing && !model.canPublish)
        do { _ = try await model.publish(); Issue.record("Expected overlapping submission to be rejected") }
        catch ComposeError.alreadyPublishing {}
        #expect(api.publishIdempotencyKeys.count == 1)
        response.continuation.yield(())
        _ = try await first.value
    }

    @Test func oldDraftWithoutAnAttemptStillDecodes() throws {
        let model = makeModel(MockMastodonAPI())
        let data = try JSONEncoder().encode(model.makeDraft(category: .manual))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "publishAttempt")
        let decoded = try JSONDecoder().decode(ComposeDraft.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.publishAttempt == nil)
        #expect(decoded.payload.content == model.content)
    }

    @Test func lostResponsesAreShownAsUnconfirmedInsteadOfSilentlySavingADraft() {
        #expect(ComposePublishFailure.message(for: APIError.timeout) == MoroL10n.Compose.publishUnconfirmed)
        #expect(ComposePublishFailure.message(for: APIError.decoding(URLError(.cannotDecodeContentData))) == MoroL10n.Compose.publishUnconfirmed)
        #expect(ComposePublishFailure.message(for: ComposeError.characterLimitExceeded) == MoroL10n.Compose.errorCharacterLimitExceeded)
    }

    private func makeModel(_ api: MockMastodonAPI, context: ComposeViewModel.ComposeContext = .newPost,
        feed: FeedCoordinator? = nil) -> ComposeViewModel {
        let model = ComposeViewModel(context: context, apiClient: api, currentUserID: "me", feedCoordinator: feed ?? FeedCoordinator())
        model.maxCharacters = 5_000
        model.content = String(repeating: "长文发布测试 😀 https://example.com/article\n", count: 60)
        return model
    }

    private func makeStatus() throws -> Status {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try #require(DateFormatting.parseISO8601(string))
        }
        return try decoder.decode(Status.self, from: JSONSerialization.data(withJSONObject: DirectMessagesFixtureProtocol.root))
    }
}
