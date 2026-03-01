// swift-tools-version: 6.2

import PackageDescription

var products: [Product] = [
    .executable(
        name: "PRRadarMacCLI",
        targets: ["PRRadarMacCLI"]
    ),
]

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/gestrich/SwiftCLI.git", branch: "main"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0"),
]

#if !canImport(CryptoKit)
dependencies.append(
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
)
#endif

var targets: [Target] = [
    // SDK Layer
    .target(
        name: "ClaudeSDK",
        dependencies: [
            .product(name: "CLISDK", package: "SwiftCLI"),
            .target(name: "ConcurrencySDK"),
            .target(name: "EnvironmentSDK"),
        ],
        path: "Sources/sdks/ClaudeSDK"
    ),

    .target(
        name: "GitSDK",
        dependencies: [
            .product(name: "CLISDK", package: "SwiftCLI"),
        ],
        path: "Sources/sdks/GitSDK"
    ),

    .target(
        name: "GitHubSDK",
        dependencies: [
            .product(name: "OctoKit", package: "octokit.swift"),
        ],
        path: "Sources/sdks/GitHubSDK"
    ),

    .target(
        name: "KeychainSDK",
        path: "Sources/sdks/KeychainSDK"
    ),

    .target(
        name: "EnvironmentSDK",
        path: "Sources/sdks/EnvironmentSDK"
    ),

    .target(
        name: "ConcurrencySDK",
        path: "Sources/sdks/ConcurrencySDK"
    ),

    // Services Layer — Domain Models (Foundation-only, no other target deps)
    .target(
        name: "PRRadarModels",
        dependencies: {
            var deps: [Target.Dependency] = []
            #if !canImport(CryptoKit)
            deps.append(.product(name: "Crypto", package: "swift-crypto"))
            #endif
            return deps
        }(),
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
        dependencies: {
            var deps: [Target.Dependency] = [
                .target(name: "ClaudeSDK"),
                .target(name: "GitSDK"),
                .target(name: "GitHubSDK"),
                .target(name: "PRRadarConfigService"),
                .target(name: "PRRadarModels"),
                .target(name: "EnvironmentSDK"),
                .product(name: "CLISDK", package: "SwiftCLI"),
                .product(name: "OctoKit", package: "octokit.swift"),
            ]
            #if !canImport(CryptoKit)
            deps.append(.product(name: "Crypto", package: "swift-crypto"))
            #endif
            return deps
        }(),
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
            .target(name: "ClaudeSDK"),
            .target(name: "EnvironmentSDK"),
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
]

#if os(macOS)
products.append(
    .library(
        name: "MacApp",
        targets: ["MacApp"]
    )
)

dependencies.append(contentsOf: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
])

targets.append(contentsOf: [
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

    .testTarget(
        name: "MacAppTests",
        dependencies: [
            .target(name: "MacApp"),
            .target(name: "PRRadarConfigService"),
            .target(name: "PRReviewFeature"),
        ],
        path: "Tests/MacAppTests"
    ),
])
#endif

let package = Package(
    name: "PRRadar",
    platforms: [
        .macOS(.v15)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
