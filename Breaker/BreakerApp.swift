import SwiftUI

@main
struct BreakerApp: App {
    @StateObject private var timerManager = TimerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerManager: timerManager)
                .frame(width: 280)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timerManager.menuBarIcon)
                Text(timerManager.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timerManager: timerManager)
        }
    }
}
