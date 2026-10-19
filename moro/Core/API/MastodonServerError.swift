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
    public let serverDescription: String?

    /// HTTP status code (set after decoding)
    public var httpCode: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case serverDescription = "error_description"
    }

    public init(error: String, errorDescription: String? = nil, httpCode: Int? = nil) {
        self.error = error
        self.serverDescription = errorDescription
        self.httpCode = httpCode
    }
}

// MARK: - LocalizedError Conformance

extension MastodonServerError: LocalizedError {
    public var errorDescription: String? { localizedDescription }
    public var localizedDescription: String {
        // Raw server text remains available for diagnostics and registration validation.
        MoroL10n.AppError.http(httpCode ?? 500)
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
    /// `error` and `error_description` together, for keyword checks that must see both.
    var combinedMessage: String {
        guard let serverDescription, !serverDescription.isEmpty else { return error }
        return "\(error) \(serverDescription)"
    }

    /// The token itself was rejected. Only this makes a stored session unusable.
    var isAuthenticationError: Bool {
        httpCode == 401
    }

    /// 403: the token is valid but the account may not act (disabled, pending approval,
    /// unconfirmed e-mail, or the action is forbidden). Never a reason to drop a session.
    var isAccountStateRestriction: Bool {
        httpCode == 403
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
