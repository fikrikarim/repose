import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var timerManager: TimerManager
    @AppStorage("workDurationMinutes") private var workDurationMinutes: Int = 20
    @AppStorage("breakDurationSeconds") private var breakDurationSeconds: Int = 20
    @AppStorage("smartPauseEnabled") private var smartPauseEnabled: Bool = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Timer") {
                Stepper(
                    "Work interval: \(workDurationMinutes) min",
                    value: $workDurationMinutes,
                    in: 1...120
                )

                Stepper(
                    "Break duration: \(breakDurationSeconds) sec",
                    value: $breakDurationSeconds,
                    in: 5...300,
                    step: 5
                )
            }

            Section("Smart Pause") {
                Toggle("Pause during meetings", isOn: $smartPauseEnabled)

                if smartPauseEnabled {
                    Text("Automatically pauses when your camera or microphone is in use (e.g., during video calls).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLogin = newValue
                        } catch {
                            // revert on failure
                        }
                    }
                ))
            }

            Section {
                HStack {
                    Spacer()
                    Text("Breaker v1.0")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 320)
    }
}
