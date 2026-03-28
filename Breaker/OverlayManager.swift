import AppKit
import SwiftUI

@MainActor
class OverlayManager {
    private var overlayWindows: [NSPanel] = []

    func showBreakOverlay(timerManager: TimerManager) {
        dismissOverlay()

        for screen in NSScreen.screens {
            let isPrimary = screen == NSScreen.main
            let view = BreakOverlayView(timerManager: timerManager, isPrimary: isPrimary)

            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: view)
            panel.orderFrontRegardless()
            overlayWindows.append(panel)
        }
    }

    func dismissOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}
