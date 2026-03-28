import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var timerManager: TimerManager
    let isPrimary: Bool
    @AppStorage("allowSkipBreak") private var allowSkipBreak: Bool = true
    @State private var breathe = false
    @State private var appeared = false
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        ZStack {
            // Blurred dark background — semi-transparent
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            if isPrimary {
                // Ambient glow behind the content
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.3, green: 0.4, blue: 0.9).opacity(0.15),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 350
                        )
                    )
                    .frame(width: 700, height: 700)
                    .scaleEffect(breathe ? 1.1 : 0.9)
                    .blur(radius: 60)

                VStack(spacing: 40) {
                    Spacer()

                    // Progress ring with breathing animation
                    ZStack {
                        // Outer breathing ring
                        Circle()
                            .stroke(.white.opacity(0.06), lineWidth: 2)
                            .frame(width: 180, height: 180)
                            .scaleEffect(breathe ? 1.12 : 0.92)

                        // Progress ring
                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.8),
                                        Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.6),
                                        Color(red: 0.4, green: 0.5, blue: 1.0).opacity(0.3),
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(-90))

                        // Inner circle
                        Circle()
                            .fill(.white.opacity(0.04))
                            .frame(width: 130, height: 130)
                            .scaleEffect(breathe ? 1.05 : 0.97)

                        // Timer inside the ring
                        Text(formatTime(timerManager.remainingSeconds))
                            .font(.system(size: 38, weight: .light, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .contentTransition(.numericText())
                    }

                    VStack(spacing: 10) {
                        Text("Take a Break")
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text("Look away from the screen and rest your eyes")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                    }

                    // Skip button
                    if allowSkipBreak {
                        Button(action: { timerManager.skipBreak() }) {
                            Text("Skip")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(appeared ? 1 : 0)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
            updateRingProgress()
        }
        .onChange(of: timerManager.remainingSeconds) { _ in
            updateRingProgress()
        }
    }

    private func updateRingProgress() {
        let total = CGFloat(timerManager.breakDurationSeconds)
        let remaining = CGFloat(timerManager.remainingSeconds)
        let progress = total > 0 ? (total - remaining) / total : 0
        withAnimation(.linear(duration: 1)) {
            ringProgress = progress
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
