//
//  WebPushKeyStore.swift
//  moro
//
//  Device-wide Web Push (RFC 8291) receiver keys: a P-256 key pair plus a
//  16-byte auth secret. The private key never leaves the device — Mastodon
//  encrypts against the public key, and the Notification Service Extension
//  decrypts on-device. Stored (base64) in the default keychain access group,
//  whose first entitlement entry is the shared
//  $(AppIdentifierPrefix)com.somincola.moro.shared group, so the extension
//  can read them; KeychainService writes kSecAttrAccessibleAfterFirstUnlock
//  so pushes arriving after a reboot-unlock can decrypt.
//

import CryptoKit
import Foundation

enum WebPushKeyStore {
    static let keychainService = "com.somincola.moro.webpush"
    static let privateKeyAccount = "webpush_private_key"
    static let authSecretAccount = "webpush_auth_secret"

    private static var keychain: KeychainService {
        KeychainService(service: keychainService)
    }

    /// The receiver key pair, generated once and persisted.
    static func privateKey() throws -> P256.KeyAgreement.PrivateKey {
        if let base64 = try? keychain.get(forKey: privateKeyAccount),
            let data = Data(base64Encoded: base64),
            let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: data)
        {
            return key
        }
        let key = P256.KeyAgreement.PrivateKey()
        try keychain.save(key.rawRepresentation.base64EncodedString(), forKey: privateKeyAccount)
        return key
    }

    /// The 16-byte Web Push auth secret, generated once and persisted.
    static func authSecret() throws -> Data {
        if let base64 = try? keychain.get(forKey: authSecretAccount),
            let data = Data(base64Encoded: base64),
            data.count == 16
        {
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        try keychain.save(data.base64EncodedString(), forKey: authSecretAccount)
        return data
    }

    /// Uncompressed (65-byte X9.63) public key, base64url — the `p256dh`
    /// subscription field.
    static func publicKeyBase64URL() throws -> String {
        try privateKey().publicKey.x963Representation.base64URLEncodedString()
    }

    /// Auth secret, base64url — the `auth` subscription field.
    static func authSecretBase64URL() throws -> String {
        try authSecret().base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
