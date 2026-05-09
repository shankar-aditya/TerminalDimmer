# TerminalDimmer

**Keep your focus sharp — dim every terminal window except the one you are using.**

TerminalDimmer is a lightweight macOS menu bar app that automatically dims inactive terminal windows and keeps the active one clear. It works silently in the background with no Dock icon, reacts instantly to focus changes, and supports six terminal emulators out of the box.

---

## Screenshot

> _Add a screenshot here once the app is running._
>
> Suggested capture: two or three terminal windows open side by side, the active one bright and the others visibly dimmed.

---

## Features

- **Auto-dims inactive terminals** — a semi-transparent black overlay appears on every terminal window that does not have keyboard focus.
- **Active window stays clear** — the focused terminal is always shown at full brightness, with no overlay.
- **Multi-window aware** — works correctly when you have many terminal windows open at once, including multiple windows from the same application (e.g. two `Terminal.app` windows).
- **Switches across spaces** — overlays follow their target windows through Mission Control spaces and full-screen apps.
- **Six supported terminals** — Terminal.app, iTerm2, Warp, Kitty, Alacritty, and Hyper are recognised out of the box.
- **Per-terminal toggle** — enable or disable dimming for each terminal independently from the menu bar popover.
- **Adjustable intensity** — drag a slider from 0% to 80% to set how dark the overlay is (default: 50%).
- **Menu bar only** — no Dock icon, no window clutter.
- **Preferences persist** — all settings are saved to `UserDefaults` and restored on the next launch.
- **Click-through overlays** — the dim overlay passes all mouse events through to the window beneath it; it never interferes with typing or clicking.

---

## Requirements

| Requirement | Detail |
|---|---|
| macOS | 13.0 Ventura or later |
| Swift | 5.9 or later (bundled with Xcode 15+) |
| Accessibility permission | Required for per-window focus detection |

> **Why Accessibility?** TerminalDimmer uses the macOS Accessibility API (`AXObserver`) to detect exactly which window is focused — even when you switch between two windows of the same app. Without this permission the app falls back to `NSWorkspace` notifications, which only provide per-application granularity (all windows of a given app are treated as a single unit).

---

## Installation

### Option 1 — Build from source and run directly

```bash
git clone https://github.com/your-username/TerminalDimmer.git
cd TerminalDimmer
swift run
```

The app starts immediately in the menu bar. Grant Accessibility access when prompted (see [Granting Accessibility Permission](#granting-accessibility-permission)).

### Option 2 — Build a release binary

```bash
swift build -c release
```

The compiled binary is written to `.build/release/TerminalDimmer`.

### Option 3 — Create a self-contained `.app` bundle

Building a proper `.app` lets you move TerminalDimmer to `/Applications` and add it to Login Items.

```bash
# 1. Build the release binary
swift build -c release

# 2. Create the bundle structure
mkdir -p TerminalDimmer.app/Contents/MacOS
mkdir -p TerminalDimmer.app/Contents/Resources

# 3. Copy the binary
cp .build/release/TerminalDimmer TerminalDimmer.app/Contents/MacOS/

# 4. Copy the Info.plist
cp TerminalDimmer/Resources/Info.plist TerminalDimmer.app/Contents/

# 5. Move the bundle to Applications (optional)
mv TerminalDimmer.app /Applications/
```

### Adding to Login Items

To launch TerminalDimmer automatically at login:

1. Open **System Settings** > **General** > **Login Items**.
2. Click **+** and select `TerminalDimmer.app`.

---

## Granting Accessibility Permission

TerminalDimmer requests Accessibility access the first time it launches. If you missed the prompt, grant it manually:

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Click **+** and add `TerminalDimmer` (or `TerminalDimmer.app`).
3. Restart TerminalDimmer.

Without this permission dimming still works at the application level — switching from Terminal.app to Chrome dims all terminal windows — but switching between two `Terminal.app` windows will not trigger a dimming update until you switch to a different app and back.

---

## Usage

### Enable / disable dimming

Click the `⬤` icon in the menu bar to open the popover, then toggle the **Enabled** switch. The setting persists across relaunches.

### Adjust dim intensity

Open the menu bar popover. Use the **Dim Intensity** slider to set how dark inactive terminal windows appear (0% = no dimming, 80% = near-black). Changes apply immediately to all existing overlays.

### Toggle individual terminals

In the **Terminals** section of the popover, check or uncheck each terminal to include or exclude it from dimming. Unchecking a terminal removes its overlays immediately; rechecking it adds them back on the next poll cycle (within ~100 ms).

### Quit

Open the popover and click **Quit** at the bottom, or use the standard `Cmd+Q` shortcut while the popover is in focus.

---

## How It Works

TerminalDimmer is composed of five focused components that are coordinated by a central `WindowStateManager`.

### 1. Window discovery — `WindowTracker`

Every ~100 ms, `WindowTracker` calls `CGWindowListCopyWindowInfo` to get the current list of all on-screen windows. It filters this list to only windows whose owning process matches one of the six known terminal bundle identifiers.

### 2. Focus detection — `FocusMonitor`

`FocusMonitor` installs an `AXObserver` on the macOS system-wide accessibility element and subscribes to `kAXFocusedWindowChangedNotification`. When focus changes, it queries `NSWorkspace.shared.frontmostApplication` to identify the newly active app.

For the common case of switching between two windows of the *same* application (e.g. two `Terminal.app` windows), `AXFocusedWindowChangedNotification` does not always fire. To handle this, `WindowStateManager` also polls the focused window frame via `AXUIElementCopyAttributeValue` on every tick and compares it against tracked window bounds (with an 8 pt tolerance to account for coordinate-system rounding between CoreGraphics and the Accessibility API).

If Accessibility permission is not granted, `FocusMonitor` falls back to `NSWorkspace.didActivateApplicationNotification` for coarser, per-application focus tracking.

### 3. Overlay rendering — `DimOverlayWindow` + `OverlayManager`

For each inactive terminal window, `OverlayManager` creates a `DimOverlayWindow` — a borderless, non-opaque `NSWindow` filled with `NSColor.black` at the configured alpha value. The overlay is ordered directly above its target window using `NSWindow.order(_:relativeTo:)` (not `orderFront`), so it does not cover unrelated applications. `ignoresMouseEvents = true` ensures all clicks pass through to the terminal beneath.

Overlays are given `collectionBehavior = [.fullScreenAuxiliary, .transient]` so they travel with their target windows across Mission Control spaces.

### 4. Preferences — `Preferences`

All user settings (`isEnabled`, `dimIntensity`, `enabledTerminals`) are `@Published` properties backed by `UserDefaults`. `WindowStateManager` observes these via Combine and reacts without requiring an app restart.

### 5. Coordination — `WindowStateManager`

`WindowStateManager` ties the four subsystems together. On each poll cycle it:

1. Detects intra-app window-focus changes by comparing the current AX-reported focused frame against tracked windows.
2. Reconciles the live `CGWindowList` with the set of tracked windows — creating overlays for new windows, removing overlays for closed windows, and updating overlay frames when a window is moved or resized.
3. Ensures the focused window always has its overlay hidden, and all other tracked windows have their overlay visible.

---

## Project Structure

```
TerminalDimmer/
├── Package.swift
└── TerminalDimmer/
    ├── App/
    │   ├── AppDelegate.swift          # NSApplicationDelegate, menu bar setup
    │   └── TerminalDimmerApp.swift    # SwiftUI App entry point
    ├── Core/
    │   ├── WindowStateManager.swift   # Central coordinator
    │   ├── WindowTracker.swift        # CGWindowList polling
    │   ├── FocusMonitor.swift         # AXObserver + NSWorkspace fallback
    │   ├── OverlayManager.swift       # Overlay lifecycle management
    │   └── DimOverlayWindow.swift     # Transparent NSWindow overlay
    ├── Models/
    │   ├── Preferences.swift          # ObservableObject user settings
    │   └── WindowInfo.swift           # Value type for a tracked window
    ├── Utilities/
    │   ├── BundleIdentifiers.swift    # Known terminal bundle IDs
    │   └── AccessibilityHelper.swift  # AX permission helpers
    ├── Views/
    │   └── MenuBarView.swift          # SwiftUI popover UI
    └── Resources/
        └── Info.plist
```

---

## Building from Source

### Prerequisites

- macOS 13.0 or later
- Xcode 15 or later (provides Swift 5.9 and the macOS SDK)

### Debug build

```bash
git clone https://github.com/your-username/TerminalDimmer.git
cd TerminalDimmer
swift build
swift run
```

### Release build

```bash
swift build -c release
.build/release/TerminalDimmer
```

### Run tests (if present)

```bash
swift test
```

---

## Configuration

### Supported terminals

| Terminal | Bundle ID |
|---|---|
| Terminal.app | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Warp | `dev.warp.Warp-Stable` |
| Kitty | `net.kovidgoyal.kitty` |
| Alacritty | `org.alacritty` |
| Hyper | `co.zeit.hyper` |

### Enabling / disabling specific terminals

Use the checkboxes in the menu bar popover. Changes take effect immediately without restarting the app.

### Adding a new terminal

To support a terminal not listed above, add its bundle ID to `BundleIdentifiers.swift`:

```swift
// TerminalDimmer/Utilities/BundleIdentifiers.swift

static let myTerminal = "com.example.MyTerminal"   // add this line

static var allTerminals: [String] {
    [terminal, iTerm2, alacritty, warp, kitty, hyper, myTerminal]  // and reference it here
}
```

Rebuild and relaunch the app. The new terminal will appear in the popover's Terminals list and dimming will apply to its windows automatically.

---

## License

This project is released under the [MIT License](LICENSE).

```
MIT License

Copyright (c) 2024 TerminalDimmer contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Contributing

Contributions are welcome. Please follow the guidelines below.

### Reporting issues

- Check existing issues before opening a new one.
- Include your macOS version, the terminal emulator(s) involved, and clear steps to reproduce.

### Submitting a pull request

1. Fork the repository and create a branch from `main`.
2. Make your changes. Keep each PR focused on a single concern.
3. Ensure the project builds cleanly with `swift build`.
4. Write or update any relevant comments in the code.
5. Open a pull request with a clear title and description of the change.

### Code style

- Follow existing Swift conventions in the codebase (no SwiftLint configuration is required).
- Use `// MARK: -` sections to organise code within files.
- Keep functions small and purpose-focused.
- Prefer value types (`struct`) over reference types (`class`) where state sharing is not required.
