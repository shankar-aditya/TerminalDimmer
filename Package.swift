// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerminalDimmer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TerminalDimmer",
            path: "TerminalDimmer",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
