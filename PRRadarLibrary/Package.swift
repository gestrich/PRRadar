// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRRadar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
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
        .package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/square/Valet.git", from: "5.0.0"),
    ],
    targets: [
        // SDK Layer
        .target(
            name: "PRRadarMacSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
                .product(name: "OctoKit", package: "octokit.swift"),
            ],
            path: "Sources/sdks/PRRadarMacSDK"
        ),

        .target(
            name: "KeychainSDK",
            dependencies: [
                .product(name: "Valet", package: "Valet"),
            ],
            path: "Sources/sdks/KeychainSDK"
        ),

        .target(
            name: "EnvironmentSDK",
            path: "Sources/sdks/EnvironmentSDK"
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
                .target(name: "KeychainSDK"),
                .target(name: "EnvironmentSDK"),
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
                .target(name: "EnvironmentSDK"),
                .product(name: "CLISDK", package: "SwiftCLI"),
                .product(name: "OctoKit", package: "octokit.swift"),
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
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/features/PRReviewFeature"
        ),

        // App Layer
        .target(
            name: "MacApp",
            dependencies: [
                .target(name: "PRReviewFeature"),
                .target(name: "PRRadarCLIService"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/apps/MacApp"
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
                .target(name: "PRRadarCLIService"),
                .target(name: "PRReviewFeature"),
                .target(name: "KeychainSDK"),
            ],
            path: "Tests/PRRadarModelsTests",
            resources: [
                .copy("EffectiveDiffFixtures"),
            ]
        ),

        .testTarget(
            name: "MacAppTests",
            dependencies: [
                .target(name: "MacApp"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRReviewFeature"),
            ],
            path: "Tests/MacAppTests"
        ),
    ]
)
