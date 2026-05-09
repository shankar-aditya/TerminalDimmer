import AppKit
import CoreGraphics

/// A transparent, click-through overlay window that dims the area it covers.
///
/// This window sits just above normal windows in the z-order and uses a
/// semi-transparent black background to produce a dimming effect. It passes
/// all mouse events through to the windows beneath it.
final class DimOverlayWindow: NSWindow {

    // MARK: - Properties

    /// Current dim intensity in the range [0, 1].
    private(set) var dimIntensity: CGFloat

    // MARK: - Init

    /// Creates a new dim overlay window.
    ///
    /// - Parameters:
    ///   - frame: The frame rectangle in screen coordinates (AppKit / bottom-left origin).
    ///   - dimIntensity: Opacity of the black overlay in the range [0, 1].
    init(frame: NSRect, dimIntensity: CGFloat) {
        self.dimIntensity = dimIntensity.clamped(to: 0...1)

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        configureWindow()
    }

    // MARK: - Private helpers

    private func configureWindow() {
        // Visuals
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.black.withAlphaComponent(dimIntensity)

        // Z-order: same level as normal windows so the overlay sits above its
        // specific target window (via order(_:relativeTo:)) without covering
        // unrelated apps like System Preferences.
        level = .normal

        // Input: let all clicks fall through to whatever is below.
        ignoresMouseEvents = true

        // Spaces behaviour: follow the user across every Space / full-screen app.
        collectionBehavior = [.fullScreenAuxiliary, .transient]
    }

    // MARK: - Public API

    /// Updates the overlay opacity without recreating the window.
    ///
    /// - Parameter intensity: New dim intensity in the range [0, 1].
    func updateDimIntensity(_ intensity: CGFloat) {
        dimIntensity = intensity.clamped(to: 0...1)
        backgroundColor = NSColor.black.withAlphaComponent(dimIntensity)
    }

    /// Repositions and resizes the overlay to match a new frame.
    ///
    /// - Parameter frame: New frame in AppKit screen coordinates (bottom-left origin).
    func updateFrame(_ frame: CGRect) {
        setFrame(frame, display: true)
    }

    /// Orders this overlay directly above the window with the given window number.
    ///
    /// Using `order(_:relativeTo:)` instead of `orderFront(nil)` confines the
    /// overlay to just above its target window rather than above every app.
    ///
    /// - Parameter windowNumber: The AppKit window number of the target window
    ///   (equivalent to `CGWindowID` from `CGWindowListCopyWindowInfo`).
    func orderAbove(windowNumber: Int) {
        order(.above, relativeTo: windowNumber)
    }
}

// MARK: - CGFloat convenience

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
