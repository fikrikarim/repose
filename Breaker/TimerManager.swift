import Foundation
import Combine
import AppKit

enum TimerState {
    case idle
    case working
    case onBreak
    case paused
}

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .idle
    @Published var remainingSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private var tickCount: Int = 0
    private var secondsBeforePause: Int = 0

    let meetingDetector = MeetingDetector()
    let overlayManager = OverlayManager()

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    var workDurationSeconds: Int {
        UserDefaults.standard.integer(forKey: "workDurationMinutes").clamped(to: 1...120) * 60
    }

    var breakDurationSeconds: Int {
        let val = UserDefaults.standard.integer(forKey: "breakDurationSeconds")
        return val.clamped(to: 5...300)
    }

    var pauseDuringMeetings: Bool {
        UserDefaults.standard.bool(forKey: "pauseDuringMeetings")
    }

    var menuBarIcon: String {
        switch state {
        case .idle: return "eye"
        case .working: return "timer"
        case .onBreak: return "eye"
        case .paused:
            return meetingDetector.isInMeeting ? "video.fill" : "pause.circle"
        }
    }

    var menuBarText: String {
        switch state {
        case .idle:
            return "Breaker"
        case .working:
            return formatTime(remainingSeconds)
        case .onBreak:
            return "Break \(formatTime(remainingSeconds))"
        case .paused:
            if meetingDetector.isInMeeting {
                return "Meeting \(formatTime(secondsBeforePause))"
            }
            return "Paused \(formatTime(secondsBeforePause))"
        }
    }

    var statusDescription: String {
        switch state {
        case .idle:
            return "Click Start to begin"
        case .working:
            return "Next break in \(formatTime(remainingSeconds))"
        case .onBreak:
            return "Take a break! \(formatTime(remainingSeconds))"
        case .paused:
            if let source = meetingDetector.meetingSource {
                return "Paused: \(source)"
            }
            return "Timer paused"
        }
    }

    init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "workDurationMinutes": 20,
            "breakDurationSeconds": 20,
            "pauseDuringMeetings": true,
            "allowSkipBreak": true,
        ])
        // Start timer immediately on launch
        start()
    }

    func start() {
        remainingSeconds = workDurationSeconds
        state = .working
        startTicking()
    }

    func stop() {
        state = .idle
        remainingSeconds = 0
        stopTicking()
        overlayManager.dismissOverlay()
    }

    func pause() {
        guard state == .working else { return }
        secondsBeforePause = remainingSeconds
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        remainingSeconds = secondsBeforePause
        state = .working
    }

    func skipBreak() {
        overlayManager.dismissOverlay()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    func togglePause() {
        if state == .working {
            pause()
        } else if state == .paused && !meetingDetector.isInMeeting {
            resume()
        }
    }

    // MARK: - Private

    private func startTicking() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Break timer running"
        )

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicking() {
        timerCancellable?.cancel()
        timerCancellable = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        tickCount += 1

        // Check for meetings every 10 seconds
        if pauseDuringMeetings && tickCount % 10 == 0 {
            checkMeetingStatus()
        }

        switch state {
        case .idle, .paused:
            break

        case .working:
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                startBreak()
            }

        case .onBreak:
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                endBreak()
            }
        }
    }

    private func startBreak() {
        remainingSeconds = breakDurationSeconds
        state = .onBreak
        overlayManager.showBreakOverlay(timerManager: self)
    }

    private func endBreak() {
        overlayManager.dismissOverlay()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    private func checkMeetingStatus() {
        meetingDetector.check()

        if meetingDetector.isInMeeting {
            if state == .working {
                secondsBeforePause = remainingSeconds
                state = .paused
            } else if state == .onBreak {
                // If a meeting starts during a break, skip the break
                skipBreak()
                secondsBeforePause = remainingSeconds
                state = .paused
            }
        } else {
            if state == .paused && meetingDetector.meetingSource == nil {
                // Meeting ended, resume
                resume()
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        if self == 0 { return range.lowerBound }
        return self
    }
}
