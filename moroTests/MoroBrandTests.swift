//
//  MoroBrandTests.swift
//  moroTests
//


import XCTest

@testable import moro

final class MoroBrandTests: XCTestCase {
    func testCanonicalProductURLs() {
        XCTAssertEqual(MoroBrand.websiteURL.absoluteString, "https://moro.somincola.com/")
        XCTAssertEqual(MoroBrand.privacyPolicyURL.absoluteString, "https://moro.somincola.com/privacy")
        XCTAssertEqual(MoroBrand.termsOfUseURL.absoluteString, "https://moro.somincola.com/terms")
        XCTAssertEqual(MoroBrand.supportURL.absoluteString, "https://moro.somincola.com/support")

        for url in [
            MoroBrand.websiteURL,
            MoroBrand.privacyPolicyURL,
            MoroBrand.termsOfUseURL,
            MoroBrand.supportURL,
        ] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "moro.somincola.com")
        }
    }

    func testCanonicalContactAddresses() {
        XCTAssertEqual(MoroBrand.supportEmail, "support@somincola.com")
        XCTAssertEqual(MoroBrand.privacyEmail, "privacy@somincola.com")
        XCTAssertEqual(MoroBrand.legalEmail, "contract@somincola.com")
        XCTAssertEqual(FeedbackMailContext.supportEmail, MoroBrand.supportEmail)
    }
}
