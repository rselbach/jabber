import AppKit
import Foundation
import SwiftUI

@MainActor
final class WaveformView: ObservableObject {
    private var circularBuffer: [Float] = []
    @Published private(set) var cachedLevels: [Float] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var processingLabel = "Transcribing..."
    @Published private(set) var partialTranscription = ""
    @Published private(set) var targetAppIcon: NSImage?
    /// Brief, non-disruptive message shown on the overlay when post-processing
    /// fell back to the raw transcript after a guardrail rejection. Auto-clears
    /// after `fallbackNoticeDuration` so no click-to-dismiss UI is needed.
    @Published private(set) var fallbackNotice: String?

    /// Invoked when the fallback notice auto-clears (after its duration) or is
    /// cleared explicitly, so the overlay window can complete a deferred hide.
    /// Not fired by `reset()` (a new session abandons the notice without
    /// completing a stale hide).
    var onFallbackNoticeCleared: (() -> Void)?

    private let maxSamples = 60
    private var writeIndex = 0
    private var isFull = false
    private var fallbackClearTask: Task<Void, Never>?
    private let fallbackNoticeDuration: TimeInterval = 2.0

    var hasActiveFallbackNotice: Bool {
        fallbackNotice != nil
    }

    var levels: [Float] {
        cachedLevels
    }

    func addLevel(_ level: Float) {
        if circularBuffer.count < maxSamples {
            circularBuffer.append(level)
        } else {
            // Use circular buffer: overwrite oldest sample
            isFull = true
            circularBuffer[writeIndex] = level
            writeIndex = (writeIndex + 1) % maxSamples
        }
        cachedLevels = computeLevels()
    }

    private func computeLevels() -> [Float] {
        guard isFull else {
            return circularBuffer
        }
        // Return levels in chronological order (oldest to newest)
        return Array(circularBuffer[writeIndex...]) + Array(circularBuffer[..<writeIndex])
    }

    func reset() {
        circularBuffer.removeAll()
        cachedLevels.removeAll()
        writeIndex = 0
        isFull = false
        isProcessing = false
        processingLabel = "Transcribing..."
        partialTranscription = ""
        targetAppIcon = nil
        // Abandon any in-flight notice without firing the cleared callback: a
        // reset means the overlay is being reused for a new session, so a
        // pending deferred hide must not fire against the fresh state.
        fallbackClearTask?.cancel()
        fallbackNotice = nil
    }

    func showProcessing() {
        isProcessing = true
        processingLabel = "Transcribing..."
    }

    /// Switches the processing overlay to a "Refining..." state used while
    /// Apple Intelligence post-processing runs. Same UI as transcription.
    func showRefining() {
        isProcessing = true
        processingLabel = "Refining..."
    }

    /// Shows a brief red fallback notice on the overlay. Auto-clears after
    /// `fallbackNoticeDuration` and fires `onFallbackNoticeCleared` so the
    /// overlay window can complete a deferred hide once the notice has been
    /// read. Replaces any prior notice.
    func showFallbackNotice(_ text: String) {
        fallbackClearTask?.cancel()
        fallbackNotice = text
        let duration = fallbackNoticeDuration
        fallbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.clearFallbackNotice()
        }
    }

    /// Clears the fallback notice and fires `onFallbackNoticeCleared`.
    func clearFallbackNotice() {
        fallbackNotice = nil
        onFallbackNoticeCleared?()
    }

    func updatePartialTranscription(_ text: String) {
        partialTranscription = text
    }

    func setTargetAppIcon(_ icon: NSImage?) {
        targetAppIcon = icon
    }
}
