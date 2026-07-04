import SwiftUI

@main
struct JabberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The app has no SwiftUI-managed windows: the menu bar item, the main
        // window, and the onboarding window are all AppDelegate-managed. This
        // empty Settings scene only satisfies the Scene requirement; its menu
        // item is replaced below so Cmd-, opens the real main window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    // Cmd-, lands on General, matching the status-menu
                    // "Settings…" item (openSettings). The section-carrying
                    // notification is observed by AppDelegate (which shows the
                    // window) and MainWindowView (which sets the sidebar
                    // selection when the window is already open).
                    NotificationCenter.default.post(
                        name: Constants.Notifications.mainWindowSectionDidRequest,
                        object: MainWindowView.Section.general
                    )
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
