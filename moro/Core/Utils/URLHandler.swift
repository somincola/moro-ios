//
//  URLHandler.swift
//  moro
//
//  URL handling utility that respects AppSettings.openLinksIn preference.
//

import Foundation
import SwiftUI

/// URL handler that respects app settings for link opening behavior
@MainActor
struct URLHandler {
    static let shared = URLHandler()
    
    private let settings = AppSettings.shared
    
    private init() {}
    
    /// Check if a URL is a Mastodon link (mention, hashtag, status, etc.)
    func isMastodonLink(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        
        // Check if it's a Mastodon instance URL
        // Common patterns: /@username, /tags/tagname, /web/statuses/123, /users/123
        return path.contains("/@") || 
               path.contains("/tags/") || 
               path.contains("/tag/") ||
               path.contains("/web/statuses/") ||
               path.contains("/statuses/") ||
               path.contains("/users/") ||
               path.contains("/accounts/")
    }
    
    /// Handle URL opening based on AppSettings
    /// - Parameters:
    ///   - url: The URL to open
    ///   - router: Optional router for in-app navigation
    ///   - systemOpenURL: System URL opening function
    func handleURL(
        _ url: URL,
        router: AppRouter? = nil,
        systemOpenURL: OpenURLAction
    ) {
        if let router, let route = preferredInAppRoute(for: url) {
            router.navigate(to: route)
            return
        }

        systemOpenURL(url)
    }

    /// Determine the preferred in-app route for a URL under current settings.
    func preferredInAppRoute(for url: URL) -> Route? {
        guard settings.openLinksIn == .moro else { return nil }

        if isMastodonLink(url), let route = parseMastodonURL(url) {
            return route
        }

        let scheme = url.scheme?.lowercased()
        let supportsInAppPreview = scheme == "http" || scheme == "https"
        return supportsInAppPreview ? .webPreview(url) : nil
    }
    
    /// Parse Mastodon URL and return a Route if possible.
    /// Exposed internally to keep parser behavior testable.
    func parseMastodonURL(_ url: URL) -> Route? {
        let components = normalizedPathComponents(from: url)
        guard !components.isEmpty else { return nil }

        if let tag = parseHashtag(components) {
            return .hashtag(tag)
        }

        if let statusContext = parseStatusContext(components) {
            let placeholder = makePlaceholderStatus(
                id: statusContext.statusID,
                sourceURL: url,
                usernameHint: statusContext.username
            )
            return .statusDetail(placeholder)
        }

        if let route = parseProfileRoute(components, sourceURL: url) {
            return route
        }

        return nil
    }

    private func normalizedPathComponents(from url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .map { $0.removingPercentEncoding ?? $0 }
    }

    private func parseHashtag(_ components: [String]) -> String? {
        if let tagIndex = components.firstIndex(where: {
            let lower = $0.lowercased()
            return lower == "tags" || lower == "tag"
        }), tagIndex + 1 < components.count {
            let tag = components[tagIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        }
        return nil
    }

    private func parseStatusContext(_ components: [String]) -> (statusID: String, username: String?)? {
        if let atIndex = components.firstIndex(where: { $0.hasPrefix("@") }) {
            let username = usernameFromAtPathComponent(components[atIndex])

            if atIndex + 1 < components.count, isLikelyStatusID(components[atIndex + 1]) {
                return (components[atIndex + 1], username)
            }

            if atIndex + 2 < components.count,
                components[atIndex + 1].lowercased() == "statuses",
                isLikelyStatusID(components[atIndex + 2])
            {
                return (components[atIndex + 2], username)
            }
        }

        if let statusesIndex = components.firstIndex(where: { $0.lowercased() == "statuses" }),
            statusesIndex + 1 < components.count,
            isLikelyStatusID(components[statusesIndex + 1])
        {
            let username = components
                .prefix(statusesIndex)
                .reversed()
                .first(where: { $0.hasPrefix("@") })
                .flatMap(usernameFromAtPathComponent)
            return (components[statusesIndex + 1], username)
        }

        return nil
    }

    private func parseProfileRoute(_ components: [String], sourceURL: URL) -> Route? {
        if let atComponent = components.first(where: { $0.hasPrefix("@") }),
            let acct = acctFromAtPathComponent(atComponent, sourceHost: sourceURL.host)
        {
            return .accountLookup(acct)
        }

        if let usersIndex = components.firstIndex(where: { $0.lowercased() == "users" }),
            usersIndex + 1 < components.count,
            isLikelyAccountID(components[usersIndex + 1])
        {
            let accountID = components[usersIndex + 1]
            let account = makePlaceholderAccount(
                id: accountID,
                username: "user_\(accountID)",
                sourceURL: sourceURL
            )
            return .userProfile(account)
        }

        if let accountsIndex = components.firstIndex(where: { $0.lowercased() == "accounts" }),
            accountsIndex + 1 < components.count,
            isLikelyAccountID(components[accountsIndex + 1])
        {
            let accountID = components[accountsIndex + 1]
            let account = makePlaceholderAccount(
                id: accountID,
                username: "account_\(accountID)",
                sourceURL: sourceURL
            )
            return .userProfile(account)
        }

        return nil
    }

    private func usernameFromAtPathComponent(_ component: String) -> String? {
        guard component.hasPrefix("@") else { return nil }
        let trimmed = String(component.dropFirst())
        let username = trimmed.split(separator: "@").first.map(String.init)?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard let username, !username.isEmpty else { return nil }
        return username
    }

    private func acctFromAtPathComponent(_ component: String, sourceHost: String?) -> String? {
        guard component.hasPrefix("@") else { return nil }
        let trimmed = String(component.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("@") {
            return trimmed
        }

        if let sourceHost, !sourceHost.isEmpty {
            return "\(trimmed)@\(sourceHost)"
        }

        return trimmed
    }

    private func isLikelyStatusID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private func isLikelyAccountID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    private func makePlaceholderAccount(id: String, username: String, sourceURL: URL) -> Account {
        Account(
            id: id,
            username: username,
            acct: username,
            displayName: username,
            note: "",
            avatar: "",
            avatarStatic: "",
            header: "",
            headerStatic: "",
            followersCount: 0,
            followingCount: 0,
            statusesCount: 0,
            url: sourceURL.absoluteString
        )
    }

    private func makePlaceholderStatus(id: String, sourceURL: URL, usernameHint: String?) -> Status {
        let username = (usernameHint?.isEmpty == false ? usernameHint : nil) ?? "unknown"
        let account = makePlaceholderAccount(
            id: usernameHint ?? "unknown-\(id)",
            username: username,
            sourceURL: sourceURL
        )
        return Status(
            id: id,
            content: "",
            createdAt: Date(),
            account: account,
            mediaAttachments: [],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false,
            url: sourceURL
        )
    }
}
