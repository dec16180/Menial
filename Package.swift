// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Menial",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Menial",
            path: "Sources/Menial"
        )
    ]
)
