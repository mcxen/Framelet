// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Framelet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Framelet", targets: ["Framelet"])
    ],
    targets: [
        .executableTarget(
            name: "Framelet",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FrameletTests",
            dependencies: ["Framelet"]
        )
    ]
)
