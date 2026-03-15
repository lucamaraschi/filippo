// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MenuBarManager",
            dependencies: ["TOMLKit"],
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
