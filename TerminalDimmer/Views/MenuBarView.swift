import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var windowStateManager: WindowStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Header
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("TerminalDimmer")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // MARK: - Enable Toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $preferences.isEnabled) {
                    Label("Enabled", systemImage: "power")
                        .font(.body)
                }
                .toggleStyle(.switch)
                .onChange(of: preferences.isEnabled) { newValue in
                    if newValue {
                        windowStateManager.start()
                    } else {
                        windowStateManager.stop()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: - Dim Intensity Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Dim Intensity", systemImage: "sun.min")
                        .font(.body)
                    Spacer()
                    Text(intensityLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $preferences.dimIntensity,
                    in: 0.0...0.8,
                    step: 0.05
                )
                .onChange(of: preferences.dimIntensity) { newValue in
                    windowStateManager.updateDimIntensity(newValue)
                }
                .disabled(!preferences.isEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: - Terminals Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Terminals")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 2)

                ForEach(BundleIdentifiers.allTerminals, id: \.self) { bundleID in
                    Toggle(isOn: terminalBinding(for: bundleID)) {
                        Text(terminalDisplayName(for: bundleID))
                            .font(.body)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!preferences.isEnabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: - Quit Button
            HStack {
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit", systemImage: "power")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var intensityLabel: String {
        let percent = Int(preferences.dimIntensity * 100)
        return "\(percent)%"
    }

    private func terminalBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: {
                preferences.enabledTerminals.contains(bundleID)
            },
            set: { enabled in
                if enabled {
                    preferences.enabledTerminals.insert(bundleID)
                } else {
                    preferences.enabledTerminals.remove(bundleID)
                }
            }
        )
    }

    private func terminalDisplayName(for bundleID: String) -> String {
        // Map bundle IDs to human-readable names; aligned with BundleIdentifiers.swift
        let names: [String: String] = [
            "com.apple.Terminal":    "Terminal",
            "com.googlecode.iterm2": "iTerm2",
            "org.alacritty":         "Alacritty",
            "dev.warp.Warp-Stable":  "Warp",
            "net.kovidgoyal.kitty":  "Kitty",
            "co.zeit.hyper":         "Hyper",
        ]
        return names[bundleID] ?? bundleID
    }
}

// MARK: - Preview

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        let prefs = Preferences()
        let manager = WindowStateManager(preferences: prefs)
        MenuBarView(preferences: prefs, windowStateManager: manager)
            .frame(width: 280)
    }
}
#endif
