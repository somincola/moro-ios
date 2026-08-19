//
//  TabBarIconTests.swift
//  moroTests
//


import UIKit
import XCTest

@testable import moro

final class TabBarIconTests: XCTestCase {
    func testDefaultTabBarUsesFlatSymbols() {
        let expected: [MainTab: (regular: String, selected: String)] = [
            .home: ("house", "house.fill"),
            .explore: ("magnifyingglass", "magnifyingglass"),
            .inbox: ("tray", "tray.fill"),
            .me: ("person", "person.fill"),
        ]

        XCTAssertEqual(Set(expected.keys), Set(MainTab.allCases))

        for tab in MainTab.allCases {
            let symbols = expected[tab]
            XCTAssertEqual(tab.defaultIcon, symbols?.regular, tab.rawValue)
            XCTAssertEqual(tab.defaultFilledIcon, symbols?.selected, tab.rawValue)
            XCTAssertFalse(tab.defaultIcon.contains("circle"), tab.rawValue)
            XCTAssertFalse(tab.defaultIcon.contains("square"), tab.rawValue)
            XCTAssertFalse(tab.defaultFilledIcon.contains("circle"), tab.rawValue)
            XCTAssertFalse(tab.defaultFilledIcon.contains("square"), tab.rawValue)
        }
    }

    func testFlatTabBarSymbolsExistInUIKit() {
        for tab in MainTab.allCases {
            XCTAssertNotNil(UIImage(systemName: tab.defaultIcon), tab.defaultIcon)
            XCTAssertNotNil(UIImage(systemName: tab.defaultFilledIcon), tab.defaultFilledIcon)
        }
    }
}
