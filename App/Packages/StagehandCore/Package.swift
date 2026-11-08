// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StagehandCore",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    products: [
        .library(name: "StagehandCore", targets: ["StagehandCore"]),
    ],
    dependencies: [
        .package(name: "Stagehand", path: "../../.."),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "StagehandCore",
            dependencies: [
                .product(name: "StagehandModel", package: "Stagehand"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),
        .testTarget(
            name: "StagehandCoreTests",
            dependencies: [
                "StagehandCore",
                .product(name: "StagehandModel", package: "Stagehand"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
            resources: [.copy("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
