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
                    NotificationCenter.default.post(
                        name: Constants.Notifications.mainWindowDidRequest,
                        object: nil
                    )
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
