// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TodoBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TodoBar",
            path: "Sources/TodoBar"
        )
    ]
)
