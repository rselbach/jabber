import AppKit
import Foundation
import SwiftUI

@MainActor
final class WaveformView: ObservableObject {
    @Published private var circularBuffer: [Float] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var processingLabel = "Transcribing..."
    @Published private(set) var partialTranscription = ""
    @Published private(set) var targetAppIcon: NSImage?

    private let maxSamples = 60
    private var writeIndex = 0
    private var isFull = false

    var levels: [Float] {
        guard isFull else {
            return circularBuffer
        }
        // Return levels in chronological order (oldest to newest)
        return Array(circularBuffer[writeIndex...]) + Array(circularBuffer[..<writeIndex])
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
    }

    func reset() {
        circularBuffer.removeAll()
        writeIndex = 0
        isFull = false
        isProcessing = false
        processingLabel = "Transcribing..."
        partialTranscription = ""
        targetAppIcon = nil
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

    func updatePartialTranscription(_ text: String) {
        partialTranscription = text
    }

    func setTargetAppIcon(_ icon: NSImage?) {
        targetAppIcon = icon
    }
}
