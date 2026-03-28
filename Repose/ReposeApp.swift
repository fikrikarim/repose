import SwiftUI

@main
struct ReposeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — the app lives entirely in the menu bar.
        // Settings scene is required but unused (settings are in the menu).
        Settings {
            EmptyView()
        }
    }
}
