//
//  NotificationService.swift
//  moroNotificationService
//
//  Decrypts Mastodon Web Push payloads on-device (RFC 8291 / the aesgcm
//  draft scheme Mastodon actually sends) and rewrites the notification with
//  the real title/body. The relay (moro-push-relay) forwards the ciphertext
//  untouched in `p` (base64url), with `e` = content encoding and, for aesgcm,
//  `k` = sender public key (dh) and `s` = salt. The receiver keys live in the
//  shared keychain access group, written by the app's WebPushKeyStore.
//

import CryptoKit
import Foundation
import UserNotifications
import WidgetKit

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent)
        bestAttemptContent = content

        guard let content else {
            contentHandler(request.content)
            return
        }

        if let message = decryptedMessage(from: request.content.userInfo) {
            if let title = message.title, !title.isEmpty {
                content.title = title
            }
            if let body = message.body, !body.isEmpty {
                content.body = body
            }
            if let type = message.notificationType {
                content.threadIdentifier = type
                content.userInfo["notification_type"] = type
            }
            if let id = message.notificationID {
                content.userInfo["notification_id"] = id
            }
        }
        applyUnreadBadge(to: content)
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Shared unread badge

    private enum BadgeKeys {
        static let appGroup = "group.com.somincola.moro.app"
        static let countsBySession = "notification_unread_counts_by_session_v1"
        static let recentIDsBySession = "notification_unread_recent_ids_by_session_v1"
        static let directMessageUnreadIDsBySession =
            "direct_message_unread_conversation_ids_by_session_v1"
    }

    private func applyUnreadBadge(to content: UNMutableNotificationContent) {
        guard let rawSessionID = content.userInfo["x"] as? String, !rawSessionID.isEmpty,
            let defaults = UserDefaults(suiteName: BadgeKeys.appGroup)
        else {
            return
        }

        let sessionID = rawSessionID.removingPercentEncoding ?? rawSessionID
        let notificationID: String? = {
            if let id = content.userInfo["notification_id"] as? String { return id }
            if let id = content.userInfo["notification_id"] as? NSNumber { return id.stringValue }
            return nil
        }()

        var counts = defaults.dictionary(forKey: BadgeKeys.countsBySession)?.reduce(into: [String: Int]()) {
            result, entry in
            if let number = entry.value as? NSNumber {
                result[entry.key] = max(0, number.intValue)
            }
        } ?? [:]
        var recentIDs = defaults.dictionary(forKey: BadgeKeys.recentIDsBySession)?.reduce(
            into: [String: [String]]()
        ) { result, entry in
            if let ids = entry.value as? [String] {
                result[entry.key] = Array(ids.suffix(200))
            }
        } ?? [:]

        let isDuplicate = notificationID.map { recentIDs[sessionID, default: []].contains($0) } ?? false
        if !isDuplicate {
            counts[sessionID, default: 0] += 1
            if let notificationID {
                recentIDs[sessionID, default: []].append(notificationID)
                recentIDs[sessionID] = Array(recentIDs[sessionID, default: []].suffix(200))
            }
            defaults.set(counts, forKey: BadgeKeys.countsBySession)
            defaults.set(recentIDs, forKey: BadgeKeys.recentIDsBySession)
            WidgetCenter.shared.reloadTimelines(ofKind: "com.somincola.moro.widget.overview")
            WidgetCenter.shared.reloadTimelines(ofKind: "com.somincola.moro.widget.quick-actions")
        }

        let directMessageUnreadCount = defaults.dictionary(
            forKey: BadgeKeys.directMessageUnreadIDsBySession
        )?.values.reduce(into: 0) { result, value in
            if let ids = value as? [String] {
                result += Set(ids).count
            }
        } ?? 0
        content.badge = NSNumber(
            value: counts.values.reduce(0, +) + directMessageUnreadCount
        )
    }

    // MARK: - Mastodon payload

    private struct PushMessage: Decodable {
        let title: String?
        let body: String?
        let notificationID: ID?
        let notificationType: String?

        enum CodingKeys: String, CodingKey {
            case title
            case body
            case notificationID = "notification_id"
            case notificationType = "notification_type"
        }

        /// Mastodon has sent both numeric and string IDs over time.
        enum ID: Decodable {
            case string(String)
            case number(Int64)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    self = .string(s)
                } else {
                    self = .number(try container.decode(Int64.self))
                }
            }

            var value: String {
                switch self {
                case .string(let s): return s
                case .number(let n): return String(n)
                }
            }
        }
    }

    private struct DecodedMessage {
        let title: String?
        let body: String?
        let notificationID: String?
        let notificationType: String?
    }

    private func decryptedMessage(from userInfo: [AnyHashable: Any]) -> DecodedMessage? {
        guard
            let encodedBody = userInfo["p"] as? String,
            let body = Data(base64URLEncoded: encodedBody),
            let encoding = userInfo["e"] as? String,
            let privateKeyData = SharedKeychain.read(account: "webpush_private_key"),
            let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData),
            let authSecret = SharedKeychain.read(account: "webpush_auth_secret")
        else { return nil }

        let plaintext: Data?
        switch encoding {
        case "aesgcm":
            guard
                let dh = userInfo["k"] as? String,
                let senderPublic = Data(base64URLEncoded: dh),
                let saltString = userInfo["s"] as? String,
                let salt = Data(base64URLEncoded: saltString)
            else { return nil }
            plaintext = WebPushDecrypter.decryptAESGCMDraft(
                ciphertext: body, salt: salt, senderPublicKey: senderPublic,
                receiverPrivateKey: privateKey, authSecret: authSecret)
        case "aes128gcm":
            plaintext = WebPushDecrypter.decryptAES128GCM(
                record: body, receiverPrivateKey: privateKey, authSecret: authSecret)
        default:
            plaintext = nil
        }

        guard let plaintext,
            let message = try? JSONDecoder().decode(PushMessage.self, from: plaintext)
        else { return nil }
        return DecodedMessage(
            title: message.title,
            body: message.body,
            notificationID: message.notificationID?.value,
            notificationType: message.notificationType
        )
    }
}

// MARK: - Web Push decryption (RFC 8291 + the aesgcm draft Mastodon uses)

enum WebPushDecrypter {
    /// Legacy `aesgcm` (draft-ietf-webpush-encryption-04) — what Mastodon's
    /// webpush gem sends today.
    static func decryptAESGCMDraft(
        ciphertext: Data, salt: Data, senderPublicKey: Data,
        receiverPrivateKey: P256.KeyAgreement.PrivateKey, authSecret: Data
    ) -> Data? {
        guard salt.count == 16, senderPublicKey.count == 65 else { return nil }
        guard
            let senderKey = try? P256.KeyAgreement.PublicKey(x963Representation: senderPublicKey),
            let sharedSecret = try? receiverPrivateKey.sharedSecretFromKeyAgreement(with: senderKey)
        else { return nil }

        let receiverPublic = receiverPrivateKey.publicKey.x963Representation
        let prk = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: authSecret,
            sharedInfo: Data("Content-Encoding: auth\0".utf8),
            outputByteCount: 32
        )

        var context = Data("P-256\0".utf8)
        context.append(contentsOf: [0x00, 0x41])
        context.append(receiverPublic)
        context.append(contentsOf: [0x00, 0x41])
        context.append(senderPublicKey)

        let cek = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: prk, salt: salt,
            info: Data("Content-Encoding: aesgcm\0".utf8) + context, outputByteCount: 16)
        let nonceKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: prk, salt: salt,
            info: Data("Content-Encoding: nonce\0".utf8) + context, outputByteCount: 12)

        guard
            let nonce = try? AES.GCM.Nonce(data: nonceKey.withUnsafeBytes { Data($0) }),
            let sealed = try? AES.GCM.SealedBox(combined: nonce.withUnsafeBytes { Data($0) } + ciphertext),
            let padded = try? AES.GCM.open(sealed, using: cek)
        else { return nil }

        // First two bytes: big-endian padding length, then that much padding.
        guard padded.count >= 2 else { return nil }
        let padLength = Int(padded[padded.startIndex]) << 8 | Int(padded[padded.startIndex + 1])
        guard padded.count >= 2 + padLength else { return nil }
        return padded.dropFirst(2 + padLength)
    }

    /// Final `aes128gcm` (RFC 8188 / RFC 8291) — self-contained header.
    static func decryptAES128GCM(
        record: Data, receiverPrivateKey: P256.KeyAgreement.PrivateKey, authSecret: Data
    ) -> Data? {
        // Header: salt(16) | rs(4) | idlen(1) | keyid(idlen) | ciphertext
        guard record.count > 21 else { return nil }
        let salt = record.prefix(16)
        let idLength = Int(record[record.startIndex + 20])
        let headerLength = 21 + idLength
        guard idLength == 65, record.count > headerLength + 16 else { return nil }
        let senderPublicKey = record.dropFirst(21).prefix(idLength)
        let ciphertext = record.dropFirst(headerLength)

        guard
            let senderKey = try? P256.KeyAgreement.PublicKey(
                x963Representation: Data(senderPublicKey)),
            let sharedSecret = try? receiverPrivateKey.sharedSecretFromKeyAgreement(with: senderKey)
        else { return nil }

        var keyInfo = Data("WebPush: info\0".utf8)
        keyInfo.append(receiverPrivateKey.publicKey.x963Representation)
        keyInfo.append(Data(senderPublicKey))

        let prk = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: authSecret, sharedInfo: keyInfo, outputByteCount: 32)
        let cek = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: prk, salt: Data(salt),
            info: Data("Content-Encoding: aes128gcm\0".utf8), outputByteCount: 16)
        let nonceKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: prk, salt: Data(salt),
            info: Data("Content-Encoding: nonce\0".utf8), outputByteCount: 12)

        guard
            let nonce = try? AES.GCM.Nonce(data: nonceKey.withUnsafeBytes { Data($0) }),
            let sealed = try? AES.GCM.SealedBox(
                combined: nonce.withUnsafeBytes { Data($0) } + Data(ciphertext)),
            let padded = try? AES.GCM.open(sealed, using: cek)
        else { return nil }

        // Strip the trailing delimiter (0x02 for the final record) and padding zeros.
        var trimmed = padded
        while let last = trimmed.last, last == 0x00 {
            trimmed = trimmed.dropLast()
        }
        guard trimmed.last == 0x02 else { return nil }
        return trimmed.dropLast()
    }
}

// MARK: - Shared keychain reader (mirrors the app's KeychainService layout)

enum SharedKeychain {
    /// Reads a base64-string secret written by the app's KeychainService
    /// (kSecClassGenericPassword, service com.somincola.moro.webpush, value =
    /// base64 string utf8 bytes) from the shared default access group.
    static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.somincola.moro.webpush",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let base64 = String(data: data, encoding: .utf8)
        else { return nil }
        return Data(base64Encoded: base64)
    }
}

extension Data {
    init?(base64URLEncoded input: String) {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
