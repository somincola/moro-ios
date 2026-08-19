//
//  MastodonAccountDeletionURL.swift
//  moro
//
//  Builds the direct account-deletion URL exposed by Mastodon instances.
//

import Foundation

enum MastodonAccountDeletionURL {
    static func make(from instanceURL: URL) -> URL? {
        guard var components = URLComponents(
            url: instanceURL,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https", components.host != nil else {
            return nil
        }

        components.path = "/settings/delete"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
