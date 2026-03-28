import SwiftUI

@main
struct BreakerApp: App {
    @StateObject private var timerManager = TimerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerManager: timerManager)
                .frame(width: 280)
        } label: {
            Label(timerManager.menuBarText, systemImage: "eye")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timerManager: timerManager)
        }
    }
}
