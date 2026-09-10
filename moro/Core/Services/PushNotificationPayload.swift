import Foundation
import CoreFoundation

/// Only the routing fields cross from the system callback to the main actor.
/// The relay ciphertext and any credentials are never retained in the request.
struct PushNotificationPayload: Equatable, Sendable {
    let sessionID: String?
    let notificationID: String?
    let notificationType: String?
    let statusURL: URL?

    nonisolated init(userInfo: [AnyHashable: Any]) {
        let rawSession = Self.text(userInfo["x"])
        sessionID = rawSession.flatMap { Self.text($0.removingPercentEncoding ?? $0) }
        notificationID = Self.identifier(userInfo["notification_id"])
        notificationType = Self.text(userInfo["notification_type"])?.lowercased()
        statusURL = Self.webURL(userInfo["status_url"]) ?? Self.webURL(userInfo["url"])
    }

    private nonisolated static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func identifier(_ value: Any?) -> String? {
        let string: String?
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            string = number.stringValue
        } else {
            string = text(value)
        }
        guard let string, string.count <= 256, !string.isEmpty,
            string.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
            })
        else { return nil }
        return string
    }

    private nonisolated static func webURL(_ value: Any?) -> URL? {
        guard let string = text(value), let url = URL(string: string),
            ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else { return nil }
        return url
    }
}

struct PendingNotificationOpen: Identifiable, Equatable, Sendable {
    let id = UUID()
    let sessionID: String?
    let payload: PushNotificationPayload
}
