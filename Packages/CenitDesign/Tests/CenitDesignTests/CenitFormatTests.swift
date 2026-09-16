import XCTest
@testable import CenitDesign

/// FER-466: los formateadores compartidos de display NUNCA deben trapear. `Int(v.rounded())` es un
/// trap fatal con un `Double` no-finito (NaN/±Inf) o finito pero fuera del rango de `Int` (magnitud
/// enorme). El camino guardado (`groupedInt`/`int`/`decimal`) devuelve «—» ante un dato malo.
final class CenitFormatTests: XCTestCase {

    func testGroupedIntNormalValues() {
        XCTAssertEqual(CenitFormat.groupedInt(12345), "12,345")
        XCTAssertEqual(CenitFormat.groupedInt(0), "0")
        XCTAssertEqual(CenitFormat.groupedInt(-42), "-42")
    }

    func testGroupedIntRejectsNonFiniteAndOverflow() {
        XCTAssertEqual(CenitFormat.groupedInt(.nan), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.groupedInt(.infinity), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.groupedInt(-.infinity), CenitFormat.emptyDato)
        // Finito pero > Int.max: `Int(rounded())` trapearía; el helper lo caza por magnitud.
        XCTAssertEqual(CenitFormat.groupedInt(1e19), CenitFormat.emptyDato)
    }

    func testIntGuarded() {
        XCTAssertEqual(CenitFormat.int(176.4), "176")
        XCTAssertEqual(CenitFormat.int(176.6), "177")
        XCTAssertEqual(CenitFormat.int(.nan), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.int(1e19), CenitFormat.emptyDato)
    }

    func testDecimalGuarded() {
        XCTAssertEqual(CenitFormat.decimal(36.63, places: 1), "36.6")
        XCTAssertEqual(CenitFormat.decimal(5, places: 0), "5")
        XCTAssertEqual(CenitFormat.decimal(.nan, places: 1), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.decimal(.infinity, places: 2), CenitFormat.emptyDato)
    }

    // MARK: - deltaPercent (FER-500 · C2) — el Δ% con signo, localizado, guardado

    private let mx = Locale(identifier: "es_MX")

    func testDeltaPercentSignosYCero() {
        XCTAssertEqual(CenitFormat.deltaPercent(12, locale: mx), "+12%")
        XCTAssertEqual(CenitFormat.deltaPercent(-12, locale: mx), "\u{2212}12%")
        XCTAssertEqual(CenitFormat.deltaPercent(0, locale: mx), "0%", "plano no lleva signo")
        XCTAssertEqual(CenitFormat.deltaPercent(-0.0, locale: mx), "0%", "«−0%» jamás")
    }

    func testDeltaPercentMenosRealNuncaGuion() {
        let texto = CenitFormat.deltaPercent(-7, locale: mx)
        XCTAssertTrue(texto.contains(CenitFormat.menosReal))
        XCTAssertFalse(texto.contains("-"), "el guion ASCII es la deriva que mata FER-500")
        XCTAssertEqual(CenitFormat.menosReal, "\u{2212}")
    }

    func testDeltaPercentRedondeoEscolarYDecimales() {
        // Escolar como `.rounded()` en las pantallas (13), no el bancario del formateador (12).
        XCTAssertEqual(CenitFormat.deltaPercent(12.5, locale: mx), "+13%")
        XCTAssertEqual(CenitFormat.deltaPercent(0.4, locale: mx), "0%")
        XCTAssertEqual(CenitFormat.deltaPercent(-0.4, locale: mx), "0%")
        XCTAssertEqual(CenitFormat.deltaPercent(7.5, places: 1, locale: mx), "+7.5%")
        XCTAssertEqual(CenitFormat.deltaPercent(7, places: 1, locale: mx), "+7.0%", "decimales fijos, como `decimal`")
        XCTAssertEqual(CenitFormat.deltaPercent(-0.04, places: 1, locale: mx), "0.0%")
        XCTAssertEqual(CenitFormat.deltaPercent(-1234.5, locale: mx), "\u{2212}1,235%")
    }

    func testDeltaPercentLocalizado() {
        XCTAssertEqual(CenitFormat.deltaPercent(12, locale: Locale(identifier: "en_US")), "+12%")
        // es-ES / de-DE: coma decimal y un espacio (fino o no, lo decide ICU) antes del «%».
        let es = CenitFormat.deltaPercent(7.5, places: 1, locale: Locale(identifier: "es_ES"))
        XCTAssertTrue(es.hasPrefix("+7,5"), es)
        XCTAssertTrue(es.hasSuffix("%"), es)
        XCTAssertEqual(es.dropLast().last?.isWhitespace, true, es)
        let de = CenitFormat.deltaPercent(-12, locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(de.hasPrefix("\u{2212}12"), de)
        XCTAssertEqual(de.dropLast().last?.isWhitespace, true, de)
    }

    func testDeltaPercentRejectsNonFiniteAndOverflow() {
        XCTAssertEqual(CenitFormat.deltaPercent(.nan), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.deltaPercent(.infinity), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.deltaPercent(-.infinity), CenitFormat.emptyDato)
        XCTAssertEqual(CenitFormat.deltaPercent(1e19), CenitFormat.emptyDato)
    }
}
