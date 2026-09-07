// swift-tools-version: 5.9
import PackageDescription

// CenitEnsenanza — el registro tipado de cómo se enseña cada funcionalidad: id estable, pestaña,
// requisitos declarativos y piezas (vacío/tip/hito/ayuda/novedad/gesto-con-botón). Guarda texto
// (claves del catálogo de la app) y rutas, nunca lógica ni estado (épico FER-428, L4/FER-430).
// Foundation-only y sin dependencias: corre en el fast loop y en ubuntu; `CenitDesign` nunca lo
// importa (`LiquidVacio` recibe `Text`, no claves).
let package = Package(
    name: "CenitEnsenanza",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CenitEnsenanza", type: .static, targets: ["CenitEnsenanza"])],
    targets: [
        .target(
            name: "CenitEnsenanza",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CenitEnsenanzaTests",
            dependencies: ["CenitEnsenanza"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
