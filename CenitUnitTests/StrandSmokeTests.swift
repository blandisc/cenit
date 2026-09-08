import XCTest
@testable import Cenit

/// Prueba de humo del objetivo de pruebas: si esto corre, la suite compiló y enlazó contra el app.
/// No verifica lógica; su valor es fallar ruidosamente cuando el objetivo deja de armarse.
final class StrandSmokeTests: XCTestCase {
    func testLaSuiteArrancaYEnlazaContraElApp() {
        XCTAssertNotNil(Bundle(for: StrandSmokeTests.self))
    }
}
