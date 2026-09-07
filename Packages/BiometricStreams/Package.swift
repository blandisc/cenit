// swift-tools-version: 5.9
import PackageDescription

// BiometricStreams — el vocabulario neutro de las filas biométricas ya decodificadas
// (`HRSample`, `RRInterval`, `SkinTempSample`, `RespSample`, `GravitySample`, `Streams`) más
// `ParsedValue`.
//
// Es la RAÍZ del grafo de paquetes y por eso no depende de nada: sólo Foundation. Así la
// persistencia (CenitStore) y la matemática (StrandAnalytics) hablan el mismo idioma sin que
// ninguna de las dos tenga que depender de la otra (FER-993 · D2).

/// Concurrencia estricta en el objetivo y en sus pruebas, escrita una sola vez.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// El vocabulario en sí: puros tipos de valor, sin recursos y sin dependencias.
private let vocabulario = Target.target(name: "BiometricStreams",
                                        swiftSettings: concurrenciaEstricta)

private let pruebas = Target.testTarget(name: "BiometricStreamsTests",
                                        dependencies: ["BiometricStreams"],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "BiometricStreams",
                      platforms: [.iOS(.v16), .macOS(.v13)],
                      products: [.library(name: "BiometricStreams", type: .static, targets: ["BiometricStreams"])],
                      targets: [vocabulario, pruebas])
