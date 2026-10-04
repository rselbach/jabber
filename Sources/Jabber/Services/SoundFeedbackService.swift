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
        if let player = players[cue] {
            return player
        }

        guard let url = Self.soundURL(for: cue) else {
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

    /// Release builds copy the SwiftPM resources flat into the app's Resources
    /// directory (see scripts/release.sh), so look in the main bundle first.
    /// Dev builds via `swift run` keep SwiftPM's resource bundle next to the
    /// bare binary. That bundle is located by hand: `Bundle.module` calls
    /// fatalError when it is missing, and a missing sound must never crash a
    /// dictation, only silence it.
    nonisolated static func soundURL(for cue: Cue, mainBundle: Bundle = .main) -> URL? {
        if let url = mainBundle.url(forResource: cue.rawValue, withExtension: "m4a") {
            return url
        }
        let resourceBundleURL = mainBundle.bundleURL.appendingPathComponent("Jabber_Jabber.bundle")
        return Bundle(url: resourceBundleURL)?.url(forResource: cue.rawValue, withExtension: "m4a")
    }
}
