import Foundation

struct BundleIdentifiers {

    // MARK: - Known Terminal Bundle IDs

    /// Apple Terminal.app
    static let terminal = "com.apple.Terminal"

    /// iTerm2
    static let iTerm2 = "com.googlecode.iterm2"

    /// Alacritty
    static let alacritty = "org.alacritty"

    /// Warp
    static let warp = "dev.warp.Warp-Stable"

    /// Kitty
    static let kitty = "net.kovidgoyal.kitty"

    /// Hyper
    static let hyper = "co.zeit.hyper"

    // MARK: - Collection

    /// All known terminal bundle IDs.
    static var allTerminals: [String] {
        [terminal, iTerm2, alacritty, warp, kitty, hyper]
    }
}
