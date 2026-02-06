import Foundation

enum NonDictationUIState: Equatable {
    case ready
    case downloading(ModelDownloadState)
    case loadingModel
    case error
}

enum NonDictationUIResolver {
    static func resolve(
        forceLoading: Bool,
        modelState: WhisperService.State,
        isModelLoadInProgress: Bool,
        downloadState: ModelDownloadState?
    ) -> NonDictationUIState {
        switch (forceLoading, modelState, isModelLoadInProgress, downloadState) {
        case (_, .error, _, _):
            return .error
        case (true, _, _, _):
            return .loadingModel
        case (_, .loading, true, _):
            return .loadingModel
        case (_, _, _, let download?):
            return .downloading(download)
        case (_, .ready, _, _):
            return .ready
        case (_, .notReady, _, _):
            return .loadingModel
        case (_, .loading, _, _):
            return .loadingModel
        }
    }
}
