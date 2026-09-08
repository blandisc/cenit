// swift-tools-version: 5.9
import PackageDescription

// StrandImport — la puerta de entrada de datos ajenos: el export de Apple Health y los CSV de
// fuerza. Lee un archivo que la persona eligió, lo normaliza y lo escribe en CenitStore.
//
// ZIPFoundation es la única dependencia externa y sirve para abrir el `.zip` del export en
// disco; no descarga nada. El paquete sigue sin hacer una sola llamada de red.

/// Concurrencia estricta en el objetivo y en sus pruebas, escrita una sola vez.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// Descompresión del export, en disco.
private let zip = Target.Dependency.product(name: "ZIPFoundation", package: "ZIPFoundation")

/// El importador. `.process` deja que SwiftPM optimice los recursos del objetivo.
private let importador = Target.target(name: "StrandImport",
                                       dependencies: ["CenitStore", "StrandTraining", zip],
                                       resources: [.process("Resources")],
                                       swiftSettings: concurrenciaEstricta)

/// Las pruebas cargan exports de muestra tal cual, así que van con `.copy`: un `.process` podría
/// tocarlos y lo que se prueba es justo el archivo crudo.
private let pruebas = Target.testTarget(name: "StrandImportTests",
                                        dependencies: ["StrandImport", "CenitStore"],
                                        resources: [.copy("Resources")],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "StrandImport",
                      platforms: [.iOS(.v16), .macOS(.v13)],
                      products: [.library(name: "StrandImport", type: .static, targets: ["StrandImport"])],
                      dependencies: [
                          .package(path: "../CenitStore"),
                          .package(path: "../StrandTraining"),
                          .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
                      ],
                      targets: [importador, pruebas])
