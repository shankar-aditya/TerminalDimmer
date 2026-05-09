import Foundation
import Combine

final class Preferences: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var dimIntensity: Double {
        didSet {
            let clamped = min(1.0, max(0.0, dimIntensity))
            if clamped != dimIntensity {
                dimIntensity = clamped
                return
            }
            UserDefaults.standard.set(dimIntensity, forKey: Keys.dimIntensity)
        }
    }

    @Published var enabledTerminals: Set<String> {
        didSet {
            let array = Array(enabledTerminals)
            UserDefaults.standard.set(array, forKey: Keys.enabledTerminals)
        }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let dimIntensity = "dimIntensity"
        static let enabledTerminals = "enabledTerminals"
    }

    // MARK: - Initializer

    init() {
        let defaults = UserDefaults.standard

        // isEnabled: default true
        if defaults.object(forKey: Keys.isEnabled) != nil {
            self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        } else {
            self.isEnabled = true
        }

        // dimIntensity: default 0.5, clamped to 0...1
        if defaults.object(forKey: Keys.dimIntensity) != nil {
            let stored = defaults.double(forKey: Keys.dimIntensity)
            self.dimIntensity = min(1.0, max(0.0, stored))
        } else {
            self.dimIntensity = 0.5
        }

        // enabledTerminals: default all known terminals
        if let stored = defaults.array(forKey: Keys.enabledTerminals) as? [String] {
            self.enabledTerminals = Set(stored)
        } else {
            self.enabledTerminals = Set(BundleIdentifiers.allTerminals)
        }
    }

    // MARK: - Helpers

    /// Returns true if the given bundle ID is in the enabled terminals set.
    func isTerminalEnabled(_ bundleID: String) -> Bool {
        enabledTerminals.contains(bundleID)
    }

    /// Toggles whether a terminal bundle ID is enabled.
    func toggleTerminal(_ bundleID: String) {
        if enabledTerminals.contains(bundleID) {
            enabledTerminals.remove(bundleID)
        } else {
            enabledTerminals.insert(bundleID)
        }
    }

    /// Resets all preferences to their default values.
    func resetToDefaults() {
        isEnabled = true
        dimIntensity = 0.5
        enabledTerminals = Set(BundleIdentifiers.allTerminals)
    }
}
