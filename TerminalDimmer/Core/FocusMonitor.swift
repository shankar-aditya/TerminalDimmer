import Foundation
import AppKit
import ApplicationServices

// MARK: - FocusMonitor

/// Monitors which window/application is currently focused using the macOS Accessibility API.
/// Falls back to NSWorkspace when accessibility permissions are unavailable.
final class FocusMonitor {

    // MARK: - Public Properties

    /// The PID of the process owning the currently focused window.
    private(set) var focusedWindowPID: pid_t?

    /// The bundle identifier of the currently focused application.
    private(set) var focusedAppBundleID: String?

    /// Called whenever the focused application changes.
    /// Receives the new PID and bundle ID (both may be nil if focus is lost or indeterminate).
    var onFocusChanged: ((pid_t?, String?) -> Void)?

    // MARK: - Private Properties

    /// The AXObserver watching the system-wide accessibility element for focus changes.
    private var axObserver: AXObserver?

    /// Retains the system-wide AXUIElement so it is not released while the observer is active.
    private var systemWideElement: AXUIElement?

    /// Token for the NSWorkspace active-application-changed notification (fallback path).
    private var workspaceObserverToken: Any?

    /// Whether the monitor is currently running.
    private var isMonitoring = false

    // MARK: - Initialisation

    init() {}

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Starts monitoring for focus changes.
    ///
    /// If accessibility permissions have been granted the method installs an
    /// AXObserver on the system-wide element.  If permissions are absent it
    /// registers a fallback NSWorkspace observer so the callback is still
    /// delivered (with slightly lower fidelity – per-app rather than
    /// per-window granularity).
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        if AXIsProcessTrusted() {
            startAXObserver()
        } else {
            print("[FocusMonitor] Accessibility permission not granted. " +
                  "Falling back to NSWorkspace notifications. " +
                  "Grant access in System Settings > Privacy & Security > Accessibility.")
            startWorkspaceFallback()
        }
    }

    /// Stops monitoring and releases all resources.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        stopAXObserver()
        stopWorkspaceFallback()
    }

    /// Returns the PID and bundle ID of the currently active application.
    ///
    /// Queries `NSWorkspace.shared.frontmostApplication` directly so it is
    /// always accurate, even if the AXObserver has not fired yet.
    func getCurrentFocusedApp() -> (pid: pid_t, bundleID: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return nil
        }
        return (pid: app.processIdentifier, bundleID: bundleID)
    }

    // MARK: - Focused Window Info

    /// Bundles the bundle identifier and frame of the currently focused window.
    struct FocusedWindowInfo {
        let bundleID: String?
        let pid: pid_t
        let frame: CGRect
    }

    /// Returns the bundle ID and frame of the currently focused window by
    /// combining `getCurrentFocusedApp()` with `getFocusedWindowFrame(for:)`.
    ///
    /// Returns `nil` if the frontmost application cannot be determined or if
    /// its focused window frame is not available via the Accessibility API.
    func getFocusedWindowInfo() -> FocusedWindowInfo? {
        guard let app = getCurrentFocusedApp() else { return nil }
        guard let frame = getFocusedWindowFrame(for: app.pid) else { return nil }
        return FocusedWindowInfo(bundleID: app.bundleID, pid: app.pid, frame: frame)
    }

    /// Returns the frame (in CG screen coordinates, top-left origin) of the
    /// currently focused window as reported by the Accessibility API.
    ///
    /// Returns `nil` if accessibility permissions are not granted or if the
    /// focused application does not expose a focused window.
    func getFocusedWindowFrame(for pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window element from the application.
        var focusedWindowRef: CFTypeRef?
        let windowStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard windowStatus == .success,
              let focusedWindowRef,
              CFGetTypeID(focusedWindowRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedWindowElement = focusedWindowRef as! AXUIElement

        // Get position and size of the focused window.
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posStatus = AXUIElementCopyAttributeValue(
            focusedWindowElement,
            kAXPositionAttribute as CFString,
            &positionRef
        )
        let sizeStatus = AXUIElementCopyAttributeValue(
            focusedWindowElement,
            kAXSizeAttribute as CFString,
            &sizeRef
        )

        guard posStatus == .success,
              sizeStatus == .success,
              let positionRef,
              let sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        // AXValue wraps CGPoint and CGSize — extract them.
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    // MARK: - AXObserver Setup

    private func startAXObserver() {
        // The system-wide element lets us observe events from any application.
        let sysElement = AXUIElementCreateSystemWide()
        systemWideElement = sysElement

        // We need *any* PID to create an AXObserver; 0 is not valid, so we
        // use the PID of our own process.  For system-wide notifications the
        // actual PID value is irrelevant because we attach to the system-wide
        // element rather than an application element.
        var observer: AXObserver?
        let selfPID = ProcessInfo.processInfo.processIdentifier

        let createStatus = AXObserverCreate(selfPID, focusChangedCallback, &observer)
        guard createStatus == .success, let observer else {
            print("[FocusMonitor] Failed to create AXObserver (error \(createStatus.rawValue)).")
            startWorkspaceFallback()
            return
        }

        // Pass `self` as the user-info pointer so the C callback can reach us.
        let addStatus = AXObserverAddNotification(
            observer,
            sysElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard addStatus == .success else {
            print("[FocusMonitor] Failed to add AX notification (error \(addStatus.rawValue)). " +
                  "Falling back to NSWorkspace.")
            startWorkspaceFallback()
            return
        }

        // Schedule the observer on the current run loop.
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = observer
        print("[FocusMonitor] AXObserver started successfully.")
    }

    private func stopAXObserver() {
        guard let observer = axObserver else { return }

        if let sysElement = systemWideElement {
            AXObserverRemoveNotification(
                observer,
                sysElement,
                kAXFocusedWindowChangedNotification as CFString
            )
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = nil
        systemWideElement = nil
    }

    // MARK: - NSWorkspace Fallback

    private func startWorkspaceFallback() {
        guard workspaceObserverToken == nil else { return }

        workspaceObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            self.handleFocusChange(pid: app?.processIdentifier,
                                   bundleID: app?.bundleIdentifier)
        }
        print("[FocusMonitor] NSWorkspace fallback observer registered.")
    }

    private func stopWorkspaceFallback() {
        if let token = workspaceObserverToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserverToken = nil
        }
    }

    // MARK: - Focus-Change Handling

    /// Called from the C callback (on the main run-loop) when the AX notification fires.
    ///
    /// For `kAXFocusedWindowChangedNotification` observed on the system-wide element,
    /// `element` is the system-wide element itself (not the focused window), so we
    /// query the frontmost application directly instead of calling AXUIElementGetPid
    /// on the notification element.
    fileprivate func handleAXFocusChanged(element: AXUIElement) {
        // The notification element for a system-wide observer is the system-wide
        // AXUIElement, not the focused window. Query the frontmost app directly.
        updateFromFrontmostApplication()
    }

    /// Central method that updates stored state and fires the callback.
    private func handleFocusChange(pid: pid_t?, bundleID: String?) {
        let resolvedPID: pid_t? = (pid == 0) ? nil : pid
        focusedWindowPID = resolvedPID
        focusedAppBundleID = bundleID
        onFocusChanged?(resolvedPID, bundleID)
    }

    /// Reads the current frontmost application from NSWorkspace and updates state.
    private func updateFromFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            handleFocusChange(pid: nil, bundleID: nil)
            return
        }
        handleFocusChange(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
    }
}

// MARK: - C Callback (AXObserverCallback)

/// Free C function required by `AXObserverCreate`.
///
/// `userData` is an unretained pointer to the `FocusMonitor` instance that
/// registered the notification.  The callback is invoked on the main run loop.
private func focusChangedCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    let monitor = Unmanaged<FocusMonitor>.fromOpaque(userData).takeUnretainedValue()
    monitor.handleAXFocusChanged(element: element)
}
