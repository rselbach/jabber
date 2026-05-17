import Foundation

enum NonDictationUIState: Equatable {
    case ready
    case downloading(ModelDownloadState)
    case loadingModel(status: String, progress: Double?)
    case error
}

enum NonDictationUIResolver {
    private static let defaultLoadingStatus = "Loading model..."

    static func resolve(
        forceLoading: Bool,
        modelState: TranscriptionService.State,
        downloadState: ModelDownloadState?
    ) -> NonDictationUIState {
        switch (forceLoading, modelState, downloadState) {
        case (_, .error, _):
            return .error
        case (true, _, _):
            return loadingState(for: modelState)
        case (_, _, let download?):
            return .downloading(download)
        case (_, .ready, _):
            return .ready
        case (_, .notReady, _):
            return .loadingModel(status: defaultLoadingStatus, progress: nil)
        case (_, .loading, _):
            return loadingState(for: modelState)
        }
    }

    private static func loadingState(for modelState: TranscriptionService.State) -> NonDictationUIState {
        guard case .loading(let status, let progress) = modelState else {
            return .loadingModel(status: defaultLoadingStatus, progress: nil)
        }
        return .loadingModel(status: status, progress: progress)
    }
}
