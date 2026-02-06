import XCTest
@testable import Jabber

final class NonDictationUIResolverTests: XCTestCase {
    func testResolveReturnsLoadingModelWhenModelIsNotReady() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .notReady,
            isModelLoadInProgress: false,
            downloadState: nil
        )

        XCTAssertEqual(state, .loadingModel)
    }

    func testResolveReturnsReadyWhenModelIsReadyAndNoDownload() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            isModelLoadInProgress: false,
            downloadState: nil
        )

        XCTAssertEqual(state, .ready)
    }

    func testResolveReturnsErrorWhenModelStateIsError() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .error("boom"),
            isModelLoadInProgress: false,
            downloadState: sampleDownloadState()
        )

        XCTAssertEqual(state, .error)
    }

    func testResolveReturnsDownloadingWhenDownloadStateExists() {
        let downloadState = sampleDownloadState()
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            isModelLoadInProgress: false,
            downloadState: downloadState
        )

        XCTAssertEqual(state, .downloading(downloadState))
    }

    func testResolveForceLoadingOverridesDownloadState() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: true,
            modelState: .ready,
            isModelLoadInProgress: false,
            downloadState: sampleDownloadState()
        )

        XCTAssertEqual(state, .loadingModel)
    }

    func testResolveReturnsLoadingWhenModelIsLoadingAndLoadInProgress() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .loading,
            isModelLoadInProgress: true,
            downloadState: nil
        )

        XCTAssertEqual(state, .loadingModel)
    }

    private func sampleDownloadState() -> ModelDownloadState {
        ModelDownloadState(
            modelId: "base",
            progress: 0.5,
            status: "Downloading Base... 50%",
            phase: .progress,
            errorDescription: nil,
            isCancelled: false
        )
    }
}
