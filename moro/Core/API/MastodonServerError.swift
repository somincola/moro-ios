//
//  MastodonServerError.swift
//  moro
//
//  Represents an error returned by the Mastodon API server.
//

import Foundation

/// Error structure returned by Mastodon API
public struct MastodonServerError: Decodable, Error, Sendable {
    /// The error message from the server
    public let error: String

    /// Optional detailed description of the error
    public let errorDescription: String?

    /// HTTP status code (set after decoding)
    public var httpCode: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    public init(error: String, errorDescription: String? = nil, httpCode: Int? = nil) {
        self.error = error
        self.errorDescription = errorDescription
        self.httpCode = httpCode
    }
}

// MARK: - LocalizedError Conformance

extension MastodonServerError: LocalizedError {
    public var localizedDescription: String {
        if let description = errorDescription, !description.isEmpty {
            return description
        }
        return error
    }

    public var failureReason: String? {
        error
    }

    public var recoverySuggestion: String? {
        guard let code = httpCode else { return nil }
        switch code {
        case 401:
            return MoroL10n.AppError.recoveryUnauthorized
        case 403:
            return MoroL10n.AppError.recoveryForbidden
        case 404:
            return MoroL10n.AppError.recoveryNotFound
        case 422:
            return MoroL10n.AppError.recoveryUnprocessable
        case 429:
            return MoroL10n.AppError.recoveryRateLimit
        case 500...599:
            return MoroL10n.AppError.recoveryServerError
        default:
            return nil
        }
    }
}

// MARK: - Common Server Errors

extension MastodonServerError {
    /// Check if this is an authentication error
    var isAuthenticationError: Bool {
        httpCode == 401 || httpCode == 403
    }

    /// Check if this is a rate limit error
    var isRateLimitError: Bool {
        httpCode == 429
    }

    /// Check if this is a not found error
    var isNotFoundError: Bool {
        httpCode == 404
    }

    /// Check if this is a server error
    var isServerError: Bool {
        guard let code = httpCode else { return false }
        return code >= 500 && code < 600
    }

    /// Check if the error is retryable
    var isRetryable: Bool {
        isRateLimitError || isServerError
    }
}
