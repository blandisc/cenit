// ensenanza: ajustes.novedades
#if os(iOS)
import SwiftUI
import TipKit
import CenitDesign

// MARK: - «Nuevo en esta versión» (épico FER-428 · L2/FER-435, D2 = A)
//
// La tarjeta de una vez al FONDO de Hoy (debajo de la Matriz, nunca encima del héroe ni de la
// palabra; nunca modal), solo cuando el registro marca una versión `mayor: true`. TipKit pone el
// «una sola vez» (`MaxDisplayCount(1)` + id por versión) y `LiquidUnaVezTipStyle` el dibujo: un
// módulo más de la columna, kicker callado, el único color en la puerta «Ver novedades». Se
// cierra con «Entendido» y no vuelve; la siguiente versión `mayor` es otro id, otra tarjeta.

/// Sin generación (`EnsenanzaGeneracion`): es de una vez para siempre, como los hitos (FER-436).
struct NovedadMayorTip: Tip {
    /// Hay una versión `mayor` posterior a la última que anunció la tarjeta (`NovedadesEstado`).
    @Parameter
    static var hayMayorPendiente: Bool = false

    /// La versión `mayor` que anuncia — parte del id, así TipKit cuenta «una vez» POR versión.
    let version: String

    var id: String { "ajustes.novedades.mayor.\(version)" }
    var title: Text {
        Text(String(localized: "novedades.tarjeta.kicker", defaultValue: "New in this version"))
    }
    var message: Text? {
        Text(String(localized: "novedades.tarjeta.cuerpo",
                    defaultValue: "There are new things in Cénit. They're in Settings → What's new, each with its route."))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: "ver") {
            Text(String(localized: "novedades.tarjeta.accion", defaultValue: "See what's new"))
        }]
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
    var rules: [Rule] {
        #Rule(Self.$hayMayorPendiente) { $0 == true }
    }
}

struct NovedadMayorTarjeta: View {
    @State private var mostrarNovedades = false

    var body: some View {
        // Sin versión `mayor` en el registro no hay tip que montar (hoy: ninguna; en Debug,
        // `-noop.novedades <version>` la inyecta, ver `NovedadesEstado.registro`).
        if let version = NovedadesEstado.versionMayor {
            TipView(NovedadMayorTip(version: version), arrowEdge: nil) { _ in
                // La puerta: TipKit ya invalidó el tip (`.actionPerformed`, en el estilo).
                NovedadesEstado.marcarTarjetaVista()
                NovedadMayorTip.hayMayorPendiente = NovedadesEstado.hayMayorPendiente
                mostrarNovedades = true
            }
            // Sobrio y neutro: Hoy es sobrio y ninguna tarjeta toma el color del veredicto
            // (voz de marca, nunca juicio — ficha de UI FER-435/436). «Entendido» viene del
            // catálogo de la app, como en `LiquidConsejoTipStyle` (FER-429).
            .tipViewStyle(LiquidUnaVezTipStyle(entendido: Text("Got it")))
            // La columna de módulos de Hoy (16, = dock), no el margen del héroe (24).
            .padding(.horizontal, LiquidSpace.s400)
            .onAppear { NovedadMayorTip.hayMayorPendiente = NovedadesEstado.hayMayorPendiente }
            .sheet(isPresented: $mostrarNovedades) {
                NavigationStack { NovedadesSheet() }
            }
        }
    }
}
#endif
