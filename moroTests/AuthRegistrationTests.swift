//
//  AuthRegistrationTests.swift
//  moroTests
//
//  Focused tests for auth and registration related models.
//

import Testing
@testable import moro
import Foundation

struct AuthRegistrationTests {
    @Test func oauthTokenResponseDecodesUnixTimestampCreatedAt() throws {
        let json = """
        {
          "access_token": "token-123",
          "token_type": "Bearer",
          "scope": "read write",
          "created_at": 1700000000
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        #expect(decoded.accessToken == "token-123")
        #expect(decoded.tokenType == "Bearer")
        #expect(decoded.scope == "read write")
        #expect(decoded.createdAt != nil)
        #expect(decoded.createdAt?.timeIntervalSince1970 == 1700000000)
    }

    @Test func oauthTokenResponseDecodesISO8601CreatedAt() throws {
        let json = """
        {
          "access_token": "token-iso",
          "token_type": "Bearer",
          "created_at": "2026-02-19T12:34:56.789Z"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        #expect(decoded.accessToken == "token-iso")
        #expect(decoded.createdAt != nil)
    }

    @Test func mastodonInstanceRuleDecodesNumericID() throws {
        let json = """
        {
          "id": 7,
          "text": "No spam",
          "hint": "Keep conversations respectful"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MastodonInstanceRule.self, from: data)

        #expect(decoded.id == "7")
        #expect(decoded.text == "No spam")
        #expect(decoded.hint == "Keep conversations respectful")
    }

    @Test func mastodonInstanceRuleLocalizesTranslationsByPreferredLanguage() throws {
        let json = """
        {
          "id": "10",
          "text": "Default rule",
          "hint": "Default hint",
          "translations": {
            "en": { "text": "English rule", "hint": "English hint" },
            "fr": { "text": "Règle française", "hint": "Indice français" },
            "zh-CN": { "text": "简体规则", "hint": "简体提示" },
            "zh-TW": { "text": "繁體規則", "hint": "繁體提示" }
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MastodonInstanceRule.self, from: data)

        #expect(decoded.localizedText(languageIdentifiers: ["zh-Hans-CN"]) == "简体规则")
        #expect(decoded.localizedHint(languageIdentifiers: ["zh-Hans-CN"]) == "简体提示")
        #expect(decoded.localizedText(languageIdentifiers: ["zh-Hant-HK"]) == "繁體規則")
        #expect(decoded.localizedText(languageIdentifiers: ["fr-FR"]) == "Règle française")
        #expect(decoded.localizedText(languageIdentifiers: ["ko-KR"]) == "English rule")
        #expect(decoded.localizedHint(languageIdentifiers: ["ko-KR"]) == "English hint")
    }

    @Test func mastodonInstanceRuleFallsBackToDefaultWhenNoMatchingEnglishTranslation() throws {
        let json = """
        {
          "id": "11",
          "text": "Default rule",
          "hint": "Default hint",
          "translations": {
            "de": { "text": "Deutsche Regel", "hint": "Deutscher Hinweis" }
          }
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MastodonInstanceRule.self, from: data)

        #expect(decoded.localizedText(languageIdentifiers: ["it-IT"]) == "Default rule")
        #expect(decoded.localizedHint(languageIdentifiers: ["it-IT"]) == "Default hint")
    }

    @Test func mastodonInstanceV2RegistrationFieldsDecode() throws {
        let json = """
        {
          "domain": "example.social",
          "title": "Example",
          "description": "A test instance",
          "registrations": {
            "enabled": false,
            "approval_required": true,
            "message": "Registrations are currently limited.",
            "min_age": 18,
            "reason_required": true
          },
          "rules": [
            { "id": "1", "text": "Be nice" }
          ]
        }
        """
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MastodonInstanceV2.self, from: Data(json.utf8))

        #expect(decoded.domain == "example.social")
        #expect(decoded.registrations?.enabled == false)
        #expect(decoded.registrations?.approvalRequired == true)
        #expect(decoded.registrations?.minAge == 18)
        #expect(decoded.registrations?.reasonRequired == true)
        #expect(decoded.registrations?.message == "Registrations are currently limited.")
        #expect(decoded.rules?.first?.text == "Be nice")
    }
}
