import AppKit
import SwiftUI
import os

@MainActor
final class DownloadOverlayWindow: OverlayWindowController {
    private let viewModel = DownloadOverlayViewModel()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DownloadOverlayWindow")

    init() {
        super.init(animationDuration: 0.3)
    }

    override func onWindowCreationFailed() {
        logger.error("Failed to create download overlay window - no screen available")
    }

    func updateProgress(_ progress: Double, status: String, indeterminate: Bool = false) {
        viewModel.progress = progress
        viewModel.status = status
        viewModel.isIndeterminate = indeterminate
    }

    @discardableResult
    override func createWindow() -> Bool {
        guard let frame = frameForCurrentScreen() else { return false }

        let panel = OverlayPanelFactory.makePanel(frame: frame)

        let content = DownloadOverlayContent(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)

        panel.contentView = hostingView
        window = panel
        return true
    }

    override func reposition() {
        guard let frame = frameForCurrentScreen() else { return }
        window?.setFrame(frame, display: true)
    }

    /// Centered overlay frame for the current screen. Overridable so tests can
    /// inject a deterministic frame (NSScreen cannot be fabricated).
    func frameForCurrentScreen() -> NSRect? {
        guard let screenFrame = OverlayScreenResolver.currentVisibleFrame() else { return nil }

        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 80

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2

        return NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
    }
}

@MainActor
final class DownloadOverlayViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var status: String = "Preparing..."
    @Published var isIndeterminate: Bool = false
}

struct DownloadOverlayContent: View {
    @ObservedObject var viewModel: DownloadOverlayViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                Text("Jabber")
                    .font(.headline)
            }

            VStack(spacing: 6) {
                if viewModel.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                }

                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
