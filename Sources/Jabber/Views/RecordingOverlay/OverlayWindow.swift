import AppKit
import SwiftUI
import os

@MainActor
final class OverlayWindow {
    private var window: NSPanel?
    private var waveformView: WaveformView?
    private var hostingView: NSHostingView<WaveformContainer>?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "OverlayWindow")

    func show() {
        if window == nil {
            guard createWindow() else {
                logger.error("Failed to create overlay window - no screen available")
                return
            }
        }
        waveformView?.reset()
        window?.orderFront(nil)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
                self?.window?.alphaValue = 1
            }
        }
    }

    func updateLevel(_ level: Float) {
        waveformView?.addLevel(level)
    }

    func showProcessing() {
        waveformView?.showProcessing()
    }

    @discardableResult
    private func createWindow() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let screenFrame = screen.visibleFrame

        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 60
        let bottomMargin: CGFloat = 100

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + bottomMargin

        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        let panel = OverlayPanelFactory.makePanel(frame: frame)

        let waveform = WaveformView()
        let container = WaveformContainer(waveformView: waveform)
        let hostingView = NSHostingView(rootView: container)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        panel.contentView = hostingView

        self.window = panel
        self.waveformView = waveform
        self.hostingView = hostingView
        return true
    }
}

enum OverlayPanelFactory {
    static func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

struct WaveformContainer: View {
    @ObservedObject var waveformView: WaveformView

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)

            if waveformView.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                WaveformShape(levels: waveformView.levels)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
            }
        }
    }
}

struct WaveformShape: Shape {
    let levels: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard levels.count > 1 else {
            // Draw flat line if no data
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return path
        }

        let stepX = rect.width / CGFloat(levels.count - 1)
        let midY = rect.midY
        let maxAmplitude = rect.height / 2 - 4

        for (index, level) in levels.enumerated() {
            let x = CGFloat(index) * stepX
            let normalizedLevel = min(CGFloat(level) * 10, 1.0) // Scale up quiet audio
            let y = midY - normalizedLevel * maxAmplitude

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}
