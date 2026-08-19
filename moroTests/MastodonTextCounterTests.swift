//
//  MastodonTextCounterTests.swift
//  moroTests
//
//  Unit coverage for the Mastodon-style character counter that the compose screen
//  relies on (URLs are a fixed 23 characters; a remote mention's @domain is dropped).
//

import XCTest

@testable import moro

final class MastodonTextCounterTests: XCTestCase {

    func testPlainTextCountsCharacters() {
        XCTAssertEqual(MastodonTextCounter.count(""), 0)
        XCTAssertEqual(MastodonTextCounter.count("Hello, world!"), 13)
    }

    func testURLCountsAsFixed23() {
        XCTAssertEqual(MastodonTextCounter.count("https://example.com"), 23)
        XCTAssertEqual(
            MastodonTextCounter.count("https://example.com/a/very/long/path/that/keeps/going"),
            23
        )
        // "hi " (3) + the URL (23).
        XCTAssertEqual(MastodonTextCounter.count("hi https://example.com/x"), 26)
    }

    func testRemoteMentionDropsDomain() {
        // @alice@mastodon.social is counted as @alice (6).
        XCTAssertEqual(MastodonTextCounter.count("@alice@mastodon.social"), 6)
        // A local mention has no @domain to drop.
        XCTAssertEqual(MastodonTextCounter.count("@bob"), 4)
    }

    func testMixedMentionAndURL() {
        // @alice (6) + space (1) + URL (23) = 30.
        XCTAssertEqual(MastodonTextCounter.count("@alice@host.tld https://x.io/y"), 30)
    }
}
