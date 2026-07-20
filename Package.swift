// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LittleBeacon",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LittleBeaconCore", targets: ["LittleBeaconCore"]),
        .executable(name: "LittleBeacon", targets: ["LittleBeaconApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "LittleBeaconCore"),
        .executableTarget(
            name: "LittleBeaconApp",
            dependencies: [
                "LittleBeaconCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "LittleBeaconCoreTests",
            dependencies: ["LittleBeaconCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
