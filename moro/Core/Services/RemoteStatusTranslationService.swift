//
//  RemoteStatusTranslationService.swift
//  moro
//
//  Server-side status translation backed by the Mastodon instance translate endpoint.
//

import Foundation
import NaturalLanguage

final class RemoteStatusTranslationService: TranslationService, @unchecked Sendable {
    private let apiClient: MastodonAPI
    private let statusID: String

    init(apiClient: MastodonAPI, statusID: String) {
        self.apiClient = apiClient
        self.statusID = statusID
    }

    var provider: TranslationProvider { .remote }

    func availability(for request: TranslationRequest) -> TranslationAvailability {
        let strippedText = plainText(from: request.text).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !strippedText.isEmpty else {
            return .unavailable(reason: TranslationServiceError.emptyText.localizedDescription)
        }

        let targetLanguage = normalizedLanguageCode(request.targetLanguage)
        guard !targetLanguage.isEmpty else {
            return .unavailable(reason: MoroL10n.Translation.notConfigured)
        }

        if let sourceLanguage = normalizedOptionalLanguageCode(request.sourceLanguage) {
            if languagesMatch(sourceLanguage, targetLanguage) {
                return .unavailable(reason: MoroL10n.Translation.sameLanguage)
            }
        } else {
            let detected = detectLanguagePrefix(from: request.text)
            if let detected, languagesMatch(detected, targetLanguage) {
                return .unavailable(reason: MoroL10n.Translation.sameLanguage)
            }
        }

        return .available
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        switch availability(for: request) {
        case .available:
            break
        case .unavailable(let reason):
            throw TranslationServiceError.unavailable(reason)
        }

        do {
            let payload = try await apiClient.translateStatus(
                id: statusID,
                targetLanguage: request.targetLanguage
            )

            let translatedHTML = (payload.content ?? payload.spoilerText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = plainText(from: translatedHTML)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else {
                throw TranslationServiceError.emptyText
            }

            let providerName = payload.provider?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TranslationResult(
                translatedText: translatedHTML,
                detectedSourceLanguage: normalizedOptionalLanguageCode(
                    payload.detectedSourceLanguage ?? request.sourceLanguage
                ),
                provider: .remote,
                providerName: providerName?.isEmpty == false
                    ? providerName
                    : MoroL10n.Translation.providerRemoteName
            )
        } catch let error as APIError {
            throw mappedError(from: error)
        } catch let error as TranslationServiceError {
            throw error
        } catch {
            throw TranslationServiceError.unavailable(
                (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            )
        }
    }

    private func mappedError(from error: APIError) -> TranslationServiceError {
        if let statusCode = error.httpStatusCode {
            switch statusCode {
            case 404, 405, 501:
                return .unavailable(MoroL10n.Translation.unavailableOnInstance)
            case 422:
                return .unsupportedLanguagePair
            default:
                break
            }
        }

        let description = error.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let description, !description.isEmpty {
            return .unavailable(description)
        }

        return .unavailable(MoroL10n.Translation.failed)
    }

    private func normalizedLanguageCode(_ code: String) -> String {
        PostLanguageCatalog.canonicalLanguageCode(for: code)
    }

    private func normalizedOptionalLanguageCode(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let normalized = normalizedLanguageCode(code)
        return normalized.isEmpty ? nil : normalized
    }

    private func languagesMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let prefixA = a.split(separator: "-").first.map(String.init) ?? a
        let prefixB = b.split(separator: "-").first.map(String.init) ?? b
        return prefixA.lowercased() == prefixB.lowercased()
    }

    private func detectLanguagePrefix(from html: String) -> String? {
        let text = plainText(from: html).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return normalizedLanguageCode(dominant.rawValue)
    }

    private func plainText(from html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
