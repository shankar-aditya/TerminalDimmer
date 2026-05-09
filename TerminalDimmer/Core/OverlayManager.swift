import AppKit
import CoreGraphics

/// Manages the lifecycle of all `DimOverlayWindow` instances.
///
/// Each target window tracked by TerminalDimmer is represented by exactly one
/// `DimOverlayWindow` keyed on `CGWindowID`.  `OverlayManager` handles
/// creation, position updates, intensity changes, show/hide, and teardown.
///
/// **Coordinate system note**
/// `CGWindowListCopyWindowInfo` reports bounds in *screen coordinates* where
/// the origin (0, 0) is the **top-left** corner of the primary display.
/// `NSWindow` (AppKit) uses a *flipped* coordinate system where the origin is
/// the **bottom-left** corner of the primary display.
/// Every `WindowInfo.bounds` value is converted before it is passed to AppKit.
final class OverlayManager {

    // MARK: - Properties

    /// All active overlay windows, keyed by the `CGWindowID` they cover.
    private(set) var overlays: [CGWindowID: DimOverlayWindow] = [:]

    /// Dim intensity shared by every overlay (range [0, 1]).
    private(set) var dimIntensity: Double

    // MARK: - Init

    /// - Parameter dimIntensity: Initial dim intensity applied to every overlay.
    init(dimIntensity: Double = 0.5) {
        self.dimIntensity = min(1.0, max(0.0, dimIntensity))
    }

    // MARK: - Overlay lifecycle (WindowInfo-based)

    /// Creates a new overlay for the given window and makes it visible.
    ///
    /// If an overlay already exists for `windowInfo.id` it is returned as-is
    /// after updating its frame to match the current `windowInfo.bounds`.
    ///
    /// - Parameter windowInfo: The target window to cover.
    /// - Returns: The newly created (or existing) `DimOverlayWindow`.
    @discardableResult
    func createOverlay(for windowInfo: WindowInfo) -> DimOverlayWindow {
        return createOverlay(for: windowInfo.id, frame: windowInfo.bounds, intensity: dimIntensity)
    }

    /// Updates the frame of an existing overlay to match the window's current
    /// position and size.
    ///
    /// - Parameter windowInfo: The window whose overlay should be repositioned.
    func updateOverlay(for windowInfo: WindowInfo) {
        updateOverlay(for: windowInfo.id, frame: windowInfo.bounds, intensity: dimIntensity)
    }

    // MARK: - Overlay lifecycle (ID-based, used by WindowStateManager)

    /// Creates a new overlay covering the given frame with the given intensity.
    ///
    /// If an overlay already exists for `windowID` it is updated in-place.
    ///
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the window to cover.
    ///   - frame: The window frame in CG screen coordinates (top-left origin).
    ///   - intensity: Dim intensity in the range [0, 1].
    /// - Returns: The newly created (or existing) `DimOverlayWindow`.
    @discardableResult
    func createOverlay(for windowID: CGWindowID, frame: CGRect, intensity: Double) -> DimOverlayWindow {
        if let existing = overlays[windowID] {
            existing.updateFrame(appKitFrame(for: frame))
            existing.updateDimIntensity(CGFloat(intensity))
            existing.orderAbove(windowNumber: Int(windowID))
            return existing
        }

        let overlay = DimOverlayWindow(
            frame: appKitFrame(for: frame),
            dimIntensity: CGFloat(intensity)
        )
        overlays[windowID] = overlay
        overlay.orderAbove(windowNumber: Int(windowID))
        return overlay
    }

    /// Updates the frame and/or intensity of an existing overlay.
    ///
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the overlay to update.
    ///   - frame: New frame in CG screen coordinates (top-left origin).
    ///   - intensity: New dim intensity in the range [0, 1].
    func updateOverlay(for windowID: CGWindowID, frame: CGRect, intensity: Double) {
        guard let overlay = overlays[windowID] else { return }
        overlay.updateFrame(appKitFrame(for: frame))
        overlay.updateDimIntensity(CGFloat(intensity))
    }

    /// Updates only the intensity of an existing overlay without changing its frame.
    ///
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the overlay to update.
    ///   - intensity: New dim intensity in the range [0, 1].
    func updateOverlay(for windowID: CGWindowID, intensity: Double) {
        overlays[windowID]?.updateDimIntensity(CGFloat(intensity))
    }

    /// Removes the overlay for the given window ID and releases it.
    ///
    /// - Parameter windowID: The `CGWindowID` of the window whose overlay
    ///   should be removed.
    func removeOverlay(for windowID: CGWindowID) {
        guard let overlay = overlays.removeValue(forKey: windowID) else { return }
        overlay.orderOut(nil)
    }

    /// Changes the dim intensity for every currently managed overlay.
    ///
    /// - Parameter intensity: New dim intensity in the range [0, 1].
    func setDimIntensity(_ intensity: Double) {
        dimIntensity = min(1.0, max(0.0, intensity))
        overlays.values.forEach { $0.updateDimIntensity(CGFloat(dimIntensity)) }
    }

    /// Makes a previously hidden overlay visible.
    ///
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the overlay to show.
    ///   - frame: Frame in CG screen coordinates to reposition the overlay.
    ///   - intensity: Dim intensity to apply when showing.
    func showOverlay(for windowID: CGWindowID, frame: CGRect, intensity: Double) {
        guard let overlay = overlays[windowID] else { return }
        overlay.updateFrame(appKitFrame(for: frame))
        overlay.updateDimIntensity(CGFloat(intensity))
        overlay.orderAbove(windowNumber: Int(windowID))
    }

    /// Makes a previously hidden overlay visible without changing its frame or intensity.
    ///
    /// - Parameter windowID: The `CGWindowID` of the overlay to show.
    func showOverlay(for windowID: CGWindowID) {
        overlays[windowID]?.orderAbove(windowNumber: Int(windowID))
    }

    /// Hides an overlay without removing it from `overlays`.
    ///
    /// The overlay can be made visible again with `showOverlay(for:)`.
    ///
    /// - Parameter windowID: The `CGWindowID` of the overlay to hide.
    func hideOverlay(for windowID: CGWindowID) {
        overlays[windowID]?.orderOut(nil)
    }

    /// Removes every managed overlay, hiding them all in the process.
    func removeAllOverlays() {
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    // MARK: - Coordinate conversion

    /// Converts a `CGRect` expressed in CG screen coordinates (top-left origin)
    /// to an `NSRect` in AppKit screen coordinates (bottom-left origin).
    ///
    /// The primary screen's height is used as the reference height because
    /// `CGWindowListCopyWindowInfo` reports all bounds relative to it.
    ///
    /// - Parameter cgRect: Rectangle in CG screen coordinates.
    /// - Returns: Equivalent rectangle in AppKit screen coordinates.
    private func appKitFrame(for cgRect: CGRect) -> NSRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
