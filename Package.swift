// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MinimalCapture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MinimalCapture",
            path: "Sources/MinimalCapture",
            swiftSettings: [
                // Everything in this app is UI-driven; opt out explicitly with `nonisolated`.
                .defaultIsolation(MainActor.self)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
