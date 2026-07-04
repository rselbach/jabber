import Security
import XCTest
@testable import Jabber

/// Live Keychain tests for `OpenRouterKeychain`.
///
/// These touch the real macOS Keychain but use a per-test-instance UUID-
/// namespaced service/account so they never collide with the user's real
/// Jabber OpenRouter key (which uses `com.rselbach.jabber` /
/// `openRouterApiKey`). Each test gets a fresh `XCTestCase` instance, so
/// `service` is a unique UUID per test method. `setUp`/`tearDown` delete the
/// item unconditionally (ignoring not-found) so nothing persists even if a
/// test fails midway. Generic password items without access-control prompts are
/// reliable in the xctest host.
final class OpenRouterKeychainTests: XCTestCase {
    /// Unique per test instance so tests never share a keychain item.
    private let service = "com.rselbach.jabber.tests.\(UUID().uuidString)"
    private let account = "openRouterApiKey"

    override func setUp() async throws {
        try await super.setUp()
        // Start clean; ignore not-found.
        try? OpenRouterKeychain.deleteKey(service: service, account: account)
    }

    override func tearDown() async throws {
        try? OpenRouterKeychain.deleteKey(service: service, account: account)
        try await super.tearDown()
    }

    func testReadReturnsNilWhenAbsent() throws {
        XCTAssertNil(try OpenRouterKeychain.readKey(service: service, account: account))
    }

    func testSaveAndReadRoundTrip() throws {
        try OpenRouterKeychain.saveKey("sk-test-greendale", service: service, account: account)
        XCTAssertEqual(try OpenRouterKeychain.readKey(service: service, account: account), "sk-test-greendale")
    }

    func testSaveOverwritesExistingKey() throws {
        try OpenRouterKeychain.saveKey("old-key", service: service, account: account)
        try OpenRouterKeychain.saveKey("new-key", service: service, account: account)
        XCTAssertEqual(try OpenRouterKeychain.readKey(service: service, account: account), "new-key")
    }

    func testSaveUpdatesAccessibilityForExistingKey() throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("old-key".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)

        try OpenRouterKeychain.saveKey("new-key", service: service, account: account)

        XCTAssertEqual(try OpenRouterKeychain.readKey(service: service, account: account), "new-key")
        XCTAssertEqual(accessibilityMatchStatus(), errSecSuccess)
    }

    func testDeleteRemovesStoredKey() throws {
        try OpenRouterKeychain.saveKey("troy-barnes", service: service, account: account)
        try OpenRouterKeychain.deleteKey(service: service, account: account)
        XCTAssertNil(try OpenRouterKeychain.readKey(service: service, account: account))
    }

    func testDeleteWhenAbsentDoesNotThrow() {
        XCTAssertNoThrow(try OpenRouterKeychain.deleteKey(service: service, account: account))
    }

    private func accessibilityMatchStatus() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }
}
