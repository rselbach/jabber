import AppKit

/// The app a transcript was typed or pasted into, as recorded in history.
struct DictatedApp: Equatable, Sendable {
    let name: String
    let bundleID: String?

    /// `nil` when the process is gone or has no name.
    @MainActor
    init?(processID: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: processID),
              let name = app.localizedName else {
            return nil
        }
        self.name = name
        bundleID = app.bundleIdentifier
    }

    init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}
