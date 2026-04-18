// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacosMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacosMonitor",
            path: "Sources/MacosMonitor"
        )
    ]
)
