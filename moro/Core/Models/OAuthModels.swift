//
//  OAuthModels.swift
//  moro
//
//  OAuth-related data models for Mastodon authentication.
//

import Foundation

/// `/api/v1/instance/extended_description` — the server's long-form "about this site"
/// page. `content` is server-rendered HTML (the admin authors it in Markdown).
nonisolated struct ExtendedInstanceDescription: Codable {
    let updatedAt: String?
    let content: String

    nonisolated enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case content
    }
}

nonisolated struct MastodonInstance: Codable {
    let uri: String
    let title: String
    let description: String
    let shortDescription: String?
    let version: String?
    let urls: InstanceURLs?
    let thumbnail: InstanceThumbnail?
    let email: String?
    let contactAccount: Account?
    let registrations: Bool?
    let approvalRequired: Bool?
    let invitesEnabled: Bool?
    let rules: [MastodonInstanceRule]?
    let languages: [String]?

    nonisolated enum CodingKeys: String, CodingKey {
        case uri
        case title
        case description
        case shortDescription = "short_description"
        case version
        case urls
        case thumbnail
        case email
        case contactAccount = "contact_account"
        case registrations
        case approvalRequired = "approval_required"
        case invitesEnabled = "invites_enabled"
        case rules
        case languages
    }
}

nonisolated struct InstanceURLs: Codable {
    let streamingAPI: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case streamingAPI = "streaming_api"
    }
}

nonisolated struct OAuthApp: Codable {
    let id: String
    let name: String
    let website: String?
    let redirectURI: String
    let clientID: String
    let clientSecret: String

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case name
        case website
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

nonisolated struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let createdAt: Date?

    nonisolated enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        
        // Handle created_at as Unix timestamp (Int) or ISO8601 string (optional)
        if let timestamp = try? container.decode(Int.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: TimeInterval(timestamp))
        } else {
            // try? decodeIfPresent returns String? (not String??)
            if let dateString = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
                createdAt = DateFormatting.parseISO8601(dateString)
            } else {
                createdAt = nil
            }
        }
    }
}

nonisolated struct MastodonInstanceRule: Codable, Identifiable, Hashable {
    nonisolated struct Translation: Codable, Hashable {
        let text: String?
        let hint: String?
    }

    let id: String
    let text: String
    let hint: String?
    let translations: [String: Translation]?

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case text
        case hint
        case translations
    }

    init(id: String, text: String, hint: String?, translations: [String: Translation]? = nil) {
        self.id = id
        self.text = text
        self.hint = hint
        self.translations = translations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = UUID().uuidString
        }

        text = try container.decode(String.self, forKey: .text)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        translations = try container.decodeIfPresent([String: Translation].self, forKey: .translations)
    }

    var localizedText: String {
        localizedText(languageIdentifiers: Self.currentLanguageIdentifiers)
    }

    var localizedHint: String? {
        localizedHint(languageIdentifiers: Self.currentLanguageIdentifiers)
    }

    func localizedText(languageIdentifiers: [String]) -> String {
        guard let translated = preferredTranslation(languageIdentifiers: languageIdentifiers)?.text,
              !translated.isEmpty else {
            return englishTranslation?.text.nonEmpty ?? text
        }
        return translated
    }

    func localizedHint(languageIdentifiers: [String]) -> String? {
        if let translated = preferredTranslation(languageIdentifiers: languageIdentifiers)?.hint,
           !translated.isEmpty {
            return translated
        }
        return englishTranslation?.hint.nonEmpty ?? hint
    }

    private var englishTranslation: Translation? {
        translation(for: "en")
    }

    private static var currentLanguageIdentifiers: [String] {
        Locale.preferredLanguages.first.map { [$0] } ?? []
    }

    private func preferredTranslation(languageIdentifiers: [String]) -> Translation? {
        for identifier in languageIdentifiers {
            for key in candidateTranslationKeys(for: identifier) {
                if let translation = translation(for: key) {
                    return translation
                }
            }
        }
        return nil
    }

    private func translation(for key: String) -> Translation? {
        guard let translations else { return nil }
        if let exact = translations[key] {
            return exact
        }
        let normalizedKey = Self.normalizedLanguageIdentifier(key)
        return translations.first {
            Self.normalizedLanguageIdentifier($0.key) == normalizedKey
        }?.value
    }

    private func candidateTranslationKeys(for identifier: String) -> [String] {
        let normalized = Self.normalizedLanguageIdentifier(identifier)
        let components = normalized.split(separator: "-").map(String.init)
        guard let language = components.first, !language.isEmpty else {
            return []
        }

        var keys: [String] = [normalized]

        if language == "zh" {
            let lowerComponents = Set(components.dropFirst().map { $0.lowercased() })
            if lowerComponents.contains("hant")
                || lowerComponents.contains("tw")
                || lowerComponents.contains("hk")
                || lowerComponents.contains("mo") {
                keys.append("zh-TW")
            } else {
                keys.append("zh-CN")
            }
        }

        keys.append(language)
        return keys.removingDuplicates()
    }

    private static func normalizedLanguageIdentifier(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let components = normalized.split(separator: "-").map(String.init)
        guard let language = components.first else { return normalized.lowercased() }

        let formattedTail = components.dropFirst().map { component in
            if component.count == 4 {
                return component.prefix(1).uppercased() + component.dropFirst().lowercased()
            }
            if component.count == 2 || component.count == 3 {
                return component.uppercased()
            }
            return component.lowercased()
        }
        return ([language.lowercased()] + formattedTail).joined(separator: "-")
    }
}

nonisolated private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

nonisolated private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

nonisolated struct MastodonInstanceV2: Codable {
    let domain: String?
    let title: String
    let version: String?
    let description: String?
    let thumbnail: InstanceThumbnail?
    let contact: MastodonInstanceContact?
    let registrations: MastodonInstanceRegistrations?
    let rules: [MastodonInstanceRule]?
    let languages: [String]?
    let configuration: InstanceConfiguration?

    nonisolated enum CodingKeys: String, CodingKey {
        case domain
        case title
        case version
        case description
        case thumbnail
        case contact
        case registrations
        case rules
        case languages
        case configuration
    }

    init(
        domain: String?,
        title: String,
        description: String?,
        thumbnail: InstanceThumbnail?,
        contact: MastodonInstanceContact?,
        registrations: MastodonInstanceRegistrations?,
        rules: [MastodonInstanceRule]?,
        languages: [String]?,
        configuration: InstanceConfiguration?,
        version: String? = nil
    ) {
        self.domain = domain
        self.title = title
        self.version = version
        self.description = description
        self.thumbnail = thumbnail
        self.contact = contact
        self.registrations = registrations
        self.rules = rules
        self.languages = languages
        self.configuration = configuration
    }
}

/// The subset of `GET /api/v2/instance` `configuration` that we use.
nonisolated struct InstanceConfiguration: Codable {
    let statuses: Statuses?
    var accounts: ProfileLimits? = nil

    nonisolated struct Statuses: Codable {
        let maxCharacters: Int?

        nonisolated enum CodingKeys: String, CodingKey {
            case maxCharacters = "max_characters"
        }
    }
}

nonisolated struct MastodonInstanceContact: Codable {
    let email: String?
    let account: Account?
}

nonisolated struct InstanceThumbnail: Codable {
    let url: String?
    let staticURL: String?
    let blurhash: String?
    let versions: Versions?

    nonisolated struct Versions: Codable {
        let oneX: String?
        let twoX: String?

        nonisolated enum CodingKeys: String, CodingKey {
            case oneX = "@1x"
            case twoX = "@2x"
        }
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case url
        case staticURL = "static"
        case blurhash
        case versions
    }

    init(url: String?, staticURL: String?, blurhash: String?, versions: Versions? = nil) {
        self.url = url
        self.staticURL = staticURL
        self.blurhash = blurhash
        self.versions = versions
    }

    init(from decoder: Decoder) throws {
        if let singleURL = try? decoder.singleValueContainer().decode(String.self) {
            self.url = singleURL
            self.staticURL = singleURL
            self.blurhash = nil
            self.versions = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.staticURL = try container.decodeIfPresent(String.self, forKey: .staticURL)
        self.blurhash = try container.decodeIfPresent(String.self, forKey: .blurhash)
        self.versions = try container.decodeIfPresent(Versions.self, forKey: .versions)
    }

    var bestURL: URL? {
        if let twoX = versions?.twoX, let url = URL(string: twoX) {
            return url
        }
        if let oneX = versions?.oneX, let url = URL(string: oneX) {
            return url
        }
        if let staticURL, let url = URL(string: staticURL) {
            return url
        }
        if let url, let parsed = URL(string: url) {
            return parsed
        }
        return nil
    }
}

nonisolated struct MastodonInstanceRegistrations: Codable {
    let enabled: Bool?
    let approvalRequired: Bool?
    let message: String?
    let minAge: Int?
    let reasonRequired: Bool?

    nonisolated enum CodingKeys: String, CodingKey {
        case enabled
        case approvalRequired = "approval_required"
        case message
        case minAge = "min_age"
        case reasonRequired = "reason_required"
    }
}

nonisolated struct InstanceRegistrationInfo {
    let domain: String
    let title: String
    let description: String
    let registrationsOpen: Bool
    let approvalRequired: Bool
    let reasonRequired: Bool
    let minAge: Int?
    let registrationMessage: String?
    let rules: [MastodonInstanceRule]
}

nonisolated struct AccountRegistrationRequest {
    let username: String
    let email: String
    let password: String
    let reason: String?
    let dateOfBirth: String?
    let agreement: Bool
    let locale: String
}

nonisolated enum RegistrationResult {
    case authenticated(token: String, account: Account, instanceURL: URL)
    case pending(email: String, requiresApproval: Bool, hint: String?)
}
