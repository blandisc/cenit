// swift-tools-version:5.9
import PackageDescription

// watchOS is part of the platform list so CenitWatch (the Apple Watch companion) can render the
// mirrored strength session with the exact same tokens. The package itself stays framework-neutral —
// no direct UIKit/AppKit import; platform bridges are gated behind `#if canImport(...)`.
let package = Package(
    name: "CenitDesign",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "CenitDesign", type: .static, targets: ["CenitDesign"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CenitDesign",
            // Space Grotesk (OFL) ships as bundled resources so the type voice renders fully offline,
            // registered at runtime via CoreText. The Ecosistema Metal shader also travels as a plain
            // resource and is compiled at runtime — SwiftPM 5.9 has no target-level `.metal` build step.
            resources: [.process("Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // `swift run CenitDesignTokens` regenerates docs/design-system/* straight from this target's
        // public tokens, so the docs can never silently drift from the code that ships.
        .executableTarget(
            name: "CenitDesignTokens",
            dependencies: ["CenitDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitDesignTests",
            dependencies: ["CenitDesign"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
