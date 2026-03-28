import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var timerManager: TimerManager
    let isPrimary: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            if isPrimary {
                VStack(spacing: 24) {
                    Image(systemName: "eye")
                        .font(.system(size: 60))
                        .foregroundColor(.white)

                    Text("Look Away")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.white)

                    Text("Rest your eyes by looking at something 20 feet away")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))

                    Text(formatTime(timerManager.remainingSeconds))
                        .font(.system(size: 72, weight: .light, design: .monospaced))
                        .foregroundColor(.white)

                    Button(action: { timerManager.skipBreak() }) {
                        Text("Skip Break")
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
