import SwiftUI
import XCTest
@testable import CenitDesign

/// El dato y el cuerpo crecen con la letra del sistema. El número de un anillo no.
///
/// En la Mac de integración `ImageRenderer` no aplica la letra grande: un alto de 22
/// se midió 22 tanto en `.large` como en `.accessibility5` (igual el de 13). Por eso
/// esta prueba ata el cableado, que es lo que esa Mac sí puede verificar. El tamaño
/// real de la letra en el iPhone no se fotografía aquí.
final class LetraGrandeTests: XCTestCase {

    func test_datoYCuerpoEstanAnclados_anilloEsFijo() {
        XCTAssertEqual(
            LiquidType.valorL,
            InstrumentoType.groteskNumber(22, relativeTo: .title3),
            "el dato de Hoy tiene que crecer con la letra del sistema"
        )
        XCTAssertEqual(
            LiquidType.cuerpo,
            Font.system(.footnote),
            "el cuerpo de Entrenar tiene que crecer con la letra del sistema"
        )
        XCTAssertEqual(
            CenitFont.number(54, weight: .bold),
            Font.system(size: 54, weight: .bold, design: .default).monospacedDigit(),
            "el número del anillo se queda fijo"
        )
    }
}
