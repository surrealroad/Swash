// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacAppKitExtras",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MacAppKitExtras", targets: ["MacAppKitExtras"]),
    ],
    targets: [
        .target(
            name: "MacAppKitExtras",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacAppKitExtrasTests",
            dependencies: ["MacAppKitExtras"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
