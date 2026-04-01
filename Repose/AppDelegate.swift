import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timerManager: TimerManager!
    private var updaterController: SPUStandardUpdaterController!
    private var statusBarTimer: Timer?
    private var menuIsOpen = false

    // Menu items that need updating
    private var statusMenuItem: NSMenuItem!
    private var pauseResumeMenuItem: NSMenuItem!
    private var workIntervalMenu: NSMenu!
    private var breakDurationMenu: NSMenu!
    private var pauseDuringMeetingsMenuItem: NSMenuItem!
    private var allowSkipMenuItem: NSMenuItem!
    private var pauseWhenIdleMenuItem: NSMenuItem!
    private var muteSoundsMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!

    #if DEBUG
    private let workIntervalOptions = [1, 5, 10, 15, 20, 25, 30, 45, 60, 90]
    private let breakDurationOptions = [10, 20, 30, 60, 120, 300, 600]
    #else
    private let workIntervalOptions = [5, 10, 15, 20, 25, 30, 45, 60, 90]
    private let breakDurationOptions = [20, 30, 60, 120, 300, 600]
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        timerManager = TimerManager()
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Repose")
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
        pauseDuringMeetingsMenuItem = NSMenuItem(title: "Pause During Meetings", action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        pauseDuringMeetingsMenuItem.target = self
        pauseDuringMeetingsMenuItem.representedObject = SettingsKey.pauseDuringMeetings
        menu.addItem(pauseDuringMeetingsMenuItem)

        pauseWhenIdleMenuItem = NSMenuItem(title: "Pause When Idle", action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        pauseWhenIdleMenuItem.target = self
        pauseWhenIdleMenuItem.representedObject = SettingsKey.pauseWhenIdle
        menu.addItem(pauseWhenIdleMenuItem)

        allowSkipMenuItem = NSMenuItem(title: "Allow Skip Break", action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        allowSkipMenuItem.target = self
        allowSkipMenuItem.representedObject = SettingsKey.allowSkipBreak
        menu.addItem(allowSkipMenuItem)

        muteSoundsMenuItem = NSMenuItem(title: "Mute Sounds", action: #selector(toggleBoolSetting(_:)), keyEquivalent: "")
        muteSoundsMenuItem.target = self
        muteSoundsMenuItem.representedObject = SettingsKey.muteSounds
        menu.addItem(muteSoundsMenuItem)

        menu.addItem(.separator())

        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Repose", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Repose", action: #selector(quitApp), keyEquivalent: "q")
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
        case .working:
            statusMenuItem.title = "Next break in \(formatTime(timerManager.remainingSeconds))"
        case .onBreak:
            statusMenuItem.title = "On a break"
        case .paused:
            statusMenuItem.title = timerManager.pauseStatusText ?? "Paused"
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
            pauseResumeMenuItem.isEnabled = timerManager.currentPauseReason != .meeting
            pauseResumeMenuItem.isHidden = false
        default:
            pauseResumeMenuItem.isHidden = true
        }

        // Work interval checkmarks
        let currentWork = UserDefaults.standard.integer(forKey: SettingsKey.workDurationMinutes)
        for item in workIntervalMenu.items {
            item.state = item.tag == currentWork ? .on : .off
        }

        // Break duration checkmarks
        let currentBreak = UserDefaults.standard.integer(forKey: SettingsKey.breakDurationSeconds)
        for item in breakDurationMenu.items {
            item.state = item.tag == currentBreak ? .on : .off
        }

        // Toggle states
        pauseDuringMeetingsMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.pauseDuringMeetings) ? .on : .off
        pauseWhenIdleMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.pauseWhenIdle) ? .on : .off
        allowSkipMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.allowSkipBreak) ? .on : .off
        muteSoundsMenuItem.state = UserDefaults.standard.bool(forKey: SettingsKey.muteSounds) ? .on : .off
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
        case .working: icon = "timer"
        case .onBreak: icon = "cup.and.saucer.fill"
        case .paused:
            switch timerManager.currentPauseReason {
            case .meeting: icon = "video.fill"
            case .idle: icon = "moon.zzz"
            default: icon = "pause.circle"
            }
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
        UserDefaults.standard.set(sender.tag, forKey: SettingsKey.workDurationMinutes)
        if timerManager.state == .working {
            timerManager.start()
        }
    }

    @objc private func setBreakDuration(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: SettingsKey.breakDurationSeconds)
    }

    @objc private func toggleBoolSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        try? enabled ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "by Fikri Karim\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        ))
        credits.append(NSAttributedString(
            string: "github.com/fikrikarim/repose",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: URL(string: "https://github.com/fikrikarim/repose")!,
            ]
        ))

        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Repose",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            .credits: credits,
        ])
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func formatBreakDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) sec"
        } else {
            return "\(seconds / 60) min"
        }
    }
}
