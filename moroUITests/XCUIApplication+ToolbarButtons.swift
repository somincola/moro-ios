import XCTest

extension XCUIApplication {
    /// On iOS 26+ the close/confirm buttons are system bar items (so iPhone Duo can move them
    /// into the vertical side bar), and those carry no accessibility identifier: match the
    /// identifier for earlier systems and the visible title otherwise.
    func toolbarButton(_ identifier: String, labels: [String]) -> XCUIElement {
        buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", identifier, labels)).firstMatch
    }

    /// Compose's publish button, in every state and test language.
    var composePostButton: XCUIElement {
        toolbarButton(
            "compose.postButton",
            labels: ["发布", "Post", "定时发布", "Schedule Post", "发布中", "Posting…", "安排中", "Scheduling…"]
        )
    }
}
