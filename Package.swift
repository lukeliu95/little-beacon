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
    targets: [
        .target(name: "LittleBeaconCore"),
        .executableTarget(
            name: "LittleBeaconApp",
            dependencies: ["LittleBeaconCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LittleBeaconCoreTests",
            dependencies: ["LittleBeaconCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
