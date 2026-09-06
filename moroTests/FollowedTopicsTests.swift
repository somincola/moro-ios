import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct FollowedTopicsTests {
    @Test func topicTransportUsesAuthenticatedTagEndpoints() async throws {
        TopicFixtureProtocol.reset()
        let client = TopicFixtureProtocol.makeClient()
        let original = try await client.fetchTag(name: "摄影")
        #expect(original.following == false)
        let followed = try await client.setTagFollowed(name: "摄影", followed: true)
        #expect(followed.following == true)
        let unfollowed = try await client.setTagFollowed(name: "摄影", followed: false)
        #expect(unfollowed.following == false)
        let requests = TopicFixtureProtocol.requests
        #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
        #expect(requests.map { $0.url!.path } == ["/api/v1/tags/摄影", "/api/v1/tags/摄影/follow", "/api/v1/tags/摄影/unfollow"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer a" })
    }

    @Test func failedFollowPreservesStateAndRepeatedTapSendsOnce() async throws {
        TopicFixtureProtocol.reset(failures: ["/api/v1/tags/Moro/follow": 1])
        let model = TopicFollowModel(apiClient: TopicFixtureProtocol.makeClient(), name: "Moro")
        await model.load()
        #expect(model.following == false)
        await model.toggle()
        #expect(model.error != nil)
        #expect(model.following == false)
        let first = Task { await model.toggle() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.isBusy)
        await model.toggle()
        await first.value
        #expect(model.following == true)
        #expect(model.error == nil)
        #expect(TopicFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count == 2)
    }

    @Test func failedInitialStateCanRetryWithoutMutation() async {
        TopicFixtureProtocol.reset(failures: ["/api/v1/tags/Moro": 1])
        let model = TopicFollowModel(apiClient: TopicFixtureProtocol.makeClient(), name: "Moro")
        await model.load()
        #expect(model.following == nil)
        #expect(model.error != nil)
        await model.toggle()
        #expect(TopicFixtureProtocol.requests.count == 1)
        await model.load()
        #expect(model.following == false)
        #expect(model.error == nil)
    }

    @Test func followedTopicsUseRelationshipCursorAndStopOnRepeatedCursor() async throws {
        TopicFixtureProtocol.reset(repeatsCursor: true)
        let client = TopicFixtureProtocol.makeClient()
        _ = try await client.setTagFollowed(name: "Moro", followed: true)
        let model = FollowedTopicsViewModel(apiClient: client)
        await model.load()
        #expect(model.tags.count == 2)
        #expect(model.nextMaxID == "relationship:2")
        await model.load()
        #expect(model.tags.count == 3)
        #expect(Set(model.tags.map(\.id)).count == 3)
        #expect(model.nextMaxID == nil)
        let requests = TopicFixtureProtocol.requests.count
        await model.load()
        #expect(TopicFixtureProtocol.requests.count == requests)
    }

    @Test func missingLinkIsNotReplacedWithATagID() async throws {
        TopicFixtureProtocol.reset(sendsNextLink: false)
        let client = TopicFixtureProtocol.makeClient()
        _ = try await client.setTagFollowed(name: "Moro", followed: true)
        let page = try await client.fetchFollowedTags(maxID: nil, limit: 2)
        #expect(page.tags.count == 2)
        #expect(page.nextMaxID == nil)
    }

    @Test func failedPageAndRefreshRetryTheirOriginalCursor() async throws {
        TopicFixtureProtocol.reset()
        let client = TopicFixtureProtocol.makeClient()
        _ = try await client.setTagFollowed(name: "Moro", followed: true)
        let model = FollowedTopicsViewModel(apiClient: client)
        await model.load()
        TopicFixtureProtocol.failNext("/api/v1/followed_tags")
        await model.load()
        #expect(model.tags.count == 2)
        #expect(model.nextMaxID == "relationship:2")
        #expect(model.error != nil)
        await model.retry()
        #expect(model.tags.count == 3)
        #expect(model.error == nil)
        await model.load(refresh: true)
        TopicFixtureProtocol.failNext("/api/v1/followed_tags")
        await model.load(refresh: true)
        #expect(model.tags.count == 2)
        await model.retry()
        let last = try #require(TopicFixtureProtocol.requests.last?.url)
        #expect(URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "max_id" } == false)
        #expect(model.tags.count == 2)
        #expect(model.error == nil)
    }

    @Test func failedRemovalKeepsRowUntilServerConfirms() async throws {
        TopicFixtureProtocol.reset(failures: ["/api/v1/tags/Swift/unfollow": 1])
        let model = FollowedTopicsViewModel(apiClient: TopicFixtureProtocol.makeClient())
        await model.load()
        let tag = try #require(model.tags.first { $0.name == "Swift" })
        await model.unfollow(tag)
        #expect(model.tags.contains { $0.id == tag.id })
        #expect(model.removalError != nil)
        let first = Task { await model.unfollow(tag) }
        try await Task.sleep(for: .milliseconds(20))
        await model.unfollow(tag)
        #expect(model.removing.contains(tag.id))
        await first.value
        #expect(!model.tags.contains { $0.id == tag.id })
        #expect(model.removalError == nil)
        #expect(model.removing.isEmpty)
    }

    @Test func accountsKeepIndependentFollowStateAndLists() async {
        TopicFixtureProtocol.reset()
        let a = TopicFollowModel(apiClient: TopicFixtureProtocol.makeClient(account: "a"), name: "Moro")
        let b = TopicFollowModel(apiClient: TopicFixtureProtocol.makeClient(account: "b"), name: "Moro")
        await a.load()
        await a.toggle()
        await b.load()
        #expect(a.following == true)
        #expect(b.following == false)
        let list = FollowedTopicsViewModel(apiClient: TopicFixtureProtocol.makeClient(account: "b"))
        await list.load()
        #expect(list.tags.map(\.name) == ["Other"])
    }

    @Test func paginationOnlyAcceptsNextLinksForTheSameEndpoint() {
        let url = URL(string: "https://example.com/api/v1/followed_tags")!
        func response(_ link: String) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Link": link])!
        }
        #expect(MastodonLinkPagination.nextMaxID(in: response("</api/v1/followed_tags?max_id=7>; rel=\"prev\", </api/v1/followed_tags?max_id=abc%3A9>; rel=\"next\"")) == "abc:9")
        #expect(MastodonLinkPagination.nextMaxID(in: response("<https://other.example/api/v1/followed_tags?max_id=9>; rel=\"next\"")) == nil)
        #expect(MastodonLinkPagination.nextMaxID(in: response("</api/v1/tags?max_id=9>; rel=\"next\"")) == nil)
    }
}
