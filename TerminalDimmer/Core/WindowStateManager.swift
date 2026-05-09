import Cocoa
import Combine

/// Central coordinator that ties WindowTracker, FocusMonitor, OverlayManager,
/// and Preferences together into a cohesive dimming system.
@MainActor
final class WindowStateManager: ObservableObject {

    // MARK: - Sub-systems

    let windowTracker: WindowTracker
    let focusMonitor: FocusMonitor
    let overlayManager: OverlayManager

    /// User-facing settings. Changes are observed via Combine so that the manager
    /// can react (e.g. rebuild overlays when `isEnabled` flips or `enabledTerminals`
    /// changes).
    @Published var preferences: Preferences

    // MARK: - Published State

    /// All terminal windows currently being tracked, keyed by CGWindowID.
    @Published private(set) var trackedWindows: [CGWindowID: WindowInfo] = [:]

    /// The CGWindowID of the terminal window that currently has keyboard focus,
    /// or nil when a non-terminal app is focused.
    @Published private(set) var focusedWindowID: CGWindowID?

    /// Whether the manager is actively monitoring windows.
    @Published private(set) var isRunning: Bool = false

    // MARK: - Private

    private var pollingTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Initialiser

    init(
        windowTracker: WindowTracker = WindowTracker(),
        focusMonitor: FocusMonitor = FocusMonitor(),
        overlayManager: OverlayManager = OverlayManager(),
        preferences: Preferences = Preferences()
    ) {
        self.windowTracker = windowTracker
        self.focusMonitor = focusMonitor
        self.overlayManager = overlayManager
        self.preferences = preferences

        bindPreferences()
    }

    // MARK: - Public API

    /// Begin monitoring terminal windows and managing dim overlays.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Wire up the focus monitor callback.
        focusMonitor.onFocusChanged = { [weak self] pid, bundleID in
            Task { @MainActor [weak self] in
                self?.handleFocusChange(pid: pid, bundleID: bundleID)
            }
        }
        focusMonitor.startMonitoring()

        // Kick off the polling loop.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollWindows()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer

        // Perform an immediate scan to populate trackedWindows first, then resolve
        // the focused window and remove its overlay.
        //
        // Order matters here:
        //   1. pollWindows() discovers all terminal windows and creates overlays for
        //      all of them (focusedWindowID is nil at this point, so every window
        //      gets an overlay).
        //   2. resolveFocusedWindowID() queries the AX API and CGWindowList to
        //      determine which specific window is active, sets focusedWindowID, and
        //      immediately hides the overlay for that window.
        //
        // This avoids the race condition where onFocusChanged (dispatched via async
        // Task) would fire after pollWindows() and never get the chance to suppress
        // the focused window's overlay before it was shown.
        pollWindows()
        resolveFocusedWindowID()
    }

    /// Stop all monitoring and tear down every overlay that was created.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        pollingTimer?.invalidate()
        pollingTimer = nil

        focusMonitor.stopMonitoring()

        // Remove every overlay that is currently alive.
        for id in trackedWindows.keys {
            overlayManager.removeOverlay(for: id)
        }

        trackedWindows.removeAll()
        focusedWindowID = nil
    }

    /// Propagate a new dim intensity to all currently-visible overlays.
    func updateDimIntensity(_ intensity: Double) {
        preferences.dimIntensity = intensity
        for (id, _) in trackedWindows where id != focusedWindowID {
            overlayManager.updateOverlay(for: id, intensity: intensity)
        }
    }

    // MARK: - Polling

    /// Called ~10 times per second to reconcile the live window list with
    /// the set of overlays that are currently being displayed.
    private func pollWindows() {
        guard isRunning, preferences.isEnabled else {
            // If the feature is disabled, ensure no overlays remain.
            if !trackedWindows.isEmpty {
                for id in trackedWindows.keys {
                    overlayManager.removeOverlay(for: id)
                }
                trackedWindows.removeAll()
            }
            return
        }

        // --- Intra-app focus detection ---
        // The AX callback (`handleFocusChange`) only fires on inter-app switches.
        // When the user moves between two windows of the same app (e.g. two
        // Terminal windows) the callback is never invoked.  We compensate by
        // actively querying the focused window on every poll cycle so that the
        // change is detected within one poll interval (~100 ms).
        if let focusInfo = focusMonitor.getFocusedWindowInfo(),
           preferences.enabledTerminals.contains(focusInfo.bundleID ?? "") {
            let newFocusedID = findWindowByFrame(focusInfo.frame)
            if newFocusedID != focusedWindowID {
                let previousFocusedID = focusedWindowID
                focusedWindowID = newFocusedID
                print("[WindowStateManager] Poll detected focus change: \(previousFocusedID.map { "\($0)" } ?? "nil") -> \(newFocusedID.map { "\($0)" } ?? "nil")")

                // Re-show overlay for the window that just lost focus.
                if let oldID = previousFocusedID,
                   let window = trackedWindows[oldID] {
                    overlayManager.showOverlay(
                        for: oldID,
                        frame: window.bounds,
                        intensity: preferences.dimIntensity
                    )
                }

                // Hide overlay for the window that just gained focus.
                if let newID = newFocusedID {
                    overlayManager.hideOverlay(for: newID)
                }
            }
        }

        // Fetch the current set of terminal windows whose bundle IDs match
        // those that the user has enabled for dimming.
        let liveWindows = windowTracker
            .getTerminalWindows()
            .filter { preferences.enabledTerminals.contains($0.ownerBundleID) }

        let liveIDs = Set(liveWindows.map(\.id))
        let trackedIDs = Set(trackedWindows.keys)

        // --- New windows that appeared since the last poll ---
        let newIDs = liveIDs.subtracting(trackedIDs)
        for window in liveWindows where newIDs.contains(window.id) {
            trackedWindows[window.id] = window
            // Only create an overlay when this window is not the focused one.
            if window.id != focusedWindowID {
                overlayManager.createOverlay(
                    for: window.id,
                    frame: window.bounds,
                    intensity: preferences.dimIntensity
                )
            }
        }

        // --- Windows that are still present — sync position / size ---
        let persistedIDs = liveIDs.intersection(trackedIDs)
        for window in liveWindows where persistedIDs.contains(window.id) {
            let previous = trackedWindows[window.id]
            trackedWindows[window.id] = window
            // Only update the overlay geometry when the window moved or resized,
            // and only when it is not the currently focused terminal.
            if window.id != focusedWindowID, window.bounds != previous?.bounds {
                overlayManager.updateOverlay(
                    for: window.id,
                    frame: window.bounds,
                    intensity: preferences.dimIntensity
                )
            }
        }

        // --- Windows that closed since the last poll ---
        let closedIDs = trackedIDs.subtracting(liveIDs)
        for id in closedIDs {
            overlayManager.removeOverlay(for: id)
            trackedWindows.removeValue(forKey: id)
            if focusedWindowID == id {
                focusedWindowID = nil
            }
        }
    }

    // MARK: - Focus Handling

    /// Resolves and sets `focusedWindowID` synchronously based on the current
    /// frontmost application, then immediately hides the overlay for the focused
    /// window.
    ///
    /// This is called after the initial `pollWindows()` so `trackedWindows` is
    /// already populated. It corrects the state where every window received an
    /// overlay during discovery (because `focusedWindowID` was nil at that point).
    private func resolveFocusedWindowID() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              preferences.enabledTerminals.contains(bundleID) else {
            focusedWindowID = nil
            return
        }

        let pid = app.processIdentifier
        let resolvedID = findWindowID(forFocusedPID: pid)
        focusedWindowID = resolvedID
        print("[WindowStateManager] Initial focused window resolved: \(resolvedID.map { "\($0)" } ?? "nil") (pid=\(pid))")

        // The initial pollWindows() created an overlay for this window because
        // focusedWindowID was nil at the time. Hide it now.
        if let id = resolvedID {
            overlayManager.hideOverlay(for: id)
        }
    }

    /// Reacts to a change in which application (and therefore which window)
    /// has keyboard focus.
    ///
    /// - Parameters:
    ///   - pid:      The process ID of the newly focused application, or nil
    ///               when focus moves to a non-app context.
    ///   - bundleID: The CFBundleIdentifier of the newly focused application.
    private func handleFocusChange(pid: pid_t?, bundleID: String?) {
        let previousFocusedID = focusedWindowID

        // Determine whether the focused app is one of the tracked terminals.
        if let pid, let bundleID, preferences.enabledTerminals.contains(bundleID) {
            // Find the specific window that currently has focus within this app.
            // Using PID alone is insufficient when multiple windows share the same PID
            // (e.g. multiple Terminal.app windows). Use the AX API to get the focused
            // window's frame and match it against tracked windows by position.
            focusedWindowID = findWindowID(forFocusedPID: pid)
            print("[WindowStateManager] Focus changed to pid=\(pid) bundleID=\(bundleID) -> windowID=\(focusedWindowID.map { "\($0)" } ?? "nil")")
        } else {
            // Focus moved to a non-terminal app (e.g., Chrome, Finder).
            // IMPORTANT: Do NOT clear focusedWindowID here!
            // We want to retain the last focused terminal so it stays clear
            // while the user is in another app. This way they can see which
            // terminal they were working in.
            print("[WindowStateManager] Focus moved to non-terminal app (bundleID=\(bundleID ?? "nil")). Retaining focusedWindowID=\(focusedWindowID.map { "\($0)" } ?? "nil")")
            return  // Don't change any overlay state
        }

        // Hide overlay for the window that just received focus.
        if let newID = focusedWindowID, newID != previousFocusedID {
            overlayManager.hideOverlay(for: newID)
        }

        // Re-show overlay for the window that lost focus (if it is still open).
        if let oldID = previousFocusedID,
           oldID != focusedWindowID,
           let window = trackedWindows[oldID] {
            overlayManager.showOverlay(
                for: oldID,
                frame: window.bounds,
                intensity: preferences.dimIntensity
            )
        }
    }

    /// Searches `trackedWindows` for the window whose bounds best match `frame`.
    ///
    /// A small tolerance is applied because AX coordinates and CGWindowList
    /// coordinates can differ by a few pixels (e.g. due to window shadows or
    /// integer rounding).  Returns `nil` when no tracked window falls within
    /// the tolerance.
    private func findWindowByFrame(_ frame: CGRect) -> CGWindowID? {
        let tolerance: CGFloat = 8.0
        return trackedWindows.values.first { window in
            abs(window.bounds.origin.x - frame.origin.x) <= tolerance
                && abs(window.bounds.origin.y - frame.origin.y) <= tolerance
                && abs(window.bounds.width  - frame.width)      <= tolerance
                && abs(window.bounds.height - frame.height)     <= tolerance
        }?.id
    }

    /// Finds the `CGWindowID` of the window that currently has keyboard focus
    /// within the application identified by `pid`.
    ///
    /// Strategy:
    /// 1. Use the Accessibility API to get the focused window's frame (position + size).
    /// 2. Cross-reference that frame with the tracked windows to find a match.
    ///
    /// If accessibility is not available (no permission) or the frame cannot be
    /// retrieved, fall back to picking the first tracked window owned by `pid`.
    /// This fallback is correct for the common single-window case and is no worse
    /// than the previous behaviour for the multi-window case.
    private func findWindowID(forFocusedPID pid: pid_t) -> CGWindowID? {
        // Attempt precise matching via AX API frame comparison.
        if let focusedFrame = focusMonitor.getFocusedWindowFrame(for: pid) {
            // Match against currently tracked windows: find the tracked window
            // whose bounds are closest to the AX-reported frame. We allow a small
            // tolerance because AX and CGWindowList can differ by a pixel or two.
            let tolerance: CGFloat = 4.0
            let match = trackedWindows.values.first { window in
                guard window.ownerPID == pid else { return false }
                return abs(window.bounds.origin.x - focusedFrame.origin.x) <= tolerance
                    && abs(window.bounds.origin.y - focusedFrame.origin.y) <= tolerance
                    && abs(window.bounds.width  - focusedFrame.width)      <= tolerance
                    && abs(window.bounds.height - focusedFrame.height)     <= tolerance
            }
            if let match {
                print("[WindowStateManager] Precise AX frame match for pid=\(pid): windowID=\(match.id) frame=\(match.bounds)")
                return match.id
            }

            // The focused window may not be in trackedWindows yet (e.g. it just
            // appeared and the next poll hasn't run). Fall through to PID matching.
            print("[WindowStateManager] No frame match found for pid=\(pid), focusedFrame=\(focusedFrame). Falling back to PID match.")
        }

        // Fallback: pick the first tracked window belonging to this PID.
        // This is correct when there is only one window per process and is used
        // when accessibility permissions are not granted.
        let fallback = trackedWindows.values.first(where: { $0.ownerPID == pid })
        print("[WindowStateManager] PID fallback for pid=\(pid): windowID=\(fallback.map { "\($0.id)" } ?? "nil")")
        return fallback?.id
    }

    // MARK: - Preference Observation

    /// Subscribe to preference changes and react accordingly.
    private func bindPreferences() {
        // When the master switch is toggled, apply or remove all overlays.
        $preferences
            .map(\.isEnabled)
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    if self.isRunning { self.pollWindows() }
                } else {
                    for id in self.trackedWindows.keys {
                        self.overlayManager.removeOverlay(for: id)
                    }
                }
            }
            .store(in: &cancellables)

        // When the set of enabled terminals changes, remove stale overlays and
        // add new ones by triggering a poll cycle.
        $preferences
            .map(\.enabledTerminals)
            .removeDuplicates()
            .dropFirst()           // Skip the initial emission on subscription.
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                // Remove overlays for windows whose app is no longer in the list.
                for (id, info) in self.trackedWindows
                where !self.preferences.enabledTerminals.contains(info.ownerBundleID) {
                    self.overlayManager.removeOverlay(for: id)
                    self.trackedWindows.removeValue(forKey: id)
                }
                // A full poll will pick up any newly enabled terminal apps.
                self.pollWindows()
            }
            .store(in: &cancellables)

        // When dim intensity changes, push the new value to existing overlays.
        $preferences
            .map(\.dimIntensity)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] intensity in
                guard let self else { return }
                for (id, _) in self.trackedWindows where id != self.focusedWindowID {
                    self.overlayManager.updateOverlay(for: id, intensity: intensity)
                }
            }
            .store(in: &cancellables)
    }
}
