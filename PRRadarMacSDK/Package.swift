// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRRadarMacSDK",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PRRadarMacSDK",
            targets: ["PRRadarMacSDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "PRRadarMacSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
            ]
        ),
        .executableTarget(
            name: "prradar-cli",
            dependencies: [
                "PRRadarMacSDK",
                .product(name: "CLISDK", package: "SwiftCLI"),
            ]
        ),
    ]
)
