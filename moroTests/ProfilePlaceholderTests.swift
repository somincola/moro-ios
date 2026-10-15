//
//  ProfilePlaceholderTests.swift
//  moroTests
//

import Foundation
import SwiftUI
import Testing

@testable import moro

extension moroTests {
    @Test func placeholderGlyphKeepsOneCJKCharacterOrTwoLatinLetters() {
        #expect(ProfilePlaceholderPalette.glyph(from: "MT") == "MT")
        #expect(ProfilePlaceholderPalette.glyph(from: "mo") == "MO")
        #expect(ProfilePlaceholderPalette.glyph(from: "张三") == "张")
        #expect(ProfilePlaceholderPalette.glyph(from: "🐘X") == "🐘")
        #expect(ProfilePlaceholderPalette.glyph(from: "  ") == "?")
    }

    @Test func placeholderHashIsStableAcrossLaunches() {
        // FNV-1a reference values; String.hashValue would change every launch.
        #expect(ProfilePlaceholderPalette.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(ProfilePlaceholderPalette.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func placeholderSpreadsAccountsAcrossTones() {
        let seeds = (1...24).map { "https://example.social/@user\($0)" }
        let hues = Set(seeds.map { ProfilePlaceholderPalette.stableHash($0) % 8 })
        #expect(hues.count >= 5)
    }

    @Test @MainActor func placeholderSeedPrefersTheProfileURL() {
        #expect(makeAccount(url: "https://example.social/@moro").placeholderSeed == "https://example.social/@moro")
        #expect(makeAccount(username: "moro", url: "").placeholderSeed == "moro@example.com")
    }
}
