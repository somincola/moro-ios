//
//  ProfileActionIconTests.swift
//  moroTests
//

import UIKit
import XCTest

@testable import moro

final class ProfileActionIconTests: XCTestCase {
    func testNotificationToggleUsesRequestedRelationshipSymbols() {
        XCTAssertEqual(
            NotificationToggleButton.systemImage(isNotifying: false),
            "person.fill.checkmark"
        )
        XCTAssertEqual(
            NotificationToggleButton.systemImage(isNotifying: true),
            "person.fill.xmark"
        )
    }

    func testNotificationToggleSymbolsExistInUIKit() {
        XCTAssertNotNil(UIImage(systemName: "person.fill.checkmark"))
        XCTAssertNotNil(UIImage(systemName: "person.fill.xmark"))
    }
}
