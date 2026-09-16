// ensenanza: hoy.palabra, tendencias.pestana
#if os(iOS)
import SwiftUI
import CenitDesign

/// Contenedor de la pestaña Cuerpo (FER-490): selector fijo «Ahora | Tiempo» y un solo árbol
/// montado a la vez (`TodayView` / `CuerpoView`). Posee la atmósfera para que el polvo no se
/// reinicie al cambiar de modo (fable #1).
struct CuerpoTabView: View {
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var modo: TabRouter.CuerpoModo = .ahora
    @State private var atmosfera = AtmosferaEstado()
    /// Oculta el selector cuando Tiempo muestra un detalle (fable #4).
    @State private var detailOcupado = false

    var body: some View {
        VStack(spacing: 0) {
            if !detailOcupado {
                selector
                    .padding(.horizontal, LiquidSpace.s600)
                    .padding(.top, LiquidSpace.s200)
                    .padding(.bottom, LiquidSpace.s200)
            }
            // D2 docs/DECISIONS.md:595 «un solo árbol cargado a la vez» — if/else, no ZStack.
            if #available(iOS 18.0, *) {
                modoConScroll
            } else {
                modoSinScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(tabRouter.$cuerpoModo.compactMap { $0 }) { pedido in
            modo = pedido
            detailOcupado = false
            tabRouter.cuerpoModo = nil
        }
    }

    private var selector: some View {
        LiquidRangeSelector(
            opciones: [
                String(localized: "Now"),
                String(localized: "Time"),
            ],
            seleccion: Binding(
                get: { modo == .ahora ? 0 : 1 },
                set: { modo = $0 == 0 ? .ahora : .tiempo; detailOcupado = false }),
            tono: LiquidColor.tinta700)
        .accessibilityLabel(String(localized: "Body"))
    }

    @available(iOS 18.0, *)
    private var modoConScroll: some View {
        CuerpoModoHost(
            modo: modo,
            atmosfera: atmosfera,
            detailOcupado: $detailOcupado)
    }

    @ViewBuilder
    private var modoSinScroll: some View {
        if modo == .ahora {
            TodayView(atmosfera: atmosfera)
        } else {
            CuerpoView(detailOcupado: $detailOcupado)
        }
    }
}

/// Host iOS 18+ que conserva `ScrollPosition` por modo mientras la pestaña vive.
@available(iOS 18.0, *)
private struct CuerpoModoHost: View {
    let modo: TabRouter.CuerpoModo
    let atmosfera: AtmosferaEstado
    @Binding var detailOcupado: Bool

    @State private var ahoraScroll = ScrollPosition()
    @State private var tiempoScroll = ScrollPosition()

    var body: some View {
        // D2 docs/DECISIONS.md:595 «un solo árbol cargado a la vez»
        if modo == .ahora {
            TodayView(atmosfera: atmosfera, scrollPos: $ahoraScroll)
        } else {
            CuerpoView(scrollPos: $tiempoScroll, detailOcupado: $detailOcupado)
        }
    }
}
#endif
