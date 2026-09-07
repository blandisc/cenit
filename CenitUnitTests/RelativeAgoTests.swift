import XCTest
@testable import Cenit

/// Fija los cubos de `relativeAgo`, la función pura detrás de la línea «Historial sincronizado
/// hace N».
///
/// Las expectativas se comparan contra la **misma plantilla `String(localized:)`** que usa la
/// función, no contra un literal en inglés: el texto vive en el catálogo de cadenas y el app corre
/// en español, así que compararlo contra inglés dejaría la prueba verde en el idioma equivocado.
final class RelativeAgoTests: XCTestCase {

    /// Un instante fijo cualquiera; lo único que importa es la resta.
    private let ahora: TimeInterval = 1_781_000_000

    /// Cómo se lee un sello de tiempo de hace `segundos`.
    private func hace(_ segundos: TimeInterval) -> String {
        relativeAgo(ahora - segundos, now: ahora)
    }

    private var justoAhora: String { String(localized: "just now") }

    func testDebajoDeUnMinutoNoSeCuentan() {
        XCTAssertEqual(hace(0), justoAhora)
        XCTAssertEqual(hace(59), justoAhora)
    }

    func testMinutosConDivisionEntera() {
        XCTAssertEqual(hace(60), String(localized: "\(1) min ago"))
        XCTAssertEqual(hace(5 * 60), String(localized: "\(5) min ago"))
        XCTAssertEqual(hace(59 * 60), String(localized: "\(59) min ago"))
    }

    func testHoras() {
        XCTAssertEqual(hace(3_600), String(localized: "\(1) h ago"))
        XCTAssertEqual(hace(23 * 3_600), String(localized: "\(23) h ago"))
    }

    func testDias() {
        XCTAssertEqual(hace(86_400), String(localized: "\(1) d ago"))
        XCTAssertEqual(hace(3 * 86_400), String(localized: "\(3) d ago"))
    }

    func testUnSelloEnElFuturoNuncaSePintaEnNegativo() {
        // Un reloj desfasado puede dejar la última sincronización adelantada respecto al teléfono.
        XCTAssertEqual(relativeAgo(ahora + 500, now: ahora), justoAhora)
    }
}
