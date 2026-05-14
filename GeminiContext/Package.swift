// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GeminiContext",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GeminiContext",
            path: "Sources/GeminiContext",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
