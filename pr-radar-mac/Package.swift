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
        // SDK Layer
        .target(
            name: "PRRadarMacSDK",
            dependencies: [
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/sdks/PRRadarMacSDK"
        ),

        // Services Layer — Configuration (Foundation-only, no other target deps)
        .target(
            name: "PRRadarConfigService",
            path: "Sources/services/PRRadarConfigService"
        ),

        // Services Layer — CLI Execution
        .target(
            name: "PRRadarCLIService",
            dependencies: [
                .target(name: "PRRadarMacSDK"),
                .target(name: "PRRadarConfigService"),
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
                .target(name: "PRRadarMacSDK"),
            ],
            path: "Sources/features/PRReviewFeature"
        ),

        // App Layer
        .executableTarget(
            name: "MacApp",
            dependencies: [
                .target(name: "PRReviewFeature"),
                .target(name: "PRRadarConfigService"),
                .product(name: "CLISDK", package: "SwiftCLI"),
            ],
            path: "Sources/apps/MacApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
    ]
)
