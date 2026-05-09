import AppKit
import ApplicationServices

final class AccessibilityHelper {

    // MARK: - Permission Checks

    /// Returns true if the app currently has accessibility (AX) permission granted.
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompts the user to grant accessibility permission by opening the
    /// Privacy & Security > Accessibility pane in System Settings (macOS 13+)
    /// or System Preferences (earlier macOS).
    static func requestAccessibilityPermission() {
        // Passing the prompt option causes macOS to show the permission dialog
        // the first time and then opens System Settings on subsequent calls.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)

        // Additionally open the correct pane so the user can enable the toggle.
        openAccessibilityPreferencesPane()
    }

    // MARK: - Focused Window

    /// Returns the PID of the process that owns the currently focused window,
    /// or nil if it cannot be determined.
    ///
    /// This uses the AXUIElement API to query the system-wide accessibility
    /// element for the frontmost application, then reads the focused window.
    static func getFocusedWindowPID() -> pid_t? {
        guard checkAccessibilityPermission() else { return nil }

        // The system-wide AX element lets us reach any app.
        let systemElement = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        guard appResult == .success, let focusedApp = focusedAppRef else {
            return nil
        }

        // Cast to AXUIElement and retrieve the PID.
        let focusedAppElement = focusedApp as! AXUIElement // swiftlint:disable:this force_cast
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(focusedAppElement, &pid)

        guard pidResult == .success, pid > 0 else { return nil }

        // Optionally verify the element actually has a focused window.
        var focusedWindowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            focusedAppElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )

        guard windowResult == .success, focusedWindowRef != nil else { return nil }

        return pid
    }

    // MARK: - Private Helpers

    /// Opens the Accessibility section in System Settings / System Preferences.
    private static func openAccessibilityPreferencesPane() {
        // macOS 13+ uses System Settings with a new URL scheme.
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Pre-macOS 13 uses the older URL scheme.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
