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
        ),
        .executable(
            name: "PRRadarMacCLI",
            targets: ["PRRadarMacCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // SDK Layer
        .target(
            name: "PRRadarMacSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/sdks/PRRadarMacSDK"
        ),

        // Services Layer — Domain Models (Foundation-only, no other target deps)
        .target(
            name: "PRRadarModels",
            path: "Sources/services/PRRadarModels"
        ),

        // Services Layer — Configuration
        .target(
            name: "PRRadarConfigService",
            dependencies: [
                .target(name: "PRRadarModels"),
            ],
            path: "Sources/services/PRRadarConfigService"
        ),

        // Services Layer — CLI Execution
        .target(
            name: "PRRadarCLIService",
            dependencies: [
                .target(name: "PRRadarMacSDK"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/services/PRRadarCLIService"
        ),

        // Features Layer
        .target(
            name: "PRReviewFeature",
            dependencies: [
                .target(name: "PRRadarCLIService"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
            ],
            path: "Sources/features/PRReviewFeature"
        ),

        // App Layer
        .executableTarget(
            name: "MacApp",
            dependencies: [
                .target(name: "PRReviewFeature"),
                .target(name: "PRRadarCLIService"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
            ],
            path: "Sources/apps/MacApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),

        // CLI App Layer
        .executableTarget(
            name: "PRRadarMacCLI",
            dependencies: [
                .target(name: "PRReviewFeature"),
                .target(name: "PRRadarCLIService"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/apps/MacCLI"
        ),

        // Tests
        .testTarget(
            name: "PRRadarModelsTests",
            dependencies: [
                .target(name: "PRRadarModels"),
                .target(name: "PRRadarConfigService"),
            ],
            path: "Tests/PRRadarModelsTests",
            resources: [
                .copy("EffectiveDiffFixtures"),
            ]
        ),
    ]
)
