//
//  MoroErrorCopy.swift
//  moro
//
//  Turns raw networking/decoding errors into concise, calm, localized copy.
//

import Foundation

enum MoroErrorCopy {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? MoroL10n.AppError.recoveryTryAgain
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return MoroL10n.AppError.networkUnavailable
            case .timedOut:
                return MoroL10n.AppError.timeout
            case .cancelled:
                return MoroL10n.AppError.cancelled
            default:
                return MoroL10n.AppError.recoveryTryAgain
            }
        }

        if error is DecodingError {
            return MoroL10n.AppError.decoding
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty,
           !looksLikeRawSystemBoilerplate(description)
        {
            return description
        }

        return sanitized(error.localizedDescription)
    }

    static func sanitized(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return MoroL10n.AppError.recoveryTryAgain
        }
        if looksLikeRawSystemBoilerplate(trimmed) {
            return MoroL10n.AppError.recoveryTryAgain
        }
        return trimmed
    }

    private static func looksLikeRawSystemBoilerplate(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let markers = [
            "nsurlerrordomain",
            "nscocoaerrordomain",
            "cfnetwork",
            "the operation couldn't be completed",
            "the operation couldn’t be completed",
            "the data couldn't be read",
            "the data couldn’t be read",
            "the internet connection appears to be offline",
            "a server with the specified hostname could not be found",
            "could not connect to the server",
            "the request timed out",
        ]
        return markers.contains { lowered.contains($0) }
    }
}
