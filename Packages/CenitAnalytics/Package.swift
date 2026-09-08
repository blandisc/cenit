// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CenitAnalytics",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "CenitAnalytics", type: .static, targets: ["CenitAnalytics"])],
    dependencies: [
        .package(path: "../BiometricStreams"),
        .package(path: "../CenitModels"),
    ],
    targets: [
        .target(
            name: "CenitAnalytics",
            dependencies: ["BiometricStreams", "CenitModels"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitAnalyticsTests",
            dependencies: [
                "CenitAnalytics",
                "CenitModels",
                "BiometricStreams",
            ],
            resources: [.copy("Resources/effort-pulse-oracle.json")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
