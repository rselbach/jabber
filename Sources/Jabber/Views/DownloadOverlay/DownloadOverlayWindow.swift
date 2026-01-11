import AppKit
import SwiftUI
import os

@MainActor
final class DownloadOverlayWindow {
    private var window: NSPanel?
    private let viewModel = DownloadOverlayViewModel()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "DownloadOverlayWindow")

    func show() {
        if window == nil {
            guard createWindow() else {
                logger.error("Failed to create download overlay window - no screen available")
                return
            }
        }
        window?.orderFront(nil)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window?.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
                self?.window?.alphaValue = 1
            }
        }
    }

    func updateProgress(_ progress: Double, status: String, indeterminate: Bool = false) {
        viewModel.progress = progress
        viewModel.status = status
        viewModel.isIndeterminate = indeterminate
    }

    @discardableResult
    private func createWindow() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let screenFrame = screen.visibleFrame

        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 80

        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2

        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        let panel = OverlayPanelFactory.makePanel(frame: frame)

        let content = DownloadOverlayContent(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        panel.contentView = hostingView
        self.window = panel
        return true
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
