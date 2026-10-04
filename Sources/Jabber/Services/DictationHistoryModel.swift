import Foundation
import Observation

/// History as the app shows it: entries newest first, reloaded whenever the
/// store announces a change. Shared by the History page and the menu bar so
/// both read one list without waiting on the disk.
@MainActor
@Observable
final class DictationHistoryModel {
    static let shared = DictationHistoryModel()

    private(set) var entries: [DictationHistoryEntry] = []

    @ObservationIgnored private let store = DictationHistoryStore.shared
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?

    private init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.dictationHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        reload()
    }

    func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        Task {
            let entries = await store.entries()
            // A later reload may have finished first; keep the newest result.
            guard generation == reloadGeneration else { return }
            self.entries = entries
        }
    }

    func delete(_ entry: DictationHistoryEntry) async throws {
        try await store.delete(id: entry.id)
    }

    func deleteAll() async throws {
        try await store.deleteAll()
    }

    func applyRetention(_ retention: HistoryRetention) async throws {
        try await store.applyRetention(retention)
    }

    func audioURL(for entry: DictationHistoryEntry) -> URL? {
        store.audioURL(for: entry)
    }
}
