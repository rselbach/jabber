import XCTest
@testable import Jabber

final class LanguageMenuTests: XCTestCase {
    func testRecentLanguages() {
        let tests: [String: (current: String, stored: String, want: [String])] = [
            "nothing stored": ("en", "", ["en"]),
            "current moves to the front": ("pt", "en,pt,fr", ["pt", "en", "fr"]),
            "capped": ("ja", "en,pt,fr,de,es", ["ja", "en", "pt", "fr", "de"]),
            "unknown codes dropped": ("en", "xx,pt,,auto", ["en", "pt", "auto"])
        ]
        for (name, tc) in tests {
            XCTAssertEqual(LanguageMenu.recentLanguages(adding: tc.current, to: tc.stored), tc.want, name)
        }
    }

    func testItemsAreSortedByNameAndMarkTheCurrentLanguage() {
        let items = LanguageMenu.items(recentLanguages: ["pt", "auto", "en"], current: "pt")

        XCTAssertEqual(items.map(\.code), ["auto", "en", "pt"])
        XCTAssertEqual(items.map(\.isSelected), [false, false, true])
        XCTAssertEqual(items.first?.title, "Automatic")
    }

    func testModelForLanguage() {
        let english = AppMode.parakeetModelId
        let multilingual = AppMode.parakeetMultilingualModelId
        let apple = AppMode.appleSpeechModelId
        let tests: [String: (language: String, current: String, downloaded: Set<String>, want: String?)] = [
            "current model covers it": ("en", multilingual, [english, multilingual, apple], multilingual),
            "switches to the recommended model": ("pt", english, [english, multilingual, apple], multilingual),
            "falls back to a downloaded alternative": ("pt", english, [english, apple], apple),
            "nothing downloaded can": ("ja", english, [english], nil),
            "current not downloaded": ("en", multilingual, [english], english)
        ]
        for (name, tc) in tests {
            let got = LanguageMenu.modelId(
                for: tc.language,
                currentModelId: tc.current,
                downloadedModelIds: tc.downloaded
            )
            XCTAssertEqual(got, tc.want, name)
        }
    }
}
