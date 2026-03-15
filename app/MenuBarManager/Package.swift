// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MenuBarManager",
            path: "MenuBarManager",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "MenuBarManager/Bridging/BridgingHeader.h"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
