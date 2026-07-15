// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macos-verbs",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "verbs",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/verbs"
        ),
        // warden — the mediation spine (Warden epic G0/G1). No external deps:
        // an MCP stdio proxy that governs `verbs` and records provenance.
        .executableTarget(
            name: "warden",
            path: "Sources/warden"
        ),
    ]
)
