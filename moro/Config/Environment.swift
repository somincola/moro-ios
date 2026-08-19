//
//  Environment.swift
//  moro
//
//  Defines build-time environment configuration helpers.
//

import Foundation

enum AppEnvironment {
    /// The current Mastodon instance base URL.
    /// Reads from Keychain if available, otherwise returns a placeholder.
    static var apiBaseURL: URL {
        // Try to read from Keychain
        let keychain = KeychainService()
        if let instanceURLString = try? keychain.get(forKey: "instance_url"),
            let url = URL(string: instanceURLString)
        {
            return url
        }

        // Default server (used only before login) — steers toward our instance.
        return URL(string: "https://\(RecommendedServers.primary)")!
    }
}
