import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct AppSupportTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "support-tests-" + UUID().uuidString)!
    }

    @Test func versionsCompareNumericComponentsAndRejectInvalidMetadata() {
        #expect(MoroAppStore.isNewer("1.0.10", than: "1.0.9"))
        #expect(MoroAppStore.isNewer("2", than: "1.99.99"))
        #expect(!MoroAppStore.isNewer("1.0", than: "1.0.0"))
        #expect(!MoroAppStore.isNewer("1.0.5", than: "1.1"))
        for invalid in ["", "1..6", "1.0-beta", "-1", "１.２", "99999999999999999999999"] {
            #expect(!MoroAppStore.isNewer(invalid, than: "1"))
        }
    }

    @Test func storefrontCodesConvertForLookup() {
        for (input, expected) in [("USA", "US"), ("CHN", "CN"), ("TWN", "TW"), ("GBR", "GB"), ("DEU", "DE"), ("JPN", "JP"), ("fr", "FR")] {
            #expect(MoroAppStore.lookupCountry(input) == expected)
        }
        #expect(MoroAppStore.lookupCountry("JPN") == "JP")
        #expect(MoroAppStore.lookupCountry("ZZZ") == nil)
        #expect(MoroAppStore.lookupCountry("en-US") == nil)
    }

    @Test func lookupOnlyAcceptsThisApp() throws {
        let valid = Data(#"{"results":[{"trackId":6776115614,"bundleId":"com.somincola.moro","version":"1.0.6"}]}"#.utf8)
        #expect(try AppStoreRelease.decodeLookup(valid)?.version == "1.0.6")
        #expect(try AppStoreRelease.decodeLookup(Data(#"{"results":[]}"#.utf8)) == nil)
        #expect(try AppStoreRelease.decodeLookup(Data(#"{"results":[{"trackId":1,"bundleId":"other","version":"99"}]}"#.utf8)) == nil)
        #expect(throws: (any Error).self) { try AppStoreRelease.decodeLookup(Data("invalid".utf8)) }
    }

    @Test func dailyCacheManualRetryAndSeenVersionSurviveRelaunch() async {
        let preferences = defaults()
        var clock = Date()
        var requests = 0
        let store = AppUpdateStore(currentVersion: "1.0.5", defaults: preferences, now: { clock }, country: { "US" }) { _ in
            requests += 1
            return AppStoreRelease(version: "1.0.6")
        }
        await store.check()
        #expect(store.hasUnseenUpdate)
        store.markUpdateSeen()
        #expect(store.hasUpdate && !store.hasUnseenUpdate)
        await store.check()
        #expect(requests == 1)
        await store.check(force: true)
        #expect(requests == 2)
        let restored = AppUpdateStore(currentVersion: "1.0.5", defaults: preferences, now: { clock }, country: { "US" }) { _ in
            requests += 1
            return AppStoreRelease(version: "1.0.7")
        }
        await restored.check()
        #expect(requests == 2 && !restored.hasUnseenUpdate)
        clock = clock.addingTimeInterval(86_401)
        await restored.check()
        #expect(requests == 3 && restored.hasUnseenUpdate)
    }

    @Test func unavailableStoreDoesNotShowAnUpdateFromAnotherRegion() async {
        var region = "US"
        let store = AppUpdateStore(currentVersion: "1", defaults: defaults(), country: { region }) { code in
            code == "US" ? AppStoreRelease(version: "2") : nil
        }
        await store.check()
        #expect(store.hasUpdate)
        region = "CN"
        await store.check()
        #expect(store.state == .unavailable && !store.hasUpdate)
    }

    @Test func offlineChecksRemainUnknownAndAreThrottledWithManualRetry() async {
        var requests = 0
        let store = AppUpdateStore(defaults: defaults(), country: { "US" }) { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        await store.check()
        await store.check()
        #expect(requests == 1 && store.state == .failed && !store.hasUpdate)
        await store.check(force: true)
        #expect(requests == 2)
    }

    @Test func anInstalledBetaNeverPromptsForDowngrade() async {
        let store = AppUpdateStore(currentVersion: "2.0", defaults: defaults(), country: { "US" }) { _ in
            AppStoreRelease(version: "1.0.6")
        }
        await store.check()
        #expect(store.state == .checked && !store.hasUpdate && !store.hasUnseenUpdate)
    }

    @Test func concurrentChecksShareOneRequest() async {
        var resume: CheckedContinuation<AppStoreRelease?, Never>?
        var requests = 0
        let store = AppUpdateStore(defaults: defaults(), country: { "US" }) { _ in
            requests += 1
            return await withCheckedContinuation { resume = $0 }
        }
        let first = Task { await store.check() }
        while resume == nil { await Task.yield() }
        await store.check(force: true)
        #expect(requests == 1)
        resume?.resume(returning: AppStoreRelease(version: "2"))
        await first.value
    }

    @Test func feedbackCreatesIndependentEditableDraftsWithoutPersonalDiagnostics() {
        let first = MoroFeedbackDraft.make(accountID: "account-a")
        let second = MoroFeedbackDraft.make(accountID: "account-a")
        #expect(first.id != second.id)
        #expect(first.category == .manual && first.payload.visibility == .public)
        #expect(first.payload.content == "@acacius@m.somincola.org #Moro\n\n")
        #expect(!first.payload.content.contains("account-a"))
        #expect(first.payload.mediaAttachments.isEmpty && !first.payload.isSchedulingEnabled)
    }
}
