import CryptoKit
import Foundation

/// Keep an uncertain submission's identity with its draft. Only a changed request
/// gets a new key; a timeout or response-decoding failure may follow a server commit.
nonisolated struct ComposePublishAttempt: Codable, Equatable {
    let idempotencyKey: String
    let fingerprint: String

    static func resolving(_ payload: StatusPublishPayload, previous: Self?) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = SHA256.hash(data: try encoder.encode(payload))
            .map { String(format: "%02x", $0) }.joined()
        if let previous, previous.fingerprint == fingerprint { return previous }
        return Self(idempotencyKey: UUID().uuidString, fingerprint: fingerprint)
    }
}

enum ComposePublishFailure {
    static func message(for error: Error) -> String {
        if let error = error as? APIError {
            switch error {
            case .timeout, .networkUnavailable, .cancelled, .decoding, .underlying:
                return MoroL10n.Compose.publishUnconfirmed
            case .serverError(let serverError):
                // A rejected post (400/422) carries the server's own explanation, e.g.
                // "Validation failed: Text character limit of 500 exceeded", in the
                // account's language. That says what to fix; a bare "Unable to process
                // request" does not.
                if let code = serverError.httpCode, code == 400 || code == 422 {
                    let message = serverError.error.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !message.isEmpty { return message }
                }
            default: break
            }
        }
        if error is URLError || error is CancellationError {
            return MoroL10n.Compose.publishUnconfirmed
        }
        return error.localizedDescription
    }
}
