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

    /// Bottom-center overlay frame matching the recording overlay's position,
    /// so both panels share one visual language (the two are never shown at
    /// the same time). Overridable so tests can inject a deterministic frame
    /// (NSScreen cannot be fabricated).
    func frameForCurrentScreen() -> NSRect? {
        guard let screenFrame = OverlayScreenResolver.currentVisibleFrame() else { return nil }

        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = 72
        let bottomMargin: CGFloat = 100

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + bottomMargin

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
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)

            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if viewModel.isIndeterminate {
                        ProgressView()
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}
