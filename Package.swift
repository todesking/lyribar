// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lyribar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Lyribar",
            path: "Sources/Lyribar",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LyribarTests",
            dependencies: ["Lyribar"],
            path: "Tests/LyribarTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
