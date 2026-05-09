import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    var statusItem: NSStatusItem!
    var popover: NSPopover!

    // Initialized at declaration time so they are available before
    // applicationDidFinishLaunching runs (SwiftUI evaluates App.body,
    // including the Settings scene, before that lifecycle method fires).
    let preferences = Preferences()
    lazy var windowStateManager = WindowStateManager(preferences: preferences)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        setupPopover()
        checkAccessibilityPermission()

        if preferences.isEnabled {
            windowStateManager.start()
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "TerminalDimmer") {
            button.image = image.withSymbolConfiguration(config)
        } else {
            // Fallback if SF Symbol is unavailable on older macOS
            button.title = "TD"
        }

        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 360)
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuBarView(
            preferences: preferences,
            windowStateManager: windowStateManager
        )
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Popover Toggle

    @objc func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermission() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            // The system prompt has been shown via the options dict above.
            // Log for debugging purposes.
            print("TerminalDimmer: Accessibility permission not yet granted.")
        }
    }
}
