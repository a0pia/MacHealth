// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacHealth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacHealth",
            path: "Sources/MacHealth",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
