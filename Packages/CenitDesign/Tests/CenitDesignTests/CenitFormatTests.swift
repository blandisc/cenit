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
}
