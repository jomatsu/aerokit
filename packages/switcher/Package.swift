// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AeroSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AeroSwitcher", targets: ["AeroSwitcher"])
    ],
    targets: [
        .target(
            name: "AeroSwitcherCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "AeroSwitcher",
            dependencies: ["AeroSwitcherCore"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "AeroSwitcherTests",
            dependencies: ["AeroSwitcherCore"]
        )
    ]
)
