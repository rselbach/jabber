import SwiftUI

@main
struct JabberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(updaterController: appDelegate.updaterController)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                    if let window = notification.object as? NSWindow,
                       window.title.contains("Settings") || window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
    }
}
