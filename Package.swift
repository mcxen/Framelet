// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Framelet",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Framelet", targets: ["Framelet"]),
        .executable(name: "FrameletUpdater", targets: ["FrameletUpdater"])
    ],
    targets: [
        .executableTarget(
            name: "Framelet",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(name: "FrameletUpdater"),
        .testTarget(
            name: "FrameletTests",
            dependencies: ["Framelet"]
        )
    ]
)
