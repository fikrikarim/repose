import AppKit
import ServiceManagement
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timerManager: TimerManager!
    private var statusBarTimer: Timer?
    private var menuIsOpen = false

    // Menu items that need updating
    private var statusMenuItem: NSMenuItem!
    private var pauseResumeMenuItem: NSMenuItem!
    private var workIntervalMenu: NSMenu!
    private var breakDurationMenu: NSMenu!
    private var pauseDuringMeetingsMenuItem: NSMenuItem!
    private var allowSkipMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!

    private let workIntervalOptions = [1, 5, 10, 15, 20, 30, 45, 60]
    private let breakDurationOptions = [10, 20, 30, 60, 120, 300]

    func applicationDidFinishLaunching(_ notification: Notification) {
        timerManager = TimerManager()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Breaker")
        statusItem.button?.imagePosition = .imageLeading

        buildMenu()
        startStatusBarTimer()
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Status line (disabled, just for display)
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Pause / Resume
        pauseResumeMenuItem = NSMenuItem(title: "Pause Timer", action: #selector(togglePause), keyEquivalent: "p")
        pauseResumeMenuItem.target = self
        menu.addItem(pauseResumeMenuItem)

        let restartItem = NSMenuItem(title: "Restart Timer", action: #selector(restartTimer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(.separator())

        // Work Interval submenu
        let workItem = NSMenuItem(title: "Work Interval", action: nil, keyEquivalent: "")
        workIntervalMenu = NSMenu()
        for minutes in workIntervalOptions {
            let item = NSMenuItem(title: "\(minutes) min", action: #selector(setWorkInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            workIntervalMenu.addItem(item)
        }
        workItem.submenu = workIntervalMenu
        menu.addItem(workItem)

        // Break Duration submenu
        let breakItem = NSMenuItem(title: "Break Duration", action: nil, keyEquivalent: "")
        breakDurationMenu = NSMenu()
        for seconds in breakDurationOptions {
            let item = NSMenuItem(title: formatBreakDuration(seconds), action: #selector(setBreakDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            breakDurationMenu.addItem(item)
        }
        breakItem.submenu = breakDurationMenu
        menu.addItem(breakItem)

        menu.addItem(.separator())

        // Toggles
        pauseDuringMeetingsMenuItem = NSMenuItem(title: "Pause During Meetings", action: #selector(togglePauseDuringMeetings), keyEquivalent: "")
        pauseDuringMeetingsMenuItem.target = self
        menu.addItem(pauseDuringMeetingsMenuItem)

        allowSkipMenuItem = NSMenuItem(title: "Allow Skip Break", action: #selector(toggleAllowSkip), keyEquivalent: "")
        allowSkipMenuItem.target = self
        menu.addItem(allowSkipMenuItem)

        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Breaker", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate — update items right before the menu opens

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = true
            updateMenuItems()
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = false
        }
    }

    private func updateStatusText() {
        switch timerManager.state {
        case .idle:
            statusMenuItem.title = "Breaker"
        case .working:
            statusMenuItem.title = "Next break in \(formatTime(timerManager.remainingSeconds))"
        case .onBreak:
            statusMenuItem.title = "On a break"
        case .paused:
            if let source = timerManager.meetingDetector.meetingSource {
                statusMenuItem.title = "Paused — \(source)"
            } else {
                statusMenuItem.title = "Paused"
            }
        }
    }

    private func updateMenuItems() {
        updateStatusText()

        // Pause / Resume
        switch timerManager.state {
        case .working:
            pauseResumeMenuItem.title = "Pause Timer"
            pauseResumeMenuItem.isEnabled = true
            pauseResumeMenuItem.isHidden = false
        case .paused:
            pauseResumeMenuItem.title = "Resume Timer"
            pauseResumeMenuItem.isEnabled = !timerManager.meetingDetector.isInMeeting
            pauseResumeMenuItem.isHidden = false
        default:
            pauseResumeMenuItem.isHidden = true
        }

        // Work interval checkmarks
        let currentWork = UserDefaults.standard.integer(forKey: "workDurationMinutes")
        for item in workIntervalMenu.items {
            item.state = item.tag == currentWork ? .on : .off
        }

        // Break duration checkmarks
        let currentBreak = UserDefaults.standard.integer(forKey: "breakDurationSeconds")
        for item in breakDurationMenu.items {
            item.state = item.tag == currentBreak ? .on : .off
        }

        // Toggle states
        pauseDuringMeetingsMenuItem.state = UserDefaults.standard.bool(forKey: "pauseDuringMeetings") ? .on : .off
        allowSkipMenuItem.state = UserDefaults.standard.bool(forKey: "allowSkipBreak") ? .on : .off
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Status bar title updates

    private func startStatusBarTimer() {
        updateStatusBarTitle()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateStatusBarTitle()
                if self.menuIsOpen {
                    self.updateStatusText()
                }
            }
        }
        // .common includes both default and eventTracking modes,
        // so updates work even while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        statusBarTimer = timer
    }

    private func updateStatusBarTitle() {
        let icon: String
        switch timerManager.state {
        case .idle: icon = "eye"
        case .working: icon = "timer"
        case .onBreak: icon = "cup.and.saucer.fill"
        case .paused:
            icon = timerManager.meetingDetector.isInMeeting ? "video.fill" : "pause.circle"
        }

        statusItem.button?.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        statusItem.button?.title = " \(timerManager.menuBarText)"
    }

    // MARK: - Actions

    @objc private func togglePause() {
        timerManager.togglePause()
    }

    @objc private func restartTimer() {
        timerManager.start()
    }

    @objc private func setWorkInterval(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "workDurationMinutes")
    }

    @objc private func setBreakDuration(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "breakDurationSeconds")
    }

    @objc private func togglePauseDuringMeetings() {
        let current = UserDefaults.standard.bool(forKey: "pauseDuringMeetings")
        UserDefaults.standard.set(!current, forKey: "pauseDuringMeetings")
    }

    @objc private func toggleAllowSkip() {
        let current = UserDefaults.standard.bool(forKey: "allowSkipBreak")
        UserDefaults.standard.set(!current, forKey: "allowSkipBreak")
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        try? enabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatBreakDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) sec"
        } else {
            return "\(seconds / 60) min"
        }
    }
}
