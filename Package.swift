// swift-tools-version: 6.0
// Package.swift: two targets — a portable core tested on Linux and the iOS app shell.
import PackageDescription

let package = Package(
    name: "Monochrome",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)],
    products: [
        .library(name: "Monochrome", targets: ["Monochrome"]),
        .library(name: "MonochromeWidget", targets: ["MonochromeWidget"]),
    ],
    targets: [
        .target(name: "MonochromeCore"),
        .target(name: "Monochrome", dependencies: ["MonochromeCore"], linkerSettings: [
            .unsafeFlags(["-Wl,-headerpad,0x1000"]),
        ]),
        .target(name: "MonochromeWidget", dependencies: ["MonochromeCore"], linkerSettings: [
            .unsafeFlags(["-Wl,-headerpad,0x1000"]),
        ]),
        .testTarget(name: "MonochromeCoreTests", dependencies: ["MonochromeCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
