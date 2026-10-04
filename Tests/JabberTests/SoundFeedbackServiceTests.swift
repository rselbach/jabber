import XCTest
@testable import Jabber

final class SoundFeedbackServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberSoundTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    /// Every packaging layout finds the sound; a missing one yields nil
    /// instead of crashing the way `Bundle.module` would.
    func testFindsSoundsInEveryPackagingLayout() throws {
        let cases: [String: (soundDirectory: String?, wantFound: Bool)] = [
            "release app with flat resources": ("", true),
            "swift run with a structured SwiftPM bundle": ("Jabber_Jabber.bundle/Contents/Resources", true),
            "swift run with a flat SwiftPM bundle": ("Jabber_Jabber.bundle", true),
            "sounds missing": (nil, false)
        ]

        for (name, tc) in cases {
            let mainDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: mainDirectory, withIntermediateDirectories: true)
            if let soundDirectory = tc.soundDirectory {
                let directory = mainDirectory.appendingPathComponent(soundDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data().write(to: directory.appendingPathComponent("dictation_start.m4a"))
            }
            let mainBundle = try XCTUnwrap(Bundle(url: mainDirectory), name)

            let got = SoundFeedbackService.soundURL(for: .dictationStart, mainBundle: mainBundle)

            XCTAssertEqual(got != nil, tc.wantFound, name)
            if let got {
                XCTAssertEqual(got.lastPathComponent, "dictation_start.m4a", name)
            }
        }
    }
}
