import AVFoundation
import Foundation
import os

/// Plays short earcons when dictation starts and stops so the user gets
/// confirmation without looking at the overlay. Playback is skipped when the
/// sound-feedback setting is off. Players are created lazily and cached.
@MainActor
final class SoundFeedbackService {
    static let shared = SoundFeedbackService()

    enum Cue: String {
        case dictationStart = "dictation_start"
        case dictationStop = "dictation_stop"
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "SoundFeedbackService")

    func play(_ cue: Cue) {
        guard TypedSettings[.soundFeedbackEnabled] else { return }
        guard let player = player(for: cue) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for cue: Cue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }

        guard let url = soundURL(for: cue) else {
            logger.error("Missing sound resource for cue \(cue.rawValue, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[cue] = player
            return player
        } catch {
            logger.error("Failed to load sound \(cue.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Release builds flatten the SwiftPM resource bundle into the app's
    /// Resources directory (see scripts/release.sh), so look in Bundle.main
    /// first and only then fall back to Bundle.module (dev builds via
    /// `swift run`, where the resource bundle sits next to the bare binary).
    private func soundURL(for cue: Cue) -> URL? {
        if let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "m4a") {
            return url
        }
        return Bundle.module.url(forResource: cue.rawValue, withExtension: "m4a")
    }
}
