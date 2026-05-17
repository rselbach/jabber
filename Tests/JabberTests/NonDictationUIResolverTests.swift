import XCTest
@testable import Jabber

final class NonDictationUIResolverTests: XCTestCase {
    func testResolveReturnsLoadingModelWhenModelIsNotReady() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .notReady,
            downloadState: nil
        )

        XCTAssertEqual(state, defaultLoadingState())
    }

    func testResolveReturnsReadyWhenModelIsReadyAndNoDownload() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            downloadState: nil
        )

        XCTAssertEqual(state, .ready)
    }

    func testResolveReturnsErrorWhenModelStateIsError() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .error("boom"),
            downloadState: sampleDownloadState()
        )

        XCTAssertEqual(state, .error)
    }

    func testResolveReturnsDownloadingWhenDownloadStateExists() {
        let downloadState = sampleDownloadState()
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .ready,
            downloadState: downloadState
        )

        XCTAssertEqual(state, .downloading(downloadState))
    }

    func testResolvePrefersDownloadStateOverGenericLoadingState() {
        let downloadState = sampleDownloadState()
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .loading(status: "Preparing model...", progress: nil),
            downloadState: downloadState
        )

        XCTAssertEqual(state, .downloading(downloadState))
    }

    func testResolveForceLoadingOverridesDownloadState() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: true,
            modelState: .ready,
            downloadState: sampleDownloadState()
        )

        XCTAssertEqual(state, defaultLoadingState())
    }

    func testResolveReturnsLoadingProgressWhenModelIsLoading() {
        let state = NonDictationUIResolver.resolve(
            forceLoading: false,
            modelState: .loading(status: "Loading text decoder weights...", progress: 0.92),
            downloadState: nil
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
