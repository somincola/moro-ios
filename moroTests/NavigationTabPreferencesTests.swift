import XCTest

@testable import moro

@MainActor
final class NavigationTabPreferencesTests: XCTestCase {
    func testSavedLayoutFollowsTheAccountAcrossSessions() throws {
        let suite = "navigation-tab-layout-tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let viewer = makeSession("original", accountID: "1", instance: "https://social.example")
        let otherUser = makeSession("other-user", accountID: "2", instance: "https://social.example")
        let otherServer = makeSession("other-server", accountID: "1", instance: "https://elsewhere.example")
        let resignedIn = makeSession("new-id", accountID: "1", instance: "https://Social.Example:443/")
        let layout = NavigationTabLayout(tabs: [.lists, .home])
        let preferences = try XCTUnwrap(NavigationTabPreferences(session: viewer, defaults: defaults))

        preferences.save(layout)

        XCTAssertEqual(NavigationTabPreferences(session: resignedIn, defaults: defaults)?.load(), layout)
        XCTAssertEqual(NavigationTabPreferences(session: otherUser, defaults: defaults)?.load(), NavigationTabLayout())
        XCTAssertEqual(NavigationTabPreferences(session: otherServer, defaults: defaults)?.load(), NavigationTabLayout())
    }

    private func makeSession(_ id: String, accountID: String, instance: String) -> StoredAccountSession {
        let account = Account(
            id: accountID, username: "viewer", acct: "viewer", displayName: "Viewer",
            note: "", avatar: "", avatarStatic: "", header: "", headerStatic: "",
            followersCount: 0, followingCount: 0, statusesCount: 0
        )
        return StoredAccountSession(
            id: id, account: account, instanceURLString: instance,
            tokenStorageKey: "test-key", lastUsedAt: .distantPast
        )
    }
}
