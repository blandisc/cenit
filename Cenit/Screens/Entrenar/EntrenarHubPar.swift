#if os(iOS)
import SwiftUI
import CenitDesign

// MARK: - Entrenar · EL PAR DEL DÍA del hub v18 (FER-171 · Parte B)
//
// «Subidas listas» (verde). La tesela «Descanso real» y su cable `restReal` se retiraron en
// FER-510 (cero fuente de datos, cero consumidores). Si no hay subidas, el par calla.

struct EntrenarHubPar: View {
    /// Ronda 2 · D1: `valueText` es el ESCALÓN (`toKg − fromKg`) cuando `isStep` — el mock (`.subLs`,
    /// «▲ 2.5 kg») pide el salto, no el peso nuevo. Sin escalón real (primera vez, o `toKg ≤ fromKg`)
    /// `isStep` es `false` y `valueText` es el peso nuevo, SIN «▲» (el arreglo lo pinta solo el caller).
    struct Subida: Identifiable {
        let id: String
        let name: String
        let valueText: String
        let isStep: Bool
    }

    let raises: [Subida]
    let onOpenRaises: () -> Void

    /// Ronda 2 · D2: `subLsFila` era `Font.system(size:)` fijo — texto de LECTURA que no escalaba
    /// con Dynamic Type. `@ScaledMetric` vive en la vista; la base sigue en `EntrenarHubMetrics`.
    @ScaledMetric(relativeTo: .caption2) private var subLsFilaSize = EntrenarHubMetrics.subLsFilaBase

    var body: some View {
        if !raises.isEmpty {
            subidasTile
                .liquidEntrada(index: 3)
        }
    }

    // MARK: - Subidas listas

    private var subidasTile: some View {
        // Ronda 2 · G8: `.onTapGesture` + combine no trae el rasgo de botón para VoiceOver — un
        // `Button` de verdad, mismo patrón que la píldora del héroe (`EntrenarHubHeroe.subPill`).
        Button(action: onOpenRaises) {
            EntrenarTile(tono: .verde) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text("Ready raises").liquidRegla().foregroundStyle(LiquidTono.verde.rotulo)
                    HStack(alignment: .firstTextBaseline, spacing: EntrenarHubMetrics.numRowGap) {
                        Text(verbatim: "\(raises.count)")
                            .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                            .foregroundStyle(LiquidColor.verdeProfundo)
                        EntrenarMiniBarras(alturas: [0.5, 0.75, 1.0], tono: .verde)
                    }
                    .padding(.top, EntrenarHubMetrics.numRowTop)
                    VStack(alignment: .leading, spacing: EntrenarHubMetrics.subLsGap) {
                        ForEach(raises.prefix(3)) { subida in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: subida.name).font(.system(size: subLsFilaSize))
                                    .foregroundStyle(LiquidColor.tinta700)
                                Spacer(minLength: LiquidSpace.s200)
                                subidaValor(subida)
                            }
                        }
                    }
                    .padding(.top, EntrenarHubMetrics.subLsTop)
                }
            }
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens today's routine"))
    }

    @ViewBuilder
    private func subidaValor(_ subida: Subida) -> some View {
        if subida.isStep {
            // «▲» es cromo visual: la etiqueta de VO es solo el valor (sin «black up-pointing triangle»).
            (Text(verbatim: "▲").font(EntrenarHubMetrics.subLsGlifo)
             + Text(verbatim: " ") + Text(verbatim: subida.valueText))
                .font(EntrenarHubMetrics.subLsDelta)
                .foregroundStyle(LiquidColor.verdeProfundo)
                .accessibilityLabel(Text(verbatim: subida.valueText))
        } else {
            Text(verbatim: subida.valueText)
                .font(EntrenarHubMetrics.subLsDelta)
                .foregroundStyle(LiquidColor.verdeProfundo)
        }
    }
}
#endif
