import Foundation

/// How long transcripts stay in history.
enum HistoryRetention: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case forever

    static let defaultValue = HistoryRetention.month

    var id: String {
        rawValue
    }

    /// Age past which entries are removed, or `nil` to keep them.
    var maxAge: TimeInterval? {
        switch self {
        case .week:
            return 7 * 24 * 60 * 60
        case .month:
            return 30 * 24 * 60 * 60
        case .forever:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .week:
            return "1 Week"
        case .month:
            return "1 Month"
        case .forever:
            return "Forever"
        }
    }
}

/// What dictation history keeps, read from settings at save time.
struct DictationHistoryPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var keepsAudio: Bool
    var retention: HistoryRetention
}
