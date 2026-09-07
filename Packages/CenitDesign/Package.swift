// swift-tools-version:5.9
import PackageDescription
// CenitDesign — el sistema visual de Cénit, empaquetado aparte de la app para que las mismas fichas
// de color, tipo y movimiento pinten iPhone, Apple Watch y los widgets sin copiarse a mano.
//
// Cero dependencias externas: nada que descargar, nada que llamar por red.
//
// watchOS entra en la lista de plataformas porque CenitWatch espeja la sesión de fuerza con estas
// mismas fichas. El paquete no importa UIKit/AppKit de frente; los puentes de plataforma van
// siempre detrás de `#if canImport(...)`.

/// Concurrencia estricta en los tres objetivos, sin repetir el arreglo tres veces.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// El sistema en sí. Space Grotesk (bajo OFL) y el shader Metal del Ecosistema viajan como recursos
/// planos: la tipografía se registra en CoreText al arrancar y el shader se compila en tiempo de
/// ejecución, porque SwiftPM 5.9 no sabe compilar un `.metal` propio del objetivo.
private let sistema = Target.target(name: "CenitDesign",
                                    resources: [.process("Resources")],
                                    swiftSettings: concurrenciaEstricta)

/// `swift run CenitDesignTokens` reescribe `docs/design-system/*` leyendo las fichas públicas del
/// objetivo de arriba, para que la documentación no pueda desviarse del código que se envía.
private let generadorDeDocs = Target.executableTarget(name: "CenitDesignTokens",
                                                      dependencies: ["CenitDesign"],
                                                      swiftSettings: concurrenciaEstricta)

private let pruebas = Target.testTarget(name: "CenitDesignTests",
                                        dependencies: ["CenitDesign"],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "CenitDesign",
                      platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
                      products: [.library(name: "CenitDesign", type: .static, targets: ["CenitDesign"])],
                      targets: [sistema, generadorDeDocs, pruebas])
