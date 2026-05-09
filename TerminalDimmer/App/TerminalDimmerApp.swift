import SwiftUI

@main
struct TerminalDimmerApp: App {

    // Wire AppDelegate into the SwiftUI lifecycle.
    // AppDelegate owns the status item and popover, so SwiftUI's
    // default window management is suppressed below.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A hidden Settings scene gives us a canonical place to hang
        // keyboard-accessible preferences if needed in the future.
        // The empty WindowGroup is intentionally absent — the entire
        // UI lives in the menu bar popover managed by AppDelegate.
        Settings {
            MenuBarView(
                preferences: appDelegate.preferences,
                windowStateManager: appDelegate.windowStateManager
            )
            .frame(width: 320, height: 400)
        }
    }
}
