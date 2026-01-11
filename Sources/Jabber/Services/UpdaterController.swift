import Combine
import Foundation
import Sparkle
import os

@MainActor
final class UpdaterController: ObservableObject {
    private var updaterController: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "UpdaterController")
    private var cancellables = Set<AnyCancellable>()
    private var didScheduleLaunchCheck = false

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false

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

        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] value in
                guard let self else { return }
                if self.automaticallyChecksForUpdates != value {
                    self.automaticallyChecksForUpdates = value
                }
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdatesOnLaunchIfNeeded() {
        guard !didScheduleLaunchCheck else { return }
        guard automaticallyChecksForUpdates else { return }
        didScheduleLaunchCheck = true
        guard let updater = updaterController?.updater else { return }
        if updater.canCheckForUpdates {
            updater.checkForUpdatesInBackground()
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                self?.updaterController?.updater.checkForUpdatesInBackground()
            }
            .store(in: &cancellables)
    }

    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }
}
