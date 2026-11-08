// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Stagehand",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "StagehandModel", targets: ["StagehandModel"]),
        .library(name: "StagehandScene", targets: ["StagehandScene"]),
        .library(name: "StagehandCapture", targets: ["StagehandCapture"]),
    ],
    targets: [
        .target(
            name: "StagehandModel",
            resources: [.process("Resources")]
        ),
        .target(name: "StagehandScene"),
        .target(
            name: "StagehandCapture",
            dependencies: ["StagehandModel", "StagehandScene"]
        ),
        .testTarget(
            name: "StagehandModelTests",
            dependencies: ["StagehandModel"]
        ),
        .testTarget(
            name: "StagehandCaptureTests",
            dependencies: ["StagehandCapture", "StagehandModel", "StagehandScene"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
