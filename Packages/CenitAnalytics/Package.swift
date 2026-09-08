// swift-tools-version: 5.9
import PackageDescription

// CenitAnalytics — la matemática de Cénit: preparación, esfuerzo, HRV, sueño, ciclo, tendencias.
//
// Sin base de datos y sin UI a propósito: entran valores, salen valores, y todo se prueba con
// `swift test` sin simulador, sin HealthKit y sin reloj. Depende sólo de dos hojas del grafo —
// el vocabulario de filas decodificadas y las formas del día resumido.

/// Concurrencia estricta en el objetivo y en sus pruebas, escrita una sola vez.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// Las hojas del grafo de las que cuelga la matemática.
private let vocabularios: [Target.Dependency] = ["BiometricStreams", "CenitModels"]

/// Los motores.
private let motores = Target.target(name: "CenitAnalytics",
                                    dependencies: vocabularios,
                                    swiftSettings: concurrenciaEstricta)

/// Las pruebas cargan dos rejas de «no se movió»: los números persistidos de esfuerzo y pulso, y
/// el proxy diario de estrés. Cada archivo graba lo que los motores respondieron para entradas
/// sintéticas fijas, y viaja como recurso plano para poder compararse bit a bit (FER-401).
private let pruebas = Target.testTarget(name: "CenitAnalyticsTests",
                                        dependencies: ["CenitAnalytics"] + vocabularios,
                                        resources: [
                                            .copy("Resources/effort-pulse-oracle.json"),
                                            .copy("Resources/daily-stress-oracle.json"),
                                        ],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "CenitAnalytics",
                      platforms: [.iOS(.v16), .macOS(.v13)],
                      products: [.library(name: "CenitAnalytics", type: .static, targets: ["CenitAnalytics"])],
                      dependencies: [.package(path: "../BiometricStreams"), .package(path: "../CenitModels")],
                      targets: [motores, pruebas])
