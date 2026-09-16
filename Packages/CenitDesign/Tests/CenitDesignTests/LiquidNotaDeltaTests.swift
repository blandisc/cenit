import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-500 · C2 — la valencia del Δ% se decide en UN lugar y del MISMO valor redondeado que el texto:
/// dirección buena → `positivo`, contraria → `atencionTexto` (nunca `negativo`), plano / neutral /
/// dato inválido → sin tono. Run: swift test --filter LiquidNotaDeltaTests
final class LiquidNotaDeltaTests: XCTestCase {

    /// Compara tonos por componentes resueltos en claro (el Mac en modo oscuro no debe mover el test).
    private func assertMismoTono(_ tono: Color?, _ esperado: Color, _ mensaje: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let tono else {
            return XCTFail("sin tono; se esperaba uno. \(mensaje)", file: file, line: line)
        }
        let a = tono.resolved(at: .light).rgbaComponents
        let b = esperado.resolved(at: .light).rgbaComponents
        XCTAssertEqual(a.r, b.r, accuracy: 0.001, mensaje, file: file, line: line)
        XCTAssertEqual(a.g, b.g, accuracy: 0.001, mensaje, file: file, line: line)
        XCTAssertEqual(a.b, b.b, accuracy: 0.001, mensaje, file: file, line: line)
    }

    // MARK: - Dirección (la base de la frase de VoiceOver)

    func test_direccion_sigueAlRedondeo() {
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: 12), .sube)
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: -12), .baja)
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: 0), .igual)
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: 0.4), .igual, "redondea a «0%» → la voz dice «sin cambio»")
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: -0.4), .igual)
        XCTAssertEqual(LiquidNotaDelta.direccion(pct: 0.4, places: 1), .sube, "con un decimal sí es «+0.4%»")
        XCTAssertNil(LiquidNotaDelta.direccion(pct: .nan))
    }

    // MARK: - Tono

    func test_tono_direccionBuena_esPositivo() {
        assertMismoTono(LiquidNotaDelta.tono(pct: 12, polaridad: .higherIsBetter), LiquidColor.positivo,
                        "VFC sube")
        assertMismoTono(LiquidNotaDelta.tono(pct: -12, polaridad: .lowerIsBetter), LiquidColor.positivo,
                        "FC en reposo baja")
    }

    func test_tono_direccionContraria_esAtencionTexto_nuncaNegativo() {
        assertMismoTono(LiquidNotaDelta.tono(pct: -12, polaridad: .higherIsBetter),
                        LiquidColor.atencionTexto, "VFC baja: ámbar de texto AA, la hoja no es un semáforo")
        assertMismoTono(LiquidNotaDelta.tono(pct: 12, polaridad: .lowerIsBetter),
                        LiquidColor.atencionTexto, "estrés sube")
    }

    func test_tono_planoNeutralOInvalido_esNil() {
        XCTAssertNil(LiquidNotaDelta.tono(pct: 0, polaridad: .higherIsBetter), "plano: sin signo y sin color")
        XCTAssertNil(LiquidNotaDelta.tono(pct: -0.4, polaridad: .higherIsBetter),
                     "redondea a «0%»: un cero en ámbar era el defecto")
        XCTAssertNil(LiquidNotaDelta.tono(pct: 12, polaridad: .neutral), "esfuerzo: signo sí, juicio no")
        XCTAssertNil(LiquidNotaDelta.tono(pct: -12, polaridad: .neutral))
        XCTAssertNil(LiquidNotaDelta.tono(pct: .nan, polaridad: .higherIsBetter))
        XCTAssertNil(LiquidNotaDelta.tono(pct: .infinity, polaridad: .lowerIsBetter))
    }

    /// Texto y tono redondean con la misma regla: a un decimal, −0.4 SÍ es una bajada.
    func test_tono_respetaLosDecimalesDelTexto() {
        XCTAssertEqual(CenitFormat.deltaPercent(-0.4, places: 1, locale: Locale(identifier: "es_MX")),
                       "\u{2212}0.4%")
        assertMismoTono(LiquidNotaDelta.tono(pct: -0.4, polaridad: .higherIsBetter, places: 1),
                        LiquidColor.atencionTexto)
    }

    // MARK: - Un solo vocabulario de polaridad

    func test_polaridad_esElVocabularioDeTrendStatSummary() {
        let p: TrendStatSummary.Polarity = .higherIsBetter
        XCTAssertEqual(p, LiquidPolaridad.higherIsBetter)
    }

    @MainActor
    func test_exists_asPublicAPI() {
        let _: any View = LiquidNotaDelta(pct: 12, polaridad: .higherIsBetter)
        let _: any View = LiquidNotaDelta(pct: 7.5, polaridad: .neutral, places: 1,
                                          accessibilityLabel: "7.5 % más que el periodo anterior")
    }
}
