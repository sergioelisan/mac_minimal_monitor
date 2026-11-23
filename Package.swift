// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ResourcesMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ResourcesMonitor", path: "Sources/ResourcesMonitor")
    ]
)
