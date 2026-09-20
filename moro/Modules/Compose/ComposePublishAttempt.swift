import CryptoKit
import Foundation

/// Keep an uncertain submission's identity with its draft. Only a changed request
/// gets a new key; a timeout or response-decoding failure may follow a server commit.
struct ComposePublishAttempt: Codable, Equatable {
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
            default: break
            }
        }
        if error is URLError || error is CancellationError {
            return MoroL10n.Compose.publishUnconfirmed
        }
        return error.localizedDescription
    }
}
