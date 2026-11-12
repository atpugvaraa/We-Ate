// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WeAte",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/KrishKrosh/OpenMultitouchSupport", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "WeAte",
            dependencies: [
                .product(name: "OpenMultitouchSupport", package: "OpenMultitouchSupport"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
