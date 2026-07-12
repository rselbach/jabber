import AppKit
import SwiftUI
import os

@MainActor
class OverlayWindowController {
    var window: NSPanel?
    var visibilityToken: UInt64 = 0
    let animationDuration: TimeInterval
    private var isHiding = false

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
        guard window?.isVisible != true || isHiding || shouldShowWhenAlreadyVisible() else { return }
        // Recompute the frame against the current screen on every show. The
        // panel is created once and cached; without repositioning, unplugging
        // the display it was created on (or a resolution change) strands it
        // offscreen and every future dictation shows an invisible overlay.
        reposition()
        visibilityToken &+= 1
        isHiding = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window?.animator().alphaValue = 1
        }
        onShow()
        window?.orderFront(nil)
    }

    func hide() {
        // A hide during an in-flight hide must not bump the token: the first
        // hide's completion would read the mismatch as "a show superseded me"
        // and restore alpha on a still-ordered-in window (visible flash), and
        // its isHiding reset lets a following show() early-return while the
        // second completion orders the window out — swallowing the show. The
        // in-flight hide already finishes the job; only show() interrupts.
        guard !isHiding else { return }
        visibilityToken &+= 1
        let token = visibilityToken
        isHiding = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            window?.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                guard token == self.visibilityToken else {
                    window.alphaValue = 1
                    self.isHiding = false
                    return
                }
                window.orderOut(nil)
                window.alphaValue = 1
                self.isHiding = false
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

    func shouldShowWhenAlreadyVisible() -> Bool {
        false
    }

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

    override func shouldShowWhenAlreadyVisible() -> Bool {
        pendingHide
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
        guard let screenFrame = OverlayScreenResolver.currentVisibleFrame() else { return nil }

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
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

enum OverlayScreenResolver {
    static func screenFrame(containing point: NSPoint, screenFrames: [NSRect]) -> Int? {
        screenFrames.firstIndex { $0.contains(point) }
    }

    @MainActor
    static func currentVisibleFrame(
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSRect? {
        let visibleFrames = screens.map(\.visibleFrame)
        if let index = screenFrame(containing: mouseLocation, screenFrames: visibleFrames) {
            return visibleFrames[index]
        }

        return NSScreen.main?.visibleFrame ?? visibleFrames.first
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
        WaveformBarsView(levels: waveformView.levels)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(waveformView.partialTranscription)
                .font(.callout)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            WaveformBarsView(levels: waveformView.levels)
                .frame(height: 24)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var processingContent: some View {
        VStack(spacing: 8) {
            ProcessingWaveformView()
                .frame(height: 16)

            Text(waveformView.processingLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

/// Voice-memo style level meter: one rounded bar per sample, symmetric around
/// the centerline, newest sample at the right. Short histories are left-padded
/// with silence so the meter is always full-width and idles as a row of dots.
/// Height changes ease out so motion stays smooth at audio-buffer cadence.
struct WaveformBarsView: View {
    let levels: [Float]

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3
    private let minBarHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let bars = displayLevels(width: geometry.size.width)
            HStack(spacing: spacing) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: barWidth, height: barHeight(for: bars[index], available: geometry.size.height))
                }
            }
            .shadow(color: Color.accentColor.opacity(0.35), radius: 1.5)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.easeOut(duration: 0.1), value: levels)
    }

    private func displayLevels(width: CGFloat) -> [Float] {
        let capacity = max(1, Int((width + spacing) / (barWidth + spacing)))
        let recent = levels.suffix(capacity)
        return Array(repeating: 0, count: capacity - recent.count) + recent
    }

    private func barHeight(for level: Float, available: CGFloat) -> CGFloat {
        let normalized = min(CGFloat(level) * 10, 1.0) // Scale up quiet audio
        return minBarHeight + normalized * max(available - minBarHeight, 0)
    }
}

/// The waveform flattened to its idle dots with a repeating highlight sweep,
/// shown while transcription or refinement runs. Keeps the overlay surface
/// continuous from recording to processing instead of swapping in a spinner.
/// The sweep is skipped when the user has Reduce Motion enabled.
struct ProcessingWaveformView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        WaveformBarsView(levels: [])
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        let bandWidth = geometry.size.width * 0.35
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.9), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth)
                        .offset(x: sweep ? geometry.size.width : -bandWidth)
                    }
                    .mask(WaveformBarsView(levels: []))
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}
