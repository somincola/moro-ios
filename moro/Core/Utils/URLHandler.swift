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
    
    func handleURL(
        _ url: URL,
        router: AppRouter? = nil,
        systemOpenURL: OpenURLAction
    ) {
        handleLinkAction(.link(url: url), router: router, systemOpenURL: systemOpenURL)
    }

    /// Shared by posts, profile bios, and profile fields, including their fallback links.
    func handleLinkAction(
        _ action: LinkAction,
        router: AppRouter? = nil,
        systemOpenURL: OpenURLAction
    ) {
        if let router, let route = preferredInAppRoute(for: action) {
            router.navigate(to: route)
        } else {
            systemOpenURL(action.url)
        }
    }

    func preferredInAppRoute(for url: URL) -> Route? {
        preferredInAppRoute(for: .link(url: url))
    }

    func preferredInAppRoute(for action: LinkAction) -> Route? {
        guard settings.openLinksIn == .moro else { return nil }
        let url = action.url
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else { return nil }

        switch action {
        case .hashtag(let tag, _):
            return .hashtag(tag)
        case .mention:
            let components = normalizedPathComponents(from: url)
            if components.count == 1,
                let acct = acctFromAtPathComponent(components[0], sourceHost: url.host)
            {
                return .accountLookup(acct)
            }
        case .link:
            break
        }

        return parseMastodonURL(url) ?? .webPreview(url)
    }

    /// Only complete status paths are candidates, and still require server resolution.
    /// Mentions and hashtags must come from parsed entities, never URL substrings.
    func parseMastodonURL(_ url: URL) -> Route? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else { return nil }
        let components = normalizedPathComponents(from: url)
        return isStatusPath(components) ? .statusLink(url) : nil
    }

    /// Status IDs belong to the server that returned them. A URL path is only
    /// a candidate: resolve the complete URL using the logged-in server, and
    /// open the original webpage when it cannot supply a real Status.
    func resolveStatusLink(_ url: URL, apiClient: MastodonAPI) async -> Route? {
        guard !Task.isCancelled else { return nil }
        // Mastodon's URL resolution contract applies to HTTPS queries.
        guard url.scheme?.lowercased() == "https" else { return .webPreview(url) }
        do {
            let results = try await apiClient.search(
                query: url.absoluteString,
                type: .statuses,
                resolve: true,
                limit: 1,
                offset: nil
            )
            guard !Task.isCancelled else { return nil }
            if let status = results.statuses.first {
                return .statusDetail(status.displayStatus)
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                (error as? URLError)?.code != .cancelled
            else { return nil }
        }
        return .webPreview(url)
    }

    private func normalizedPathComponents(from url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    }

    private func isStatusPath(_ components: [String]) -> Bool {
        guard let id = components.last, !id.isEmpty,
            id.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return false }

        switch components.count {
        case 2:
            return components[0] == "statuses"
                || (components[0].hasPrefix("@") && components[0].count > 1)
        case 3:
            return components[1] == "statuses"
                && (components[0] == "web"
                    || (components[0].hasPrefix("@") && components[0].count > 1))
        case 4:
            return components[0] == "users" && components[2] == "statuses"
        default:
            return false
        }
    }

    private func acctFromAtPathComponent(_ component: String, sourceHost: String?) -> String? {
        guard component.hasPrefix("@"), let sourceHost else { return nil }
        let acct = String(component.dropFirst())
        let parts = acct.split(separator: "@", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }),
            !acct.contains(where: { $0.isWhitespace || $0 == "/" })
        else { return nil }
        return parts.count == 2 ? acct : "\(acct)@\(sourceHost)"
    }
}
