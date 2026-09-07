import XCTest
@testable import CenitDesign

// MARK: - FER-430 · `LiquidVacio` está en el catálogo con su rol y su archivo
//
// Que el archivo del índice exista lo cubre `CatalogEntryArchivoExisteTests` para TODAS las filas;
// aquí solo se fija lo propio de este componente (criterio de aceptación del issue: «aparece en
// CATALOGO.md»). Sus tres estados viven en el `#Preview` del archivo.

final class LiquidVacioTests: XCTestCase {
    func test_estaEnElCatalogo() throws {
        let fila = CatalogoIndice.filas(try CatalogoIndice.texto()).first { $0[2] == "`LiquidVacio`" }
        let cols = try XCTUnwrap(fila, "CATALOGO.md no tiene fila para `LiquidVacio` — ¿falta `swift run CenitDesignTokens`?")
        XCTAssertEqual(cols[1], "Estado vacío que enseña", "el rol del catálogo es el del issue")
        XCTAssertEqual(CatalogoIndice.sinBackticks(cols[3]), "LiquidGlass/LiquidVacio.swift")
    }
}
