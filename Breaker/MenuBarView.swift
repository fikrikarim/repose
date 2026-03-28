import SwiftUI

struct MenuBarView: View {
    @ObservedObject var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 12) {
            // Status
            HStack {
                Image(systemName: stateIcon)
                    .foregroundColor(stateColor)
                Text(stateLabel)
                    .font(.headline)
                Spacer()
            }

            // Countdown or status description
            Text(timerManager.statusDescription)
                .font(.system(.title2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            // Smart pause indicator
            if timerManager.smartPauseEnabled && timerManager.meetingDetector.isInMeeting {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(timerManager.meetingDetector.meetingSource ?? "Meeting detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // Controls
            HStack {
                Button(timerManager.state == .paused ? "Resume" : "Pause") {
                    timerManager.togglePause()
                }
                .disabled(timerManager.state == .onBreak || timerManager.state == .idle ||
                          (timerManager.state == .paused && timerManager.meetingDetector.isInMeeting))

                Button("Restart") {
                    timerManager.start()
                }

                Spacer()

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Text("Settings")
                    }
                } else {
                    Button("Settings") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
            }

            Divider()

            Button("Quit Breaker") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
    }

    private var stateIcon: String {
        switch timerManager.state {
        case .idle: return "eye"
        case .working: return "timer"
        case .onBreak: return "eye.trianglebadge.exclamationmark"
        case .paused: return "pause.circle"
        }
    }

    private var stateColor: Color {
        switch timerManager.state {
        case .idle: return .secondary
        case .working: return .green
        case .onBreak: return .orange
        case .paused: return .yellow
        }
    }

    private var stateLabel: String {
        switch timerManager.state {
        case .idle: return "Ready"
        case .working: return "Working"
        case .onBreak: return "Break Time"
        case .paused: return "Paused"
        }
    }
}
