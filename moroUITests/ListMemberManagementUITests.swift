import XCTest

@MainActor
final class ListMemberManagementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTimelineManagesMembersInPlaceWithSearchAndRowLevelRetry() {
        let app = openLists(simulateSlowAdd: true)
        defer { app.terminate() }
        tap(app.buttons["lists.row.nav-list"])
        tap(app.buttons["lists.timeline.members"])
        let title = "Members of Navigation list fixture"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        let search = app.textFields["listMembers.search"]
        tap(search)
        search.typeText("offline")
        let searchError = app.staticTexts["Search failed"]
        XCTAssertTrue(searchError.waitForExistence(timeout: 8))
        tap(app.buttons["listMembers.clear"])
        search.typeText("push")
        let add = app.buttons["listMembers.add.dm-push-author"]
        tap(add)
        let pending = app.descendants(matching: .any)["listMembers.pending.dm-push-author"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 4))
        XCTAssertFalse(searchError.exists)
        let rowError = app.descendants(matching: .any)["listMembers.error.dm-push-author"].firstMatch
        XCTAssertTrue(rowError.waitForExistence(timeout: 10))
        tap(add)
        let added = app.descendants(matching: .any)["listMembers.added.dm-push-author"].firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        XCTAssertFalse(rowError.exists)
        XCTAssertTrue(app.navigationBars[title].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "list-members-search"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)

        tap(app.buttons["listMembers.clear"])
        tap(app.buttons["listMembers.remove.dm-push-author"])
        XCTAssertTrue(app.staticTexts["This list has no members yet"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(app.navigationBars["Navigation list fixture"].waitForExistence(timeout: 5))
    }

    func testCreationAndListMenuOpenTheSameMemberPage() {
        let app = openLists()
        defer { app.terminate() }
        tap(app.buttons["lists.new"])
        let name = app.textFields["lists.editor.name"]
        tap(name)
        name.typeText("Book club")
        tap(app.buttons["lists.editor.save"])
        XCTAssertTrue(app.navigationBars["Members of Book club"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["listMembers.search"].exists)
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(app.buttons["lists.row.created-list"].waitForExistence(timeout: 5))
        let original = app.buttons["lists.row.nav-list"]
        original.press(forDuration: 0.7)
        tap(app.buttons["Members"])
        XCTAssertTrue(app.navigationBars["Members of Navigation list fixture"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(app.navigationBars["Lists"].waitForExistence(timeout: 5))
    }

    private func openLists(simulateSlowAdd: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_PUSH_OPEN", "UITEST_DISABLE_ANIMATIONS", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UITEST_PUSH_SCENARIO"] = "inbox"
        if simulateSlowAdd {
            app.launchEnvironment["UITEST_LIST_FAIL_ADD"] = "1"
            app.launchEnvironment["UITEST_LIST_ADD_DELAY"] = "3"
        }
        app.launch(isolatedFor: self)
        tap(app.buttons["mainTab.home"])
        tap(app.buttons["Timeline switcher"])
        tap(app.buttons["Lists"])
        return app
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        element.tap()
    }
}
