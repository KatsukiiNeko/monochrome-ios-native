// swift-tools-version: 6.0
// Package.swift: two targets — a portable core tested on Linux and the iOS app shell.
import PackageDescription

let package = Package(
    name: "Monochrome",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Monochrome", targets: ["Monochrome"]),
    ],
    targets: [
        .target(name: "MonochromeCore"),
        .target(name: "Monochrome", dependencies: ["MonochromeCore"]),
        .testTarget(name: "MonochromeCoreTests", dependencies: ["MonochromeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
