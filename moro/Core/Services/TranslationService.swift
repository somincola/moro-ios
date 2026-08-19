//
//  TranslationService.swift
//  moro
//
//  Translation provider abstraction for future post/content translation features.
//

import Foundation

public enum TranslationProvider: String, Sendable {
    case system
    case remote
    case unavailable
}

public enum TranslationAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public struct TranslationRequest: Equatable, Sendable {
    public let text: String
    public let sourceLanguage: String?
    public let targetLanguage: String

    public init(text: String, sourceLanguage: String? = nil, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

public struct TranslationResult: Equatable, Sendable {
    public let translatedText: String
    public let detectedSourceLanguage: String?
    public let provider: TranslationProvider
    public let providerName: String?

    public init(
        translatedText: String,
        detectedSourceLanguage: String?,
        provider: TranslationProvider,
        providerName: String? = nil
    ) {
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
        self.provider = provider
        self.providerName = providerName
    }
}

public protocol TranslationService: Sendable {
    var provider: TranslationProvider { get }
    func availability(for request: TranslationRequest) -> TranslationAvailability
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public enum TranslationServiceError: LocalizedError, Equatable {
    case unavailable(String)
    case unsupportedLanguagePair
    case emptyText

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .unsupportedLanguagePair:
            return MoroL10n.Translation.unsupportedLanguagePair
        case .emptyText:
            return MoroL10n.Translation.emptyText
        }
    }
}

public struct UnavailableTranslationService: TranslationService {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var provider: TranslationProvider { .unavailable }

    public func availability(for request: TranslationRequest) -> TranslationAvailability {
        .unavailable(reason: reason)
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranslationServiceError.emptyText
        }
        throw TranslationServiceError.unavailable(reason)
    }
}

public extension TranslationService where Self == UnavailableTranslationService {
    static var disabled: UnavailableTranslationService {
        UnavailableTranslationService(reason: MoroL10n.Translation.notConfigured)
    }
}
