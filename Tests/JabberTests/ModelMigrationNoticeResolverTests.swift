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

    func testNoticeKeyBuildsStableMigrationKey() {
        XCTAssertEqual(
            ModelMigrationNoticeResolver.noticeKey(for: ModelManager.Migration(from: "medium", to: "qwen3")),
            "medium->qwen3"
        )
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

    func testFallbackPrefersDownloadedRecommendedModel() {
        XCTAssertEqual(
            ModelFallbackResolver.downloadedFallbackModelId(
                recommendedModelId: "nemotron",
                downloadedModelIds: ["apple-speech", "nemotron"]
            ),
            "nemotron"
        )
    }

    func testFallbackUsesFirstDownloadedModelWhenRecommendedMissing() {
        XCTAssertEqual(
            ModelFallbackResolver.downloadedFallbackModelId(
                recommendedModelId: "nemotron",
                downloadedModelIds: ["apple-speech", "qwen3"]
            ),
            "apple-speech"
        )
    }

    func testFallbackReturnsNilWithoutDownloadedModels() {
        XCTAssertNil(ModelFallbackResolver.downloadedFallbackModelId(
            recommendedModelId: "nemotron",
            downloadedModelIds: []
        ))
    }

    func testDeclinedDownloadMatchesCurrentMigrationKey() {
        XCTAssertTrue(ModelMigrationDeclineResolver.isDownloadDeclined(
            migration: ModelManager.Migration(from: "medium", to: "qwen3-1.7b-4bit"),
            declinedNoticeKey: "medium->qwen3-1.7b-4bit",
            newModelDownloaded: false
        ))
    }

    func testDeclinedDownloadIgnoresDifferentMigrationKey() {
        XCTAssertFalse(ModelMigrationDeclineResolver.isDownloadDeclined(
            migration: ModelManager.Migration(from: "small", to: "qwen3-0.6b-4bit"),
            declinedNoticeKey: "medium->qwen3-1.7b-4bit",
            newModelDownloaded: false
        ))
    }

    func testDeclinedDownloadStopsBlockingWhenReplacementDownloaded() {
        XCTAssertFalse(ModelMigrationDeclineResolver.isDownloadDeclined(
            migration: ModelManager.Migration(from: "medium", to: "qwen3-1.7b-4bit"),
            declinedNoticeKey: "medium->qwen3-1.7b-4bit",
            newModelDownloaded: true
        ))
    }
}
