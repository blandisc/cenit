import XCTest
import SwiftUI
@testable import CenitDesign

// MARK: - FER-430 · `LiquidVacio` existe, está en el catálogo y su archivo es el que dice
//
// Mismo patrón que `CatalogEntryArchivoExisteTests`: se lee el `CATALOGO.md` YA GENERADO
// (`swift run CenitDesignTokens`) y se verifica la fila del componente — que el índice lo
// enseñe y apunte al archivo vivo. Criterio de aceptación del issue: «`LiquidVacio` existe en
// `CenitDesign` con `#Preview` de sus tres partes y aparece en CATALOGO.md».

final class LiquidVacioTests: XCTestCase {
    /// `Tests/CenitDesignTests/<esteArchivo>.swift` → sube a la raíz del repo.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../Tests/CenitDesignTests
            .deletingLastPathComponent() // .../Tests
            .deletingLastPathComponent() // .../CenitDesign (raíz del paquete)
            .deletingLastPathComponent() // .../Packages
            .deletingLastPathComponent() // raíz del repo
    }

    func test_estaEnElCatalogoYSuArchivoExiste() throws {
        let catalogoURL = repoRoot.appendingPathComponent("docs/design-system/CATALOGO.md")
        let catalogo = try String(contentsOf: catalogoURL, encoding: .utf8)

        // Fila del índice: `| Rol | \`símbolo\` | \`archivo\` | cuándo usarlo | cuándo no |`.
        let fila = catalogo.split(separator: "\n").first { line in
            let cols = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return cols.count == 7 && cols[2] == "`LiquidVacio`"
        }
        let filaVacio = try XCTUnwrap(fila, "CATALOGO.md no tiene fila para `LiquidVacio` — ¿falta `swift run CenitDesignTokens`?")

        let cols = filaVacio.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(cols[1], "Estado vacío que enseña", "el rol del catálogo es el del issue")
        let archivo = cols[3].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        XCTAssertEqual(archivo, "LiquidGlass/LiquidVacio.swift")

        let path = repoRoot
            .appendingPathComponent("Packages/CenitDesign/Sources/CenitDesign")
            .appendingPathComponent(archivo).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "el índice apunta a `\(archivo)`, que no existe")
    }

    @MainActor
    func test_exists_asPublicAPI_conSusTresEstados() {
        // Solo texto (con ruta).
        let _: any View = LiquidVacio(
            simbolo: "trophy",
            queEs: Text(verbatim: "Aún no tienes marcas"),
            comoSeLlena: Text(verbatim: "Cuando registres una serie, tu mejor marca aparece aquí."),
            salida: .dondeVive(Text(verbatim: "Vive en Entrenar › Progreso")))
        // Con cuenta.
        let _: any View = LiquidVacio(
            queEs: Text(verbatim: "Tu sueño todavía no tiene base"),
            comoSeLlena: Text(verbatim: "Cénit necesita varias noches con el reloj puesto."),
            cuenta: Text(verbatim: "Faltan 3 noches"))
        // Con acción.
        var tocado = false
        let _: any View = LiquidVacio(
            simbolo: "clock.arrow.circlepath",
            queEs: Text(verbatim: "Aún no hay entrenamientos"),
            comoSeLlena: Text(verbatim: "Cuando termines una sesión de fuerza, aparece aquí."),
            salida: .accion(etiqueta: Text(verbatim: "Importar historial"),
                            simbolo: "square.and.arrow.down",
                            handler: { tocado = true }))
        XCTAssertFalse(tocado, "construir la vista no dispara el handler")
    }
}
