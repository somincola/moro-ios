//
//  KeychainService.swift
//  moro
//
//  Secure storage for authentication tokens using iOS Keychain.
//

import Foundation
import Security

enum MoroSharedContainer {
    nonisolated static let appGroupIdentifier = "group.com.somincola.moro.app"
    nonisolated static let composeDraftStagingDirectoryName = "ComposeDraftStaging"

    nonisolated static func sharedUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    nonisolated static func sharedContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    nonisolated static func composeDraftStagingDirectoryURL(fileManager: FileManager = .default) -> URL {
        let baseURL = sharedContainerURL(fileManager: fileManager)
            ?? fileManager.temporaryDirectory.appendingPathComponent("moro-shared", isDirectory: true)
        return baseURL.appendingPathComponent(composeDraftStagingDirectoryName, isDirectory: true)
    }

    nonisolated static func resolvedSharedKeychainAccessGroup() -> String? {
        // Return nil so KeychainService omits kSecAttrAccessGroup and the OS uses the
        // app's default keychain access group — the first `keychain-access-groups`
        // entitlement ("$(AppIdentifierPrefix)com.somincola.moro.shared"), resolved to the
        // CURRENT signing team's prefix. This avoids hardcoding a team ID and keeps token
        // storage working across signing-team changes (personal → somincola llc).
        nil
    }
}

final class KeychainService {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let service: String
    private let accessGroup: String?

    nonisolated init(
        service: String = "com.somincola.moro",
        accessGroup: String? = MoroSharedContainer.resolvedSharedKeychainAccessGroup()
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        var query = baseQuery(forKey: key, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        // Tokens live in a shared App-Group keychain; keep them on this device only so
        // they don't sync to other devices via encrypted backups. AfterFirstUnlock still
        // lets the Share Extension / background tasks read them while the device is locked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(baseQuery(forKey: key, accessGroup: accessGroup) as CFDictionary)
        if accessGroup != nil {
            SecItemDelete(baseQuery(forKey: key, accessGroup: nil) as CFDictionary)
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    func get(forKey key: String) throws -> String? {
        if let value = try readValue(forKey: key, accessGroup: accessGroup) {
            return value
        }

        guard accessGroup != nil,
              let legacyValue = try readValue(forKey: key, accessGroup: nil) else {
            return nil
        }

        try save(legacyValue, forKey: key)
        try? deleteValue(forKey: key, accessGroup: nil)
        return legacyValue
    }

    func delete(forKey key: String) throws {
        try deleteValue(forKey: key, accessGroup: accessGroup)
        if accessGroup != nil {
            try deleteValue(forKey: key, accessGroup: nil)
        }
    }

    func deleteAll() throws {
        try deleteAll(accessGroup: accessGroup)
        if accessGroup != nil {
            try deleteAll(accessGroup: nil)
        }
    }

    private func baseQuery(forKey key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func readValue(forKey key: String, accessGroup: String?) throws -> String? {
        var query = baseQuery(forKey: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return value
    }

    private func deleteValue(forKey key: String, accessGroup: String?) throws {
        let status = SecItemDelete(baseQuery(forKey: key, accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    private func deleteAll(accessGroup: String?) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return MoroL10n.AppError.decoding
        case .unhandledError:
            return MoroL10n.AppError.unknown
        }
    }
}
