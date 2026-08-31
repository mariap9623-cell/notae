// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notae",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Notae",
            path: "Sources/Notae",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
