import AppKit
import CoreGraphics

// MARK: - WindowTracker

final class WindowTracker {

    // MARK: Public Interface

    /// Returns all on-screen windows, excluding desktop elements.
    func getAllWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements
        ]
        return fetchWindows(options: options)
    }

    /// Returns all on-screen windows that belong to any known terminal application.
    func getTerminalWindows() -> [WindowInfo] {
        let allTerminals = Set(BundleIdentifiers.allTerminals)
        return getAllWindows().filter { window in
            allTerminals.contains(window.ownerBundleID)
        }
    }

    /// Returns only windows whose owner application matches one of the provided bundle identifiers.
    func getTerminalWindows(bundleIDs: Set<String>) -> [WindowInfo] {
        getAllWindows().filter { window in
            bundleIDs.contains(window.ownerBundleID)
        }
    }

    // MARK: Private Helpers

    /// Fetches the raw CGWindowList and maps each entry to a `WindowInfo`.
    private func fetchWindows(options: CGWindowListOption) -> [WindowInfo] {
        guard
            let cfArray = CGWindowListCopyWindowInfo(options, kCGNullWindowID),
            let windowList = cfArray as? [[String: Any]]
        else {
            return []
        }

        return windowList.compactMap { dict in
            windowInfo(from: dict)
        }
    }

    /// Parses a single window dictionary into a `WindowInfo`, returning `nil` if any
    /// required field is missing or cannot be converted.
    private func windowInfo(from dict: [String: Any]) -> WindowInfo? {
        guard
            let windowNumber = dict[kCGWindowNumber as String] as? CGWindowID,
            let ownerPID    = dict[kCGWindowOwnerPID as String] as? pid_t,
            let ownerName   = dict[kCGWindowOwnerName as String] as? String,
            let layer       = dict[kCGWindowLayer as String] as? Int32
        else {
            return nil
        }

        // kCGWindowBounds is stored as a CFDictionary with keys X, Y, Width, Height.
        let bounds: CGRect
        if let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat] {
            bounds = CGRect(
                x:      boundsDict["X"]      ?? 0,
                y:      boundsDict["Y"]      ?? 0,
                width:  boundsDict["Width"]  ?? 0,
                height: boundsDict["Height"] ?? 0
            )
        } else if
            let cfBoundsDict = dict[kCGWindowBounds as String],
            let cfRect = CGRect(dictionaryRepresentation: cfBoundsDict as! CFDictionary)
        {
            bounds = cfRect
        } else {
            bounds = .zero
        }

        // kCGWindowIsOnscreen may be absent for windows that are off-screen;
        // default to true when the flag is not present (we already filtered with
        // kCGWindowListOptionOnScreenOnly, so this is a safe default).
        let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? true

        let ownerBundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""

        return WindowInfo(
            id:            windowNumber,
            ownerPID:      ownerPID,
            ownerName:     ownerName,
            ownerBundleID: ownerBundleID,
            bounds:        bounds,
            layer:         layer,
            isOnScreen:    isOnScreen
        )
    }

    /// Resolves the bundle identifier for a running application with the given PID.
    /// Returns `nil` if no matching application is found.
    func bundleIdentifier(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
