// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CenitImport",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "CenitImport", type: .static, targets: ["CenitImport"])],
    dependencies: [
        .package(path: "../CenitStore"),
        .package(path: "../CenitTraining"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "CenitImport",
            dependencies: [
                "CenitStore", "CenitTraining",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitImportTests",
            dependencies: ["CenitImport", "CenitStore"],
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
