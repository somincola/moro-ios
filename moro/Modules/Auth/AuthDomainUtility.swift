//
//  AuthDomainUtility.swift
//  moro
//
//  Shared helpers for normalizing and lightly validating instance domains.
//

import Foundation

/// Curated quick-pick servers, kept short (~5) to keep the UI clean.
/// Single source of truth for both the login chips and the registration picker.
enum RecommendedServers {
    /// Server we steer users toward first (highlighted / pre-recommended).
    static let primary = "m.somincola.org"

    /// Other suggestions: flagship + a couple of popular servers + a Chinese community.
    static let others = ["mastodon.social", "mstdn.social", "mas.to", "m.cmx.im"]

    /// Primary first, then the rest.
    static var all: [String] { [primary] + others }
}

enum AuthDomainUtility {
    /// Strips scheme, whitespace, trailing slashes and lowercases the domain.
    static func sanitize(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        value = value.replacingOccurrences(of: "/", with: "")
        return value
    }

    /// Cheap client-side shape check before hitting the network.
    static func isLikelyDomain(_ domain: String) -> Bool {
        let pattern = #"^[a-z0-9.-]+\.[a-z]{2,}$"#
        return domain.range(of: pattern, options: .regularExpression) != nil
    }
}
