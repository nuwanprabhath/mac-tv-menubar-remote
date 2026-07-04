// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-tv-menubar-remote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacTVRemote",
            path: "Sources/MacTVRemote",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
