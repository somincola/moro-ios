//
//  AppIconChoiceTests.swift
//  moroTests
//
//  Guards that every alternate icon maps to a unique non-nil alternate name
//  (default = primary = nil).
//

import XCTest

@testable import moro

@MainActor
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

    func testRetiredStoredChoicesAreNoLongerSelectable() {
        XCTAssertNil(AppSettings.AppIconChoice(rawValue: "classic"))
        XCTAssertNil(AppSettings.AppIconChoice(rawValue: "lineElephant"))
    }

    func testRetiredSystemIconsRestoreThePrimaryIcon() async throws {
        for name in ["AppIconClassic", "AppIconLineElephant"] {
            let application = FakeIconApplication(alternateIconName: name)
            let manager = AppIconManager(application: application)

            let selection = try await manager.reconcileSelection()

            XCTAssertEqual(selection, .default)
            XCTAssertNil(application.alternateIconName)
            XCTAssertEqual(application.requestedNames.count, 1)
            XCTAssertNil(application.requestedNames[0])
        }
    }

    func testSupportedSystemSelectionsArePreserved() async throws {
        for choice in AppSettings.AppIconChoice.allCases {
            let application = FakeIconApplication(alternateIconName: choice.alternateIconName)
            let manager = AppIconManager(application: application)

            let selection = try await manager.reconcileSelection()

            XCTAssertEqual(selection, choice)
            XCTAssertEqual(application.alternateIconName, choice.alternateIconName)
            XCTAssertTrue(application.requestedNames.isEmpty)
        }
    }

    func testFailedRestorationCanRetryOnTheNextActivation() async throws {
        let application = FakeIconApplication(alternateIconName: "AppIconClassic")
        application.changeError = NSError(domain: "AppIconChoiceTests", code: 1)
        let manager = AppIconManager(application: application)

        do {
            _ = try await manager.reconcileSelection()
            XCTFail("A rejected reset must not be treated as success")
        } catch {
            XCTAssertEqual(application.alternateIconName, "AppIconClassic")
        }

        application.changeError = nil
        let selection = try await manager.reconcileSelection()
        XCTAssertEqual(selection, .default)
        XCTAssertNil(application.alternateIconName)
        XCTAssertEqual(application.requestedNames.count, 2)
    }
}

@MainActor
private final class FakeIconApplication: AppIconApplication {
    let supportsAlternateIcons = true
    var alternateIconName: String?
    var requestedNames: [String?] = []
    var changeError: Error?

    init(alternateIconName: String?) {
        self.alternateIconName = alternateIconName
    }

    func setAlternateIconName(
        _ alternateIconName: String?,
        completionHandler: (@Sendable (Error?) -> Void)?
    ) {
        requestedNames.append(alternateIconName)
        if changeError == nil {
            self.alternateIconName = alternateIconName
        }
        completionHandler?(changeError)
    }
}
