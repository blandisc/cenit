import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-488 — la fila «Contexto · Carga» es NEUTRA por decisión del dueño (2026-09-15 §6): la carga
/// no vota, así que su única mancha de color es la IDENTIDAD de carga y la palabra va en tinta.
/// Igual que `EntrenarHiloContrasteTests`, esto se mide (`OKLab.contrastRatio`), no se dictamina a
/// ojo; resolución explícita en claro para no depender de la apariencia del Mac (FER-448).
final class EntrenarFilaCargaTests: XCTestCase {

    private typealias Tinta = EntrenarFilaCarga.Tinta

    private var lienzo: Color { EntrenarMetrics.lienzoContraste.resolved(at: .light) }

    private func rgba(_ color: Color) -> [Double] {
        let k = color.resolved(at: .light).rgbaComponents
        return [k.r, k.g, k.b, k.a]
    }

    /// Rótulo, palabra, «Calibrando» y chevron: ≥ 4.5:1 (AA texto) sobre el lienzo de la portada.
    func testLasTintasDeLaFilaCumplenAAsobreElLienzo() {
        let tintas: [(String, Color)] = [
            ("rotulo", Tinta.rotulo), ("palabra", Tinta.palabra),
            ("calibrando", Tinta.calibrando), ("chevron", Tinta.chevron),
        ]
        for (nombre, tinta) in tintas {
            let ratio = OKLab.contrastRatio(tinta.resolved(at: .light), lienzo)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(nombre) da \(ratio):1 sobre el lienzo")
        }
    }

    /// El punto es la IDENTIDAD de carga (`verdeCarga`), nunca el verde del veredicto/marca ni un
    /// color de juicio: es la regla que separa esta fila de `TrainingLoadStrip` (`Flag.color()`).
    func testElPuntoEsIdentidadDeCargaNoUnJuicio() {
        let punto = rgba(Tinta.punto)
        XCTAssertEqual(punto, rgba(LiquidColor.verdeCarga))
        let juicios: [(String, Color)] = [
            ("verdePrimario", LiquidColor.verdePrimario), ("positivo", LiquidColor.positivo),
            ("atencion", LiquidColor.atencion), ("negativo", LiquidColor.negativo),
        ]
        for (nombre, juicio) in juicios {
            XCTAssertNotEqual(punto, rgba(juicio),
                              "el punto de la fila está pintado con \(nombre): la carga no vota")
        }
    }
}
