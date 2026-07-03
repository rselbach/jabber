import Foundation
import Security
import os

/// Minimal Keychain wrapper for the OpenRouter API key only. Stores the key as
/// a generic password item so it lives in the macOS Keychain (never in
/// UserDefaults). Service/account are namespaced to Jabber's bundle id.
///
/// All operations throw `OpenRouterKeychain.Error` on unexpected OSStatus values
/// — no silent failures. `errSecItemNotFound` is treated as "no key stored" and
/// is therefore not an error for read/delete. The Settings UI calls these
/// throwing functions directly and surfaces failures as inline red text.
enum OpenRouterKeychain {
    /// Keychain service. Matches Jabber's bundle/log subsystem id.
    static let service = "com.rselbach.jabber"

    /// Keychain account identifying the OpenRouter API key item.
    static let account = "openRouterApiKey"

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
    static func readKey(service: String = service, account: String = account) throws -> String? {
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
    static func saveKey(
        _ key: String,
        service: String = service,
        account: String = account
    ) throws {
        let data = Data(key.utf8)

        // Update an existing item first; if none exists, add a new one.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
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
    static func deleteKey(service: String = service, account: String = account) throws {
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
