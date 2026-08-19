//
//  AppIconChoiceTests.swift
//  moroTests
//
//  Guards that every alternate icon maps to a unique non-nil alternate name
//  (default = primary = nil).
//

import XCTest

@testable import moro

final class AppIconChoiceTests: XCTestCase {

    func testDefaultHasNoAlternateIconName() {
        XCTAssertNil(AppSettings.AppIconChoice.default.alternateIconName)
        XCTAssertEqual(
            AppSettings.AppIconChoice.default.previewAssetName,
            "AppIconPreviewDefault"
        )
    }

    func testAlternatesHaveUniqueNonNilNames() {
        let alternates = AppSettings.AppIconChoice.allCases.filter { $0 != .default }
        let names = alternates.compactMap(\.alternateIconName)
        XCTAssertEqual(
            names.count, alternates.count, "every non-default icon needs an alternate name"
        )
        XCTAssertEqual(Set(names).count, names.count, "alternate icon names must be unique")
    }

    func testPromotedDefaultAndPreviousDefaultUseDifferentAssets() {
        XCTAssertEqual(
            AppSettings.AppIconChoice.classic.alternateIconName,
            "AppIconClassic"
        )
        XCTAssertEqual(
            AppSettings.AppIconChoice.classic.previewAssetName,
            "AppIconPreviewClassic"
        )
        XCTAssertNotEqual(
            AppSettings.AppIconChoice.default.previewAssetName,
            AppSettings.AppIconChoice.classic.previewAssetName
        )
    }
}
