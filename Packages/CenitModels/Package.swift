// swift-tools-version: 5.9
import PackageDescription

// CenitModels — the shared vocabulary of daily metric value types (DailyMetric,
// CachedSleepSession, DietMealStatus). Foundation-only and dependency-free BY DESIGN: it is a
// leaf of the package graph so persistence (CenitStore) and math (CenitAnalytics) can speak
// these shapes WITHOUT one package owning the types the other consumes. Moved from CenitStore
// (plan 2026-07-20 · L3-C1a).
let package = Package(
    name: "CenitModels",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CenitModels", type: .static, targets: ["CenitModels"])],
    targets: [
        .target(
            name: "CenitModels",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitModelsTests",
            dependencies: ["CenitModels"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
