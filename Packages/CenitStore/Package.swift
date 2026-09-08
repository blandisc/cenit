// swift-tools-version: 5.9
import PackageDescription

// CenitStore — el SQLite local de Cénit sobre GRDB: el esquema versionado, sus migraciones
// (sólo se agregan, nunca se editan) y los repositorios que la app consulta.
//
// Es el único paquete que toca disco. Habla el vocabulario de BiometricStreams y las formas de
// CenitModels, y conoce el dominio de fuerza de CenitTraining para poder guardarlo.

/// Concurrencia estricta en el objetivo y en sus pruebas, escrita una sola vez.
private let concurrenciaEstricta: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

/// GRDB es la única dependencia externa del paquete, y no habla por red: es SQLite en el disco.
private let grdb = Target.Dependency.product(name: "GRDB", package: "GRDB.swift")

/// El almacén. Los dos `.zlib` son los mapas de remapeo de identificadores que maneja la
/// migración v33 del catálogo de ejercicios (DEFLATE crudo, FER-923); viajan comprimidos porque
/// se leen una sola vez, al migrar.
private let almacen = Target.target(name: "CenitStore",
                                    dependencies: ["BiometricStreams", "CenitModels", "CenitTraining", grdb],
                                    resources: [
                                        .copy("Resources/exercise-id-remap.json.zlib"),
                                        .copy("Resources/legacy-exercise-data.json.zlib"),
                                    ],
                                    swiftSettings: concurrenciaEstricta)

/// Los dos recursos de prueba son la red de la migración única (FER-393): una base real migrada
/// por el código anterior, con su bitácora de 43 identificadores, y el volcado de su esquema.
private let pruebas = Target.testTarget(name: "CenitStoreTests",
                                        dependencies: ["CenitStore"],
                                        resources: [
                                            .copy("Resources/legacy-fixture.sqlite"),
                                            .copy("Resources/legacy-schema.sql"),
                                        ],
                                        swiftSettings: concurrenciaEstricta)

let package = Package(name: "CenitStore",
                      platforms: [.iOS(.v16), .macOS(.v13)],
                      products: [.library(name: "CenitStore", type: .static, targets: ["CenitStore"])],
                      dependencies: [
                          .package(path: "../BiometricStreams"),
                          .package(path: "../CenitModels"),
                          .package(path: "../CenitTraining"),
                          .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
                      ],
                      targets: [almacen, pruebas])
