//
//  APIError.swift
//  moro
//
//  Enhanced error taxonomy for networking layer with LocalizedError support.
//

import Foundation

/// API error types for network operations
enum APIError: Error, Sendable {
    /// Invalid URL provided
    case invalidURL
    /// Failed to decode response
    case decoding(Error)
    /// HTTP error with status code and optional response data
    case http(statusCode: Int, data: Data?)
    /// Mastodon API server returned an error
    case serverError(MastodonServerError)
    /// Authentication missing or invalid
    case authenticationRequired
    /// Request was cancelled
    case cancelled
    /// Network connectivity issue
    case networkUnavailable
    /// Request timed out
    case timeout
    /// Rate limited by server
    case rateLimited(retryAfter: TimeInterval?)
    /// Underlying error from URLSession or other sources
    case underlying(Error)
}

// MARK: - LocalizedError Conformance

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return MoroL10n.AppError.invalidURL
        case .decoding:
            return MoroL10n.AppError.decoding
        case .http(let statusCode, _):
            return MoroL10n.AppError.http(statusCode)
        case .serverError(let serverError):
            return serverError.localizedDescription
        case .authenticationRequired:
            return MoroL10n.AppError.authenticationRequired
        case .cancelled:
            return MoroL10n.AppError.cancelled
        case .networkUnavailable:
            return MoroL10n.AppError.networkUnavailable
        case .timeout:
            return MoroL10n.AppError.timeout
        case .rateLimited:
            return MoroL10n.AppError.rateLimited
        case .underlying(let error):
            return error.localizedDescription
        }
    }

    var failureReason: String? {
        switch self {
        case .invalidURL:
            return MoroL10n.AppError.reasonInvalidURL
        case .decoding(let error):
            if let decodingError = error as? DecodingError {
                return decodingError.detailedDescription
            }
            return error.localizedDescription
        case .http(let statusCode, let data):
            if let data = data, let message = String(data: data, encoding: .utf8) {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP \(statusCode)"
        case .serverError(let serverError):
            return serverError.failureReason
        case .authenticationRequired:
            return MoroL10n.AppError.reasonAuthenticationRequired
        case .cancelled:
            return nil
        case .networkUnavailable:
            return MoroL10n.AppError.reasonNetworkUnavailable
        case .timeout:
            return MoroL10n.AppError.reasonTimeout
        case .rateLimited:
            return MoroL10n.AppError.reasonRateLimited
        case .underlying(let error):
            return (error as? LocalizedError)?.failureReason
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL, .decoding:
            return MoroL10n.AppError.recoveryContactSupport
        case .http(let statusCode, _):
            return httpRecoverySuggestion(for: statusCode)
        case .serverError(let serverError):
            return serverError.recoverySuggestion
        case .authenticationRequired:
            return MoroL10n.AppError.recoveryRelogin
        case .cancelled:
            return nil
        case .networkUnavailable:
            return MoroL10n.AppError.recoveryCheckConnection
        case .timeout:
            return MoroL10n.AppError.recoveryTryAgain
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return MoroL10n.AppError.recoveryWaitSeconds(Int(seconds))
            }
            return MoroL10n.AppError.recoveryWaitAndRetry
        case .underlying:
            return MoroL10n.AppError.recoveryTryAgain
        }
    }

    private func httpRecoverySuggestion(for statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            return MoroL10n.AppError.recoveryRelogin
        case 404:
            return MoroL10n.AppError.recoveryNotFound
        case 422:
            return MoroL10n.AppError.recoveryCheckInput
        case 429:
            return MoroL10n.AppError.recoveryWaitAndRetry
        case 500...599:
            return MoroL10n.AppError.recoveryServerError
        default:
            return MoroL10n.AppError.recoveryTryAgain
        }
    }
}

// MARK: - Error Classification

extension APIError {
    /// Whether the error is retryable
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .timeout, .rateLimited:
            return true
        case .serverError(let serverError):
            return serverError.isRetryable
        case .http(let statusCode, _):
            return statusCode >= 500 || statusCode == 429
        case .underlying(let error):
            return (error as NSError).code == NSURLErrorTimedOut
                || (error as NSError).code == NSURLErrorNetworkConnectionLost
        default:
            return false
        }
    }

    /// Whether the user should be prompted to re-authenticate
    var requiresReauthentication: Bool {
        switch self {
        case .authenticationRequired:
            return true
        case .http(let statusCode, _):
            return statusCode == 401
        case .serverError(let serverError):
            return serverError.isAuthenticationError
        default:
            return false
        }
    }

    /// Whether this error should be shown to the user
    var shouldShowToUser: Bool {
        switch self {
        case .cancelled:
            return false
        default:
            return true
        }
    }

    /// HTTP status code if applicable
    var httpStatusCode: Int? {
        switch self {
        case .http(let statusCode, _):
            return statusCode
        case .serverError(let serverError):
            return serverError.httpCode
        default:
            return nil
        }
    }
}

// MARK: - User-Friendly Display

extension APIError {
    /// User-friendly title for error alerts
    var alertTitle: String {
        switch self {
        case .networkUnavailable:
            return MoroL10n.AppError.titleNoConnection
        case .authenticationRequired:
            return MoroL10n.AppError.titleSessionExpired
        case .rateLimited:
            return MoroL10n.AppError.titleSlowDown
        case .serverError:
            return MoroL10n.AppError.titleServerError
        default:
            return MoroL10n.AppError.titleSomethingWentWrong
        }
    }

    /// User-friendly message for error alerts
    var alertMessage: String {
        errorDescription ?? MoroL10n.AppError.unknown
    }
}

// MARK: - DecodingError Extension

extension DecodingError {
    var detailedDescription: String {
        switch self {
        case .typeMismatch(let type, let context):
            return
                "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return
                "Value not found: \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .keyNotFound(let key, let context):
            return
                "Key '\(key.stringValue)' not found at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted: \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error"
        }
    }
}
