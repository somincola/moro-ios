//
//  UITestDefaultsIsolationTests.swift
//  moroTests
//

import Foundation
import Testing
@testable import moro

struct UITestDefaultsIsolationTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "ui-test-isolation-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func aNewTestStartsFromDefaultsAndARelaunchKeepsItsSettings() {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "timelineInAppNewPostBannerEnabled")  // left by an earlier test

        let firstTest = ["UITEST_DEFAULTS_SESSION": "run|testA|1"]
        #expect(UITestDefaultsIsolation.applyIfRequested(environment: firstTest, defaults: defaults, domain: domain))
        #expect(defaults.object(forKey: "timelineInAppNewPostBannerEnabled") == nil)

        // The same test changes a setting and relaunches to check it persisted.
        defaults.set(true, forKey: "expandContentWarnings")
        #expect(!UITestDefaultsIsolation.applyIfRequested(environment: firstTest, defaults: defaults, domain: domain))
        #expect(defaults.bool(forKey: "expandContentWarnings"))

        // The next test does not inherit it.
        let secondTest = ["UITEST_DEFAULTS_SESSION": "run|testB|2"]
        #expect(UITestDefaultsIsolation.applyIfRequested(environment: secondTest, defaults: defaults, domain: domain))
        #expect(defaults.object(forKey: "expandContentWarnings") == nil)
    }

    @Test func launchesWithoutASessionLeaveSettingsAlone() {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(16, forKey: "postFontSize")
        #expect(!UITestDefaultsIsolation.applyIfRequested(environment: [:], defaults: defaults, domain: domain))
        #expect(defaults.integer(forKey: "postFontSize") == 16)
    }
}
