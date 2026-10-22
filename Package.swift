// swift-tools-version: 6.0
// Package.swift: two targets — a portable core tested on Linux and the iOS app shell.
import PackageDescription

let package = Package(
    name: "Monochrome",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)],
    products: [
        .library(name: "Monochrome", targets: ["Monochrome"]),
    ],
    targets: [
        .target(name: "MonochromeCore"),
        .target(name: "Monochrome", dependencies: ["MonochromeCore"]),
        .testTarget(name: "MonochromeCoreTests", dependencies: ["MonochromeCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
