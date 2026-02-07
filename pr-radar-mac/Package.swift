// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRRadar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "MacApp",
            targets: ["MacApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "PRRadarMacSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/sdks/PRRadarMacSDK"
        ),
        .executableTarget(
            name: "MacApp",
            dependencies: [
                .target(name: "PRRadarMacSDK"),
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/apps/MacApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
    ]
)
