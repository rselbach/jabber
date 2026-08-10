import Foundation
import Security

/// Shared generic-password operations for cloud post-processing API keys.
/// Provider wrappers below supply separate accounts so credentials never
/// overwrite each other. `errSecItemNotFound` means "no key stored" for reads
/// and deletes; every other unexpected status is surfaced to the Settings UI.
private enum PostProcessingKeychain {
    enum Error: LocalizedError {
        case unexpectedStatus(OSStatus, String)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status, context):
                return "Keychain \(context) failed (OSStatus \(status))."
            }
        }
    }

    /// Reads the stored API key. Returns `nil` when no item is stored.
    /// Throws on any keychain status other than success/item-not-found.
    static func readKey(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unexpectedStatus(status, "read")
        }
    }

    /// Stores `key`, creating or updating the item. An empty/whitespace key
    /// should be deleted via `deleteKey()` instead.
    static func saveKey(_ key: String, service: String, account: String) throws {
        let data = Data(key.utf8)

        // Update an existing item first; if none exists, add a new one.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // Accessible after first unlock so background dictation can read the
            // key without requiring an unlocked keychain prompt mid-session.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.unexpectedStatus(addStatus, "save")
            }
            return
        default:
            throw Error.unexpectedStatus(updateStatus, "update")
        }
    }

    /// Deletes the stored API key. No-op (not an error) when no item exists.
    static func deleteKey(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw Error.unexpectedStatus(status, "delete")
        }
    }
}

/// Keychain-backed storage for the OpenRouter API key.
enum OpenRouterKeychain {
    static let service = "com.rselbach.jabber"
    static let account = "openRouterApiKey"

    static func readKey(service: String = service, account: String = account) throws -> String? {
        try PostProcessingKeychain.readKey(service: service, account: account)
    }

    static func saveKey(
        _ key: String,
        service: String = service,
        account: String = account
    ) throws {
        try PostProcessingKeychain.saveKey(key, service: service, account: account)
    }

    static func deleteKey(service: String = service, account: String = account) throws {
        try PostProcessingKeychain.deleteKey(service: service, account: account)
    }
}

/// Keychain-backed storage for the OpenCode Zen API key. The account differs
/// from OpenRouter's so selecting or editing one provider cannot affect the
/// other's credential.
enum OpenCodeZenKeychain {
    static let service = "com.rselbach.jabber"
    static let account = "openCodeZenApiKey"

    static func readKey(service: String = service, account: String = account) throws -> String? {
        try PostProcessingKeychain.readKey(service: service, account: account)
    }

    static func saveKey(
        _ key: String,
        service: String = service,
        account: String = account
    ) throws {
        try PostProcessingKeychain.saveKey(key, service: service, account: account)
    }

    static func deleteKey(service: String = service, account: String = account) throws {
        try PostProcessingKeychain.deleteKey(service: service, account: account)
    }
}
