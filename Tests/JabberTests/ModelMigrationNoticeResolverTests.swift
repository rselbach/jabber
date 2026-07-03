import XCTest
@testable import Jabber

@MainActor
final class ModelMigrationNoticeResolverTests: XCTestCase {
    func testNoMigrationReturnsNil() {
        XCTAssertNil(ModelMigrationNoticeResolver.resolve(
            migration: nil,
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: ""
        ))
    }

    func testDownloadedReplacementSuppressesNotice() {
        XCTAssertNil(ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "new"),
            newModelDownloaded: true,
            newModelIsBuiltIn: false,
            lastShownKey: ""
        ))
    }

    func testBuiltInReplacementSuppressesNotice() {
        XCTAssertNil(ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "apple-speech"),
            newModelDownloaded: false,
            newModelIsBuiltIn: true,
            lastShownKey: ""
        ))
    }

    func testAlreadyShownForKeySuppressesNotice() {
        let first = ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "new"),
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: ""
        )
        XCTAssertEqual(first?.noticeKey, "old->new")

        let second = ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "new"),
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: "old->new"
        )
        XCTAssertNil(second)
    }

    func testDifferentMigrationShowsNoticeAgain() {
        let second = ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "new", to: "newer"),
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: "old->new"
        )
        XCTAssertEqual(second?.noticeKey, "new->newer")
        XCTAssertEqual(second?.migration.from, "new")
        XCTAssertEqual(second?.migration.to, "newer")
    }

    func testReturnsMigrationDetails() {
        let notice = ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "new"),
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: ""
        )
        XCTAssertEqual(notice?.migration.from, "old")
        XCTAssertEqual(notice?.migration.to, "new")
        XCTAssertEqual(notice?.noticeKey, "old->new")
    }

    func testEmptyShownKeyDoesNotMatchValidMigration() {
        let notice = ModelMigrationNoticeResolver.resolve(
            migration: ModelManager.Migration(from: "old", to: "new"),
            newModelDownloaded: false,
            newModelIsBuiltIn: false,
            lastShownKey: ""
        )
        XCTAssertNotNil(notice, "Empty last-shown key means never prompted; notice should fire")
    }
}
