import XCTest
@testable import Jabber

final class SetupReadinessResolverTests: XCTestCase {
    func testReadyWhenPermissionsAndModelAreAvailable() {
        let readiness = SetupReadinessResolver.resolve(
            hasMicrophonePermission: true,
            hasAccessibilityPermission: true,
            requiresAccessibilityPermission: true,
            hasDownloadedModel: true,
            isDownloadingModel: false
        )

        XCTAssertTrue(readiness.isComplete)
        XCTAssertTrue(readiness.requiredSteps.isEmpty)
        XCTAssertEqual(readiness.steps.map(\.id), SetupStepID.allCases)
    }

    func testAccessibilityIsCompleteWhenClipboardModeDoesNotRequireIt() throws {
        let readiness = SetupReadinessResolver.resolve(
            hasMicrophonePermission: true,
            hasAccessibilityPermission: false,
            requiresAccessibilityPermission: false,
            hasDownloadedModel: true,
            isDownloadingModel: false
        )

        XCTAssertTrue(readiness.isComplete)
        let accessibility = try XCTUnwrap(readiness.steps.first { $0.id == .accessibility })
        XCTAssertEqual(accessibility.status, .complete)
        XCTAssertNil(accessibility.action)
    }

    func testMissingRequirementsExposeActions() throws {
        let readiness = SetupReadinessResolver.resolve(
            hasMicrophonePermission: false,
            hasAccessibilityPermission: false,
            requiresAccessibilityPermission: true,
            hasDownloadedModel: false,
            isDownloadingModel: false
        )

        XCTAssertFalse(readiness.isComplete)
        let microphone = try XCTUnwrap(readiness.steps.first { $0.id == .microphone })
        let accessibility = try XCTUnwrap(readiness.steps.first { $0.id == .accessibility })
        let model = try XCTUnwrap(readiness.steps.first { $0.id == .model })

        XCTAssertEqual(microphone.status, .needsAction)
        XCTAssertEqual(microphone.action, .requestMicrophone)
        XCTAssertEqual(accessibility.status, .needsAction)
        XCTAssertEqual(accessibility.action, .openAccessibilitySettings)
        XCTAssertEqual(model.status, .needsAction)
        XCTAssertEqual(model.action, .downloadBaseModel)
    }

    func testDownloadingModelIsInProgress() throws {
        let readiness = SetupReadinessResolver.resolve(
            hasMicrophonePermission: true,
            hasAccessibilityPermission: true,
            requiresAccessibilityPermission: true,
            hasDownloadedModel: false,
            isDownloadingModel: true
        )

        XCTAssertFalse(readiness.isComplete)
        let model = try XCTUnwrap(readiness.steps.first { $0.id == .model })
        XCTAssertEqual(model.status, .inProgress)
        XCTAssertNil(model.action)
    }
}
