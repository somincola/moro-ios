//
//  LoginStarfieldTests.swift
//  moroTests
//

import Foundation
import Testing

@testable import moro

extension moroTests {
    @Test func knownServersAreUniqueAndLeadWithTheRecommendedOnes() {
        let domains = KnownServers.domains
        #expect(Set(domains).count == domains.count)
        #expect(Array(domains.prefix(RecommendedServers.all.count)) == RecommendedServers.all)
        #expect(domains.allSatisfy { AuthDomainUtility.isLikelyDomain($0) })
    }

    @Test func starfieldReadsHandlesAndURLsAsTheirServer() {
        #expect(StarfieldModel.normalize("  HTTPS://Mastodon.Social ") == "mastodon.social")
        #expect(StarfieldModel.normalize("@alice@mas.to") == "mas.to")
    }

    @Test func starfieldStartsCalmWithNothingTyped() {
        var model = StarfieldModel()
        model.update(query: "", now: .now)
        #expect(model.lock == nil)
        #expect(model.levels.allSatisfy { $0.to == 0.5 })
    }

    @Test func starfieldLocksOnAnExactServer() {
        var model = StarfieldModel()
        model.update(query: RecommendedServers.primary, now: .now)
        #expect(model.lock?.label == RecommendedServers.primary)
        #expect(model.lock?.index == KnownServers.domains.firstIndex(of: RecommendedServers.primary))
    }

    @Test func starfieldNarrowsUntilOneServerIsLeft() {
        var model = StarfieldModel()
        model.update(query: "m", now: .now)
        #expect(model.lock == nil)

        model.update(query: "mastodon.so", now: .now)
        #expect(model.lock?.label == "mastodon.social")

        model.update(query: "", now: .now)
        #expect(model.lock == nil)
        #expect(model.returning?.index == KnownServers.domains.firstIndex(of: "mastodon.social"))
    }

    @Test func starfieldGivesAnUnlistedDomainANewStar() {
        var model = StarfieldModel()
        model.update(query: "my.server.dev", now: .now)
        #expect(model.lock?.index == nil)
        #expect(model.lock?.label == "my.server.dev")

        model.update(query: "my.server.", now: .now)
        #expect(model.lock == nil)
    }
}
