// swift-tools-version:6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SimplePing",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(
            name: "SimplePing",
            targets: ["SimplePing"])
    ],
    targets: [
        .target(
            name: "SimplePing"
        )
    ],
    swiftLanguageModes: [.v6]
)
