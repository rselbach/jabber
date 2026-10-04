import Foundation

/// The recording overlay's clock: elapsed time, switching to a countdown once
/// the session limit is close so the automatic stop never comes as a surprise.
struct RecordingClock: Equatable {
    /// How long before the limit the clock turns into a warning countdown.
    static let warningWindow: TimeInterval = 60

    let text: String
    let isWarning: Bool

    init(elapsed: TimeInterval, limit: TimeInterval) {
        let remaining = max(0, limit - elapsed)
        guard remaining > Self.warningWindow else {
            // Round up so the countdown reaches 0:00 only at the stop itself.
            text = "Stops in \(Self.format(seconds: Int(remaining.rounded(.up))))"
            isWarning = true
            return
        }
        text = Self.format(seconds: Int(max(0, elapsed)))
        isWarning = false
    }

    private static func format(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
