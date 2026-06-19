// swift-tools-version: 5.9
import PackageDescription

// Swift 5 모드(strict concurrency 회피) — PortKiller 와 동일한 ad-hoc 빌드 정책.
let package = Package(
    name: "DynamicLake",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicLake",
            path: "Sources"
        ),
    ]
)
