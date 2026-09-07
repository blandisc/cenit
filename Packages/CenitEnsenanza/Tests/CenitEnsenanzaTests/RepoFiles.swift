import Foundation

// MARK: - Sube desde el test hasta la raíz del repo (mismo precedente que
// `Packages/CenitDesign/Tests/CenitDesignTests/CatalogEntryArchivoExisteTests.swift`)
//
// Algunos tests de `RegistroTests` leen archivos del repo que el registro referencia
// (`CHANGELOG.md`, `Cenit/Resources/Localizable.xcstrings`) para verificar que sus claves de
// verdad existen — no basta con que el Swift compile, tienen que apuntar a algo real.

enum RepoFiles {
    /// `Tests/CenitEnsenanzaTests/<esteArchivo>.swift` → sube a la raíz del repo.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../Tests/CenitEnsenanzaTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../CenitEnsenanza (raíz del paquete)
            .deletingLastPathComponent() // .../Packages
            .deletingLastPathComponent() // raíz del repo
    }

    static func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Para lo que se consume como JSON: sin pasar por `String` (el catálogo pesa ~2 MB).
    static func readData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent(relativePath))
    }
}
