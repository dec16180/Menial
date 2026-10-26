// swift-tools-version:5.9
// SPDX-FileCopyrightText: 2026 Christopher De Nicolo
//
// SPDX-License-Identifier: MIT

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
