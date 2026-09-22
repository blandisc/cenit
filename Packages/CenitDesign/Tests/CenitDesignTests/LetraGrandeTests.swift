#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import CenitDesign

/// El dato y el cuerpo crecen con la letra del sistema. El número de un anillo no.
///
/// `ImageRenderer` no agranda un `Font` anclado a un estilo de texto (ver
/// `LiquidGlassTests.test_type_unidadDelNumeralEscala`). Lo que sí obedece es el layout
/// que lee `dynamicTypeSize`. `@ScaledMetric(relativeTo:)` usa la misma curva que el
/// `relativeTo` de la fuente: el dato de Hoy va a `.title3`, el cuerpo de Entrenar a
/// `.footnote`, y el número del anillo es un alto fijo.
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

    @MainActor
    func test_laCurvaCrece_elAltoFijoNo() {
        let datoChico = alto(Regla(base: 22, estilo: .title3), .large)
        let datoGrande = alto(Regla(base: 22, estilo: .title3), .accessibility5)
        XCTAssertGreaterThan(
            datoGrande, datoChico + 1,
            "title3 \(datoChico) → \(datoGrande): el dato tiene que crecer"
        )

        let cuerpoChico = alto(Regla(base: 13, estilo: .footnote), .large)
        let cuerpoGrande = alto(Regla(base: 13, estilo: .footnote), .accessibility5)
        XCTAssertGreaterThan(
            cuerpoGrande, cuerpoChico + 1,
            "footnote \(cuerpoChico) → \(cuerpoGrande): el cuerpo tiene que crecer"
        )

        let anilloChico = alto(AltoFijo(puntos: 54), .large)
        let anilloGrande = alto(AltoFijo(puntos: 54), .accessibility5)
        XCTAssertEqual(
            anilloGrande, anilloChico, accuracy: 0.5,
            "fijo \(anilloChico) → \(anilloGrande): el número del anillo se queda quieto"
        )
    }

    @MainActor
    private func alto<V: View>(_ view: V, _ size: DynamicTypeSize) -> CGFloat {
        let wrapped = view
            .environment(\.dynamicTypeSize, size)
            .fixedSize()
        let renderer = ImageRenderer(content: wrapped)
        renderer.proposedSize = ProposedViewSize(width: 8, height: nil)
        renderer.scale = 1
        guard let image = renderer.nsImage else {
            XCTFail("no se pudo medir la letra")
            return 0
        }
        return image.size.height
    }
}

/// Alto que sigue la curva de Dynamic Type del estilo, igual que un `relativeTo`.
private struct Regla: View {
    var base: CGFloat
    var estilo: Font.TextStyle
    @ScaledMetric var puntos: CGFloat

    init(base: CGFloat, estilo: Font.TextStyle) {
        self.base = base
        self.estilo = estilo
        _puntos = ScaledMetric(wrappedValue: base, relativeTo: estilo)
    }

    var body: some View {
        Color.black.frame(width: 4, height: puntos)
    }
}

/// Alto en puntos. No lee la letra del sistema.
private struct AltoFijo: View {
    var puntos: CGFloat
    var body: some View {
        Color.black.frame(width: 4, height: puntos)
    }
}
#endif
