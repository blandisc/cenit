import XCTest
import SwiftUI
import TipKit
@testable import CenitDesign

/// FER-436 · la tarjeta de una vez: contrato del estilo (rótulo inyectable, tono/régimen por
/// defecto) y su receta en tokens — cero literales de diseño salvo el chevron de fila.
final class LiquidUnaVezTests: XCTestCase {

    /// `TipViewStyle` es `@MainActor`: el `init` y sus propiedades también.
    @MainActor
    func test_default_esNeutroSobrio() {
        let estilo = LiquidUnaVezTipStyle()
        XCTAssertEqual(estilo.tono, .neutro, "sin tono la tarjeta es neutra: el color vive en la puerta")
        XCTAssertEqual(estilo.regimen, .sobrio, "el régimen por defecto del sistema es sobrio")
    }

    @MainActor
    func test_exists_asPublicTipViewStyle_conRotuloInyectable() {
        let estilo = LiquidUnaVezTipStyle(tono: .verde, regimen: .mosaico,
                                          entendido: Text(verbatim: "Entendido"))
        let _: any TipViewStyle = estilo
        XCTAssertEqual(estilo.tono, .verde)
        XCTAssertEqual(estilo.regimen, .mosaico)
    }

    func test_receta_enTokens() {
        XCTAssertEqual(LiquidUnaVezMetrics.paddingArriba, LiquidSpace.s400)
        XCTAssertEqual(LiquidUnaVezMetrics.paddingLados, LiquidSpace.s400)
        XCTAssertEqual(LiquidUnaVezMetrics.paddingAbajo, LiquidSpace.s200)
        XCTAssertEqual(LiquidUnaVezMetrics.kickerACuerpo, LiquidSpace.s150)
        XCTAssertEqual(LiquidUnaVezMetrics.cuerpoAAcciones, LiquidSpace.s200)
        XCTAssertEqual(LiquidUnaVezMetrics.puertaGap, LiquidSpace.s150)
        XCTAssertEqual(LiquidUnaVezMetrics.accionesGap, LiquidSpace.s400)
        XCTAssertEqual(LiquidUnaVezMetrics.apiladoGap, 0, "apiladas no llevan gap: cada una ya mide 44")
        XCTAssertEqual(LiquidUnaVezMetrics.accionAltura, LiquidControl.hitTarget,
                       "cada acción mide al menos el objetivo táctil HIG")
        XCTAssertEqual(LiquidUnaVezMetrics.chevron, 12, "LiquidListRow:152 — el chevron de fila")
    }
}
