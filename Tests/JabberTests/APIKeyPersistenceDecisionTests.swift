import XCTest
@testable import Jabber

@MainActor
final class APIKeyPersistenceDecisionTests: XCTestCase {
    // Regression: a transient keychain read failure (e.g. user cancelled the
    // auth prompt) blanks the SecureField. onDisappear fires on every sidebar
    // switch and previously treated that blank as "delete stored key" — wiping
    // the user's real key. Empty values must stay blocked after a failed load,
    // but a freshly typed key should still save; unchanged values skip writes.
    func testShouldPersistGuardsAgainstReadFailureAndUnchangedValues() {
        let tests: [String: (input: (
            didLoadSuccessfully: Bool,
            isLoadInProgress: Bool,
            loadedValue: String,
            currentValue: String
        ), want: Bool)] = [
            "load in progress: skip blank save": (
                input: (false, true, "", ""), want: false
            ),
            "load in progress: skip typed value until load resolves or edit cancels it": (
                input: (false, true, "", "sk-key-greendale"), want: false
            ),
            "read failed: never persist, even if field looks deletable": (
                input: (false, false, "", ""), want: false
            ),
            "read failed, user typed a new key: persist": (
                input: (false, false, "", "sk-key-greendale"), want: true
            ),
            "read failed, user typed a new key with whitespace: persist": (
                input: (false, false, "", "  sk-key-greendale  "), want: true
            ),
            "loaded, unchanged key: skip the write": (
                input: (true, false, "sk-troy-barnes", "sk-troy-barnes"), want: false
            ),
            "loaded, unchanged key with surrounding whitespace: skip the write": (
                input: (true, false, "  sk-troy-barnes  ", "sk-troy-barnes"), want: false
            ),
            "loaded, user edited to a new key: persist": (
                input: (true, false, "sk-old", "sk-new-abed"), want: true
            ),
            "loaded, user cleared the field: persist (deletion)": (
                input: (true, false, "sk-señor-chang", ""), want: true
            ),
            "loaded, user blanked to whitespace: persist (deletion)": (
                input: (true, false, "sk-señor-chang", "   "), want: true
            )
        ]

        for (name, tc) in tests {
            let got = APIKeyPersistenceDecision.shouldPersist(
                didLoadSuccessfully: tc.input.didLoadSuccessfully,
                isLoadInProgress: tc.input.isLoadInProgress,
                loadedValue: tc.input.loadedValue,
                currentValue: tc.input.currentValue
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }
}
