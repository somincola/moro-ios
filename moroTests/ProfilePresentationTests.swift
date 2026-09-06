import Foundation
import Testing
@testable import moro

@MainActor
struct ProfilePresentationTests {
    @Test @MainActor func featuredTagsNeedBothVisibilityAndContent() {
        let tags = [FeaturedTag(id: "1", name: "moro")]
        #expect(ProfilePresentationPreferences.shouldShowTags(enabled: true, tags: tags))
        #expect(!ProfilePresentationPreferences.shouldShowTags(enabled: false, tags: tags))
        #expect(!ProfilePresentationPreferences.shouldShowTags(enabled: true, tags: []))
        #expect(!ProfilePresentationPreferences.shouldShowTags(enabled: false, tags: []))
    }

    @Test @MainActor func featuredTagVisibilityPersistsWithoutCrossingAccounts() throws {
        let suite = "profile-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ProfilePresentationPreferences(defaults: defaults)
        first.setShowsFeaturedTags(false, accountKey: "A")
        let restored = ProfilePresentationPreferences(defaults: defaults)
        #expect(!restored.showsFeaturedTags(accountKey: "A"))
        #expect(restored.showsFeaturedTags(accountKey: "B"))
    }

    @Test func featuredTagsAcceptBothCountRepresentations() throws {
        for count in ["3", "\"3\""] {
            let data = Data("{\"id\":\"featured-id\",\"name\":\"日常\",\"statuses_count\":\(count)}".utf8)
            let tag = try JSONDecoder().decode(FeaturedTag.self, from: data)
            #expect(tag.statusesCount == 3)
            #expect(tag.id == "featured-id")
        }
    }

    @Test func taggedAccountQueriesIncludeTheTagForPinnedAndRegularPosts() throws {
        for pinned in [true, false] {
            let endpoint = MastodonEndpoint.accountStatuses(id: "author", maxID: nil, sinceID: nil,
                limit: 20, excludeReplies: true, excludeReblogs: false, onlyMedia: false,
                pinned: pinned, tagged: "日常")
            let items = try #require(endpoint.queryItems)
            #expect(items.first(where: { $0.name == "tagged" })?.value == "日常")
            #expect(!items.contains(where: { $0.name == "since_id" || $0.name == "max_id" }))
            #expect(items.contains(where: { $0.name == "pinned" }) == pinned)
        }
    }
}
