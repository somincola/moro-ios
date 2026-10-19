//
//  Environment.swift
//  moro
//
//  Defines build-time environment configuration helpers.
//

import Foundation

enum AppEnvironment {
    /// Last instance URL read from the Keychain. Stream events compare credentials on every
    /// event, so this must not hit `SecItemCopyMatching` each time. Writers of the active
    /// session's instance URL call `invalidateInstanceURL()`.
    private static var cachedInstanceURL: URL?

    /// The current Mastodon instance base URL.
    /// Reads from Keychain if available, otherwise returns a placeholder.
    static var apiBaseURL: URL {
        if let cachedInstanceURL { return cachedInstanceURL }

        let keychain = KeychainService()
        if let instanceURLString = try? keychain.get(forKey: "instance_url"),
            let url = URL(string: instanceURLString)
        {
            cachedInstanceURL = url
            return url
        }

        // Default server (used only before login) — steers toward our instance. Not cached,
        // so the first read after login picks up the real instance.
        return URL(string: "https://\(RecommendedServers.primary)")!
    }

    /// Call whenever the active session's instance URL is written or removed.
    static func invalidateInstanceURL() {
        cachedInstanceURL = nil
    }
}
