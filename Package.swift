// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskPals",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DeskPals", path: "Sources/DeskPals")
    ]
)
