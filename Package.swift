// swift-tools-version:5.10
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Richard Kaufmann
import PackageDescription

let package = Package(
    name: "TapHand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TapHand", path: "Sources/TapHand")
    ]
)
