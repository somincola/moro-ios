//
//  MoroWidgetSharedStoreTests.swift
//  moroTests
//


import XCTest
@testable import moro

final class MoroWidgetSharedStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MoroWidgetSharedStoreTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadSnapshotUsesNotificationUnreadCountWithoutAddingConversationUnread() throws {
        let account = MoroWidgetAccount(
            id: "account-1",
            username: "moro",
            acct: "moro@example.social",
            displayName: "Moro User",
            avatar: "https://example.social/avatar.gif",
            avatarStatic: "https://example.social/avatar.png",
            followersCount: 1_234,
            followingCount: 321
        )
        let updatedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let activeSession = ActiveSessionFixture(
            sessionID: "session-1",
            account: account,
            updatedAt: updatedAt
        )
        userDefaults.set(
            try JSONEncoder().encode(activeSession),
            forKey: "shared_active_account_session_snapshot_v1"
        )
        userDefaults.set(
            ["session-1": 7, "session-2": 99],
            forKey: "notification_unread_counts_by_session_v1"
        )
        userDefaults.set(
            ["session-1": ["conversation-1", "conversation-2", "conversation-2"]],
            forKey: "direct_message_unread_conversation_ids_by_session_v1"
        )
        let snapshot = try XCTUnwrap(MoroWidgetSharedStore.loadSnapshot(from: userDefaults))

        XCTAssertEqual(snapshot.sessionID, "session-1")
        XCTAssertEqual(snapshot.account, account)
        XCTAssertEqual(snapshot.unreadCount, 7)
        XCTAssertEqual(snapshot.account.followersCount, 1_234)
        XCTAssertEqual(snapshot.account.followingCount, 321)
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
    }

    func testLoadSnapshotReturnsNilWithoutActiveAccount() {
        XCTAssertNil(MoroWidgetSharedStore.loadSnapshot(from: userDefaults))
    }

    func testPreferredNameRemovesMastodonEmojiShortcodes() {
        let account = MoroWidgetAccount(
            id: "account-1",
            username: "moro",
            acct: "moro@example.social",
            displayName: "  Moro :verified:  User :party_parrot: ",
            avatar: "",
            avatarStatic: ""
        )

        XCTAssertEqual(account.preferredName, "Moro User")
    }

    func testLegacyAccountSnapshotDefaultsMissingProfileCountsToZero() throws {
        let updatedAt = Date(timeIntervalSinceReferenceDate: 234_567)
        let activeSession = LegacyActiveSessionFixture(
            sessionID: "session-legacy",
            account: LegacyAccountFixture(
                id: "account-legacy",
                username: "legacy",
                acct: "legacy@example.social",
                displayName: "Legacy",
                avatar: "",
                avatarStatic: ""
            ),
            updatedAt: updatedAt
        )
        userDefaults.set(
            try JSONEncoder().encode(activeSession),
            forKey: "shared_active_account_session_snapshot_v1"
        )

        let snapshot = try XCTUnwrap(MoroWidgetSharedStore.loadSnapshot(from: userDefaults))

        XCTAssertEqual(snapshot.account.followersCount, 0)
        XCTAssertEqual(snapshot.account.followingCount, 0)
    }

    func testHandoffIsConsumedExactlyOnce() {
        let now = Date(timeIntervalSinceReferenceDate: 500)
        MoroWidgetHandoffStore.write(destination: .inbox, now: now, to: userDefaults)

        let handoff = MoroWidgetHandoffStore.consume(from: userDefaults, now: now)

        XCTAssertEqual(handoff?.destination, .inbox)
        XCTAssertNil(MoroWidgetHandoffStore.consume(from: userDefaults, now: now))
    }

    func testWidgetDestinationsMatchSupportedQuickActions() {
        XCTAssertEqual(
            Set(MoroWidgetDestination.allCases),
            Set([.home, .compose, .search, .inbox, .profile])
        )
    }

    func testLegacyNotificationsDestinationDecodesAsInbox() throws {
        let data = try XCTUnwrap("\"notifications\"".data(using: .utf8))

        XCTAssertEqual(
            try JSONDecoder().decode(MoroWidgetDestination.self, from: data),
            .inbox
        )
    }

    @MainActor
    func testOpenIntentIsAvailableToHostApp() {
        _ = OpenMoroDestinationIntent(destination: .home)
    }

    func testExpiredHandoffIsDiscarded() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 500)
        MoroWidgetHandoffStore.write(destination: .compose, now: createdAt, to: userDefaults)

        let handoff = MoroWidgetHandoffStore.consume(
            from: userDefaults,
            now: createdAt.addingTimeInterval(601),
            maximumAge: 600
        )

        XCTAssertNil(handoff)
    }

    func testAvatarCacheIsInvalidatedWhenSourceURLChanges() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://example.social/avatar-v1.png"))
        let changedURL = try XCTUnwrap(URL(string: "https://example.social/avatar-v2.png"))
        let data = Data([1, 2, 3])
        MoroWidgetSharedStore.cacheAvatarData(
            data,
            accountID: "account-1",
            sourceURL: originalURL,
            in: userDefaults
        )

        XCTAssertEqual(
            MoroWidgetSharedStore.cachedAvatarData(
                accountID: "account-1",
                sourceURL: originalURL,
                from: userDefaults
            ),
            data
        )
        XCTAssertNil(
            MoroWidgetSharedStore.cachedAvatarData(
                accountID: "account-1",
                sourceURL: changedURL,
                from: userDefaults
            )
        )
    }
}

private struct ActiveSessionFixture: Encodable {
    let sessionID: String
    let account: MoroWidgetAccount
    let updatedAt: Date
}

private struct LegacyActiveSessionFixture: Encodable {
    let sessionID: String
    let account: LegacyAccountFixture
    let updatedAt: Date
}

private struct LegacyAccountFixture: Encodable {
    let id: String
    let username: String
    let acct: String
    let displayName: String
    let avatar: String
    let avatarStatic: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case acct
        case displayName = "display_name"
        case avatar
        case avatarStatic = "avatar_static"
    }
}
