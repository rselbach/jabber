import AppKit
import SwiftUI
import os

@MainActor
class OverlayWindowController {
    var window: NSPanel?
    var visibilityToken: UInt64 = 0
    let animationDuration: TimeInterval

    init(animationDuration: TimeInterval) {
        self.animationDuration = animationDuration
    }

    func show() {
        if window == nil {
            guard createWindow() else {
                onWindowCreationFailed()
                return
            }
        }
        // Recompute the frame against the current screen on every show. The
        // panel is created once and cached; without repositioning, unplugging
        // the display it was created on (or a resolution change) strands it
        // offscreen and every future dictation shows an invisible overlay.
        reposition()
        visibilityToken &+= 1
        window?.alphaValue = 1
        onShow()
        window?.orderFront(nil)
    }

    func hide() {
        visibilityToken &+= 1
        let token = visibilityToken

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            window?.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                guard token == self.visibilityToken else {
                    window.alphaValue = 1
                    return
                }
                window.orderOut(nil)
                window.alphaValue = 1
            }
        }
    }

    @discardableResult
    func createWindow() -> Bool {
        false
    }

    /// Recompute and apply the window frame against the current screen. Default
    /// no-op; subclasses with screen-relative geometry override this. Called on
    /// every `show()` so a cached panel follows the user's current display.
    func reposition() {}

    func onShow() {}
    func onWindowCreationFailed() {}
}

@MainActor
class OverlayWindow: OverlayWindowController {
    var waveformView: WaveformView?
    private var hostingView: NSHostingView<WaveformContainer>?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "OverlayWindow")

    /// When `hide()` is called while a fallback notice is on screen, the hide
    /// is deferred until the notice auto-clears so the user has time to read it.
    private var pendingHide = false

    init() {
        super.init(animationDuration: 0.2)
    }

    override func onShow() {
        // A new session abandons any deferred hide carried over from the
        // previous session's fallback-notice window. Without this, a stale
        // pendingHide from session A would fire when session B's own
        // fallback notice auto-clears (session B is still active), hiding
        // the overlay mid-transcription.
        pendingHide = false
        waveformView?.reset()
    }

    override func onWindowCreationFailed() {
        logger.error("Failed to create overlay window - no screen available")
    }

    func updateLevel(_ level: Float) {
        waveformView?.addLevel(level)
    }

    func updatePartialTranscription(_ text: String) {
        waveformView?.updatePartialTranscription(text)
    }

    func showProcessing() {
        waveformView?.showProcessing()
    }

    func showRefining() {
        waveformView?.showRefining()
    }

    /// Shows a brief, non-disruptive red notice on the overlay when
    /// post-processing fell back to the raw transcript. The overlay is already
    /// on screen (we are mid-transcription/refining), so this only updates the
    /// waveform view; it does not reset existing state.
    func showFallbackNotice(_ text: String) {
        waveformView?.showFallbackNotice(text)
    }

    override func hide() {
        // Defer the hide while a fallback notice is visible so it can be read;
        // the notice's auto-clear reissues the hide via the cleared callback.
        if waveformView?.hasActiveFallbackNotice == true {
            pendingHide = true
            return
        }
        pendingHide = false
        super.hide()
    }

    func fallbackNoticeCleared() {
        guard pendingHide else { return }
        pendingHide = false
        super.hide()
    }

    func setTargetAppIcon(_ icon: NSImage?) {
        waveformView?.setTargetAppIcon(icon)
    }

    @discardableResult
    override func createWindow() -> Bool {
        guard let frame = frameForCurrentScreen() else { return false }

        let panel = OverlayPanelFactory.makePanel(frame: frame)

        let waveform = WaveformView()
        waveform.onFallbackNoticeCleared = { [weak self] in
            self?.fallbackNoticeCleared()
        }
        let container = WaveformContainer(waveformView: waveform)
        let hostingView = NSHostingView(rootView: container)
        hostingView.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)

        panel.contentView = hostingView

        window = panel
        waveformView = waveform
        self.hostingView = hostingView
        return true
    }

    override func reposition() {
        guard let frame = frameForCurrentScreen() else { return }
        window?.setFrame(frame, display: true)
    }

    /// Bottom-center overlay frame for the current screen. Overridable so tests
    /// can inject a deterministic frame (NSScreen cannot be fabricated).
    func frameForCurrentScreen() -> NSRect? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let screenFrame = screen.visibleFrame

        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 104
        let bottomMargin: CGFloat = 100

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + bottomMargin

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }
}

enum OverlayPanelFactory {
    @MainActor
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

            HStack(spacing: 10) {
                if let icon = waveformView.targetAppIcon {
                    targetAppIconView(icon)
                        .padding(.leading, 10)
                }

                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let notice = waveformView.fallbackNotice {
            fallbackNoticeView(notice)
        } else if waveformView.isProcessing {
            processingContent
        } else if waveformView.partialTranscription.isEmpty {
            waveform
        } else {
            previewContent
        }
    }

    /// Brief, non-disruptive red indicator shown when post-processing fell
    /// back to the raw transcript. Auto-clears (no click-to-dismiss UI).
    private func fallbackNoticeView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func targetAppIconView(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var waveform: some View {
        WaveformShape(levels: waveformView.levels)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(waveformView.partialTranscription)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            WaveformShape(levels: waveformView.levels)
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(height: 24)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var processingContent: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(waveformView.processingLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !waveformView.partialTranscription.isEmpty {
                Text(waveformView.partialTranscription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
