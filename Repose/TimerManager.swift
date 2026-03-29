import Foundation
import Combine
import AppKit

enum TimerState {
    case working
    case onBreak
    case paused
}

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .working
    @Published var remainingSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private var tickCount: Int = 0
    private var secondsBeforePause: Int = 0
    private var pausedByMeeting = false

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

    var menuBarText: String {
        switch state {
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

        // Reset work timer on wake — sleep time isn't work time
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    private func handleWake() {
        switch state {
        case .working:
            remainingSeconds = workDurationSeconds
        case .onBreak:
            overlayManager.dismissOverlay()
            remainingSeconds = workDurationSeconds
            state = .working
        case .paused:
            break
        }
    }

    func start() {
        remainingSeconds = workDurationSeconds
        state = .working
        startTicking()
    }

    func pause() {
        guard state == .working else { return }
        secondsBeforePause = remainingSeconds
        state = .paused
        pausedByMeeting = false
    }

    func resume() {
        guard state == .paused else { return }
        remainingSeconds = secondsBeforePause
        state = .working
        pausedByMeeting = false
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
        case .paused:
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
        // Check for meeting immediately before showing break overlay
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                secondsBeforePause = workDurationSeconds
                state = .paused
                pausedByMeeting = true
                return
            }
        }

        remainingSeconds = breakDurationSeconds
        state = .onBreak
        overlayManager.showBreakOverlay(timerManager: self)
        NSSound(named: "Glass")?.play()
    }

    private func endBreak() {
        NSSound(named: "Blow")?.play()
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
                pausedByMeeting = true
            } else if state == .onBreak {
                // If a meeting starts during a break, skip the break
                skipBreak()
                secondsBeforePause = remainingSeconds
                state = .paused
                pausedByMeeting = true
            }
        } else {
            if state == .paused && pausedByMeeting {
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
