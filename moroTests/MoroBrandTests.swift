//
//  MoroBrandTests.swift
//  moroTests
//


import XCTest

@testable import moro

final class MoroBrandTests: XCTestCase {
    func testCanonicalProductURLs() {
        XCTAssertEqual(MoroBrand.websiteURL.absoluteString, "https://getmoro.app/")
        XCTAssertEqual(MoroBrand.privacyPolicyURL.absoluteString, "https://getmoro.app/privacy")
        XCTAssertEqual(MoroBrand.termsOfUseURL.absoluteString, "https://getmoro.app/terms")
        XCTAssertEqual(MoroBrand.supportURL.absoluteString, "https://getmoro.app/support")

        for url in [
            MoroBrand.websiteURL,
            MoroBrand.privacyPolicyURL,
            MoroBrand.termsOfUseURL,
            MoroBrand.supportURL,
        ] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "getmoro.app")
        }
    }

    func testCanonicalContactAddresses() {
        XCTAssertEqual(MoroBrand.supportEmail, "support@somincola.com")
        XCTAssertEqual(MoroBrand.privacyEmail, "privacy@somincola.com")
        XCTAssertEqual(MoroBrand.legalEmail, "contract@somincola.com")
        XCTAssertEqual(FeedbackMailContext.supportEmail, MoroBrand.supportEmail)
    }
}
