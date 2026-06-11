// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "AeroKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AeroKit", targets: ["AeroKit"])
    ],
    targets: [
        .target(
            name: "AeroKitCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SwitcherFeature",
            dependencies: ["AeroKitCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ExposeFeature",
            dependencies: ["AeroKitCore"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "AeroKit",
            dependencies: ["AeroKitCore", "SwitcherFeature", "ExposeFeature"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AeroKitTests",
            dependencies: ["AeroKitCore", "SwitcherFeature", "ExposeFeature"]
        )
    ]
)
