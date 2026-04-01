import Foundation
import Combine
import AppKit
import CoreGraphics
import IOKit.pwr_mgt

enum TimerState {
    case working
    case onBreak
    case paused
}

enum PauseReason {
    case manual
    case meeting
    case idle
    case breakPending  // Work timer expired during meeting, waiting for meeting to end
}

enum SettingsKey {
    static let workDurationMinutes = "workDurationMinutes"
    static let breakDurationSeconds = "breakDurationSeconds"
    static let pauseDuringMeetings = "pauseDuringMeetings"
    static let allowSkipBreak = "allowSkipBreak"
    static let muteSounds = "muteSounds"
    static let pauseWhenIdle = "pauseWhenIdle"
}

@MainActor
class TimerManager: ObservableObject {
    @Published var state: TimerState = .working
    @Published var remainingSeconds: Int = 0

    private var timerCancellable: AnyCancellable?
    private var tickCount: Int = 0
    private var secondsBeforePause: Int = 0
    private var pauseReason: PauseReason = .manual

    let meetingDetector = MeetingDetector()
    let overlayManager = OverlayManager()
    private let postMeetingBreakDelay = 5

    // Activity to prevent App Nap
    private var activity: NSObjectProtocol?

    var workDurationSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKey.workDurationMinutes).clamped(to: 1...120) * 60
    }

    var breakDurationSeconds: Int {
        let val = UserDefaults.standard.integer(forKey: SettingsKey.breakDurationSeconds)
        return val.clamped(to: 5...300)
    }

    var pauseDuringMeetings: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseDuringMeetings)
    }

    var muteSounds: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.muteSounds)
    }

    var pauseWhenIdle: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseWhenIdle)
    }

    var menuBarText: String {
        switch state {
        case .working:
            return formatTime(remainingSeconds)
        case .onBreak:
            return "Break \(formatTime(remainingSeconds))"
        case .paused:
            switch pauseReason {
            case .meeting:
                return "Meeting \(formatTime(secondsBeforePause))"
            case .breakPending:
                return "Meeting"
            case .idle:
                return "Idle"
            case .manual:
                return "Paused \(formatTime(secondsBeforePause))"
            }
        }
    }

    var pauseStatusText: String? {
        guard state == .paused else { return nil }
        switch pauseReason {
        case .meeting:
            return meetingDetector.meetingSource.map { "Paused — \($0)" } ?? "Paused — Meeting"
        case .breakPending:
            return meetingDetector.meetingSource.map { "\($0) — Break pending" } ?? "In meeting — Break pending"
        case .idle:
            return "Paused — Idle"
        case .manual:
            return "Paused"
        }
    }

    var currentPauseReason: PauseReason? {
        state == .paused ? pauseReason : nil
    }

    var isInMeeting: Bool {                                                                                                                             
        meetingDetector.isInMeeting                                                                                                                     
    } 

    init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            SettingsKey.workDurationMinutes: 20,
            SettingsKey.breakDurationSeconds: 20,
            SettingsKey.pauseDuringMeetings: true,
            SettingsKey.allowSkipBreak: true,
            SettingsKey.muteSounds: false,
            SettingsKey.pauseWhenIdle: true,
        ])
        // Start timer and ticker (ticker runs for app lifetime)
        remainingSeconds = workDurationSeconds
        state = .working
        startTicking()

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
    }

    func pause() {
        guard state == .working else { return }
        secondsBeforePause = remainingSeconds
        state = .paused
        pauseReason = .manual
    }

    func resume() {
        guard state == .paused else { return }
        remainingSeconds = secondsBeforePause
        state = .working
        pauseReason = .manual
    }

    func skipBreak() {
        overlayManager.dismissOverlay()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    func togglePause() {
        if state == .working {
            pause()
        } else if state == .paused && pauseReason != .meeting && pauseReason != .breakPending {
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

    private func tick() {
        tickCount += 1

        // Check for meetings and idle every 5 seconds
        if tickCount % 5 == 0 {
            if pauseDuringMeetings { checkMeetingStatus() }
            if pauseWhenIdle { checkIdleStatus() }
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
                secondsBeforePause = 0
                state = .paused
                pauseReason = .breakPending
                return
            }
        }

        remainingSeconds = breakDurationSeconds
        state = .onBreak
        overlayManager.showBreakOverlay(timerManager: self)
        if !muteSounds { NSSound(named: "Glass")?.play() }
    }

    private func endBreak() {
        if !muteSounds { NSSound(named: "Blow")?.play() }
        overlayManager.dismissWithAnimation()
        remainingSeconds = workDurationSeconds
        state = .working
    }

    private func checkMeetingStatus() {
        meetingDetector.check()

        if meetingDetector.isInMeeting {
            // Timer keeps running during meetings when working — no pause
            if state == .onBreak {
                // If a meeting starts during a break, skip the break
                skipBreak()
                secondsBeforePause = remainingSeconds
                state = .paused
                pauseReason = .meeting
            }
        } else {
            if state == .paused && pauseReason == .breakPending {
                // Meeting ended with break pending — short countdown then break
                remainingSeconds = postMeetingBreakDelay
                state = .working
            } else if state == .paused && pauseReason == .meeting {
                // Meeting ended (break was skipped), resume
                resume()
            }
        }
    }

    // MARK: - Idle Detection

    #if DEBUG
    private let idleThreshold: TimeInterval = 30 // 30 seconds for testing
    #else
    private let idleThreshold: TimeInterval = 300 // 5 minutes
    #endif

    private func checkIdleStatus() {
        // kCGAnyInputEventType (~0) checks all input event types
        let idleTime = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if idleTime >= idleThreshold && !hasActiveDisplaySleepAssertion() {
            if state == .working {
                secondsBeforePause = remainingSeconds
                state = .paused
                pauseReason = .idle
            }
        } else {
            if state == .paused && pauseReason == .idle {
                resumeFromIdle()
            }
        }
    }

    private func resumeFromIdle() {
        guard state == .paused && pauseReason == .idle else { return }

        // Check for active meeting before resuming to avoid a gap
        if pauseDuringMeetings {
            meetingDetector.check()
            if meetingDetector.isInMeeting {
                secondsBeforePause = workDurationSeconds
                pauseReason = .meeting
                return
            }
        }

        remainingSeconds = workDurationSeconds
        state = .working
    }

    private func hasActiveDisplaySleepAssertion() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let dict = assertions?.takeRetainedValue() as? [String: [[String: Any]]] else {
            return false
        }

        for (_, processAssertions) in dict {
            for assertion in processAssertions {
                if let type = assertion["AssertType"] as? String,
                   type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleep" {
                    return true
                }
            }
        }
        return false
    }

}

func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
