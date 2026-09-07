import XCTest

// MARK: - FER-267 · el índice no puede apuntar a un archivo muerto
//
// La tabla curada `catalogEntries` vive en `CenitDesignTokens/main.swift` (el patrón
// `Role`/`roles` ya establecido ahí) — no se importa aquí: un ejecutable con top-level code
// en `main.swift` corre ese código al enlazarse con el binario de tests, así que este test
// lee en cambio el `docs/design-system/CATALOGO.md` YA GENERADO (`swift run
// CenitDesignTokens`, vigilado por `design-tokens.yml`) y verifica que cada `archivo` de su
// índice de componentes exista de verdad bajo `Sources/CenitDesign/` — justo lo que mata un
// índice que enseña muertos, la razón de ser de este issue. La honestidad de
// `rol`/`cuándo usarlo`/`cuándo no` la cuida el review humano; esto solo cierra el hueco barato.

final class CatalogEntryArchivoExisteTests: XCTestCase {
    func test_cadaArchivoDelIndiceExiste() throws {
        let repoRoot = CatalogoIndice.repoRoot
        let sourcesRoot = repoRoot.appendingPathComponent("Packages/CenitDesign/Sources/CenitDesign")

        let archivos = CatalogoIndice.filas(try CatalogoIndice.texto()).map { CatalogoIndice.sinBackticks($0[3]) }
        XCTAssertFalse(archivos.isEmpty, "no se encontraron filas de índice en \(CatalogoIndice.url.path) — ¿cambió el formato de la tabla?")

        let fm = FileManager.default
        for archivo in archivos {
            // FER-280·1a: el índice ahora también lista piezas VIVAS de la capa app (SaveErrorToast,
            // HealthAlertBanner…) — sus rutas empiezan con `Cenit/` y se resuelven contra la raíz
            // del repo; el resto sigue viviendo bajo Sources/CenitDesign.
            let base = archivo.hasPrefix("Cenit/") ? repoRoot : sourcesRoot
            let path = base.appendingPathComponent(archivo).path
            XCTAssertTrue(fm.fileExists(atPath: path),
                          "el índice de CATALOGO.md apunta a `\(archivo)`, que no existe (raíz: \(base.lastPathComponent))")
        }
    }
}
