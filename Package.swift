// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CYBMediaHolder",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(
            name: "CYBMediaHolder",
            targets: ["CYBMediaHolder"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CYBMediaHolder",
            dependencies: [],
            exclude: ["Migration/README_Migration.md"]),
        .testTarget(
            name: "CYBMediaHolderTests",
            dependencies: ["CYBMediaHolder"]),
    ]
)
