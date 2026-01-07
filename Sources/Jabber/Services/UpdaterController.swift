import Foundation
import Sparkle
import os

@MainActor
final class UpdaterController: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "UpdaterController")

    @Published var canCheckForUpdates = false

    private var isValidBundle: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.infoDictionary?["CFBundleVersion"] != nil
    }

    init() {
        guard isValidBundle else {
            logger.info("Skipping updater init — not running from a valid app bundle")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }
}
