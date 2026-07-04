import XCTest
@testable import Jabber

@MainActor
final class APIKeyPersistenceDecisionTests: XCTestCase {
    // Regression: a transient keychain read failure (e.g. user cancelled the
    // auth prompt) blanks the SecureField. onDisappear fires on every sidebar
    // switch and previously treated that blank as "delete stored key" — wiping
    // the user's real key. Load must succeed before any write, and unchanged
    // values skip the write entirely.
    func testShouldPersistGuardsAgainstReadFailureAndUnchangedValues() {
        let tests: [String: (input: (
            didLoadSuccessfully: Bool,
            loadedValue: String,
            currentValue: String
        ), want: Bool)] = [
            "read failed: never persist, even if field looks deletable": (
                input: (false, "", ""), want: false
            ),
            "read failed: never persist, even if field has a value": (
                input: (false, "", "sk-key-greendale"), want: false
            ),
            "loaded, unchanged key: skip the write": (
                input: (true, "sk-troy-barnes", "sk-troy-barnes"), want: false
            ),
            "loaded, unchanged key with surrounding whitespace: skip the write": (
                input: (true, "  sk-troy-barnes  ", "sk-troy-barnes"), want: false
            ),
            "loaded, user edited to a new key: persist": (
                input: (true, "sk-old", "sk-new-abed"), want: true
            ),
            "loaded, user cleared the field: persist (deletion)": (
                input: (true, "sk-señor-chang", ""), want: true
            ),
            "loaded, user blanked to whitespace: persist (deletion)": (
                input: (true, "sk-señor-chang", "   "), want: true
            )
        ]

        for (name, tc) in tests {
            let got = APIKeyPersistenceDecision.shouldPersist(
                didLoadSuccessfully: tc.input.didLoadSuccessfully,
                loadedValue: tc.input.loadedValue,
                currentValue: tc.input.currentValue
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }
}
