import XCTest

@testable import moro

@MainActor
final class StatusEngagementTests: XCTestCase {
    func testIndependentListsRetryTheSameCursorAndStopOnARepeatedLink() async {
        let api = MockMastodonAPI()
        let reader = ThreadReadingFixtures.other
        let author = ThreadReadingFixtures.author
        var calls: [String] = []
        var failOnce = true
        api.statusEngagementHandler = { id, kind, cursor in
            XCTAssertEqual(id, "original")
            calls.append("\(kind.rawValue)/\(cursor ?? "first")")
            if kind == .boosts { return StatusEngagementPage(accounts: [author], nextMaxID: nil) }
            guard let cursor else { return StatusEngagementPage(accounts: [reader], nextMaxID: "relation-7") }
            if failOnce { failOnce = false; throw URLError(.timedOut) }
            return StatusEngagementPage(accounts: [reader, author], nextMaxID: cursor)
        }
        let model = StatusEngagementViewModel(statusID: "original", apiClient: api)
        XCTAssertTrue(calls.isEmpty)
        await model.load(.favourites)
        await model.load(.boosts)
        await model.load(.favourites)
        await model.load(.favourites, after: "relation-7")
        XCTAssertEqual(model[.favourites].accounts, [reader])
        XCTAssertNotNil(model[.favourites].error)
        await model.load(.favourites, after: "relation-7")
        XCTAssertEqual(model[.favourites].accounts, [reader, author])
        XCTAssertEqual(model[.boosts].accounts, [author])
        XCTAssertNil(model[.favourites].nextMaxID)
        await model.load(.favourites, after: "relation-7")
        XCTAssertEqual(calls, ["favourited_by/first", "reblogged_by/first", "favourited_by/relation-7", "favourited_by/relation-7"])
    }
}
