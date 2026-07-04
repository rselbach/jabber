import XCTest
@testable import Jabber

final class NonDictationUIResolverTests: XCTestCase {
    func testResolveReturnsLoadingModelWhenModelIsNotReadyAndLoadInProgress() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .notReady,
            downloadState: nil,
            isLoadInProgress: true
        )

        XCTAssertEqual(state, defaultLoadingState())
    }

    func testResolveReturnsErrorWhenModelIsNotReadyAndNoLoadInProgress() {
        // After the user dismisses the migration notice with "Not Now" (or any
        // path that leaves no load running), an indeterminate "Loading
        // model..." spinner would be a lie. The honest state is that the model
        // is not usable and nothing is preparing it.
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .notReady,
            downloadState: nil,
            isLoadInProgress: false
        )

        XCTAssertEqual(state, .error)
    }

    func testResolveReturnsReadyWhenModelIsReadyAndNoDownload() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            downloadState: nil,
            isLoadInProgress: false
        )

        XCTAssertEqual(state, .ready)
    }

    func testResolveReturnsErrorWhenModelStateIsError() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .error("boom"),
            downloadState: sampleDownloadState(),
            isLoadInProgress: false
        )

        XCTAssertEqual(state, .error)
    }

    func testResolveReturnsDownloadingWhenDownloadStateExists() {
        let downloadState = sampleDownloadState()
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            downloadState: downloadState,
            isLoadInProgress: false
        )

        XCTAssertEqual(state, .downloading(downloadState))
    }

    func testResolvePrefersDownloadStateOverGenericLoadingState() {
        let downloadState = sampleDownloadState()
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .loading(status: "Preparing model...", progress: nil),
            downloadState: downloadState,
            isLoadInProgress: true
        )

        XCTAssertEqual(state, .downloading(downloadState))
    }

    func testResolveForceLoadingOverridesDownloadState() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: true,
            modelState: .ready,
            downloadState: sampleDownloadState(),
            isLoadInProgress: false
        )

        XCTAssertEqual(state, defaultLoadingState())
    }

    func testResolveReturnsLoadingProgressWhenModelIsLoading() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .loading(status: "Loading text decoder weights...", progress: 0.92),
            downloadState: nil,
            isLoadInProgress: true
        )

        XCTAssertEqual(
            state,
            .loadingModel(status: "Loading text decoder weights...", progress: 0.92)
        )
    }

    private func defaultLoadingState() -> NonDictationUIState {
        .loadingModel(status: "Loading model...", progress: nil)
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
