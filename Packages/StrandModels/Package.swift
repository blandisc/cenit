// swift-tools-version: 5.9
import PackageDescription

// StrandModels — las formas compartidas del día ya resumido (`DailyMetric`,
// `CachedSleepSession`, `DietMealStatus`).
//
// Es una HOJA del grafo, sin dependencias y sólo con Foundation, a propósito: la persistencia
// (CenitStore) y la matemática (StrandAnalytics) necesitan los mismos tipos, y ninguna de las dos
// debe ser dueña de los tipos que consume la otra. Salieron de CenitStore en el plan del
// 2026-07-20 · L3-C1a.

/// Concurrencia estricta en el objetivo y en sus pruebas, escrita una sola vez.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// Los tipos en sí: valores `Codable`/`Sendable`, sin recursos y sin dependencias.
private let formas = Target.target(name: "StrandModels",
                                   swiftSettings: concurrenciaEstricta)

private let pruebas = Target.testTarget(name: "StrandModelsTests",
                                        dependencies: ["StrandModels"],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "StrandModels",
                      platforms: [.iOS(.v16), .macOS(.v13)],
                      products: [.library(name: "StrandModels", type: .static, targets: ["StrandModels"])],
                      targets: [formas, pruebas])
