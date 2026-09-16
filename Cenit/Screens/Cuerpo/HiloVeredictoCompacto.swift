// ensenanza: hoy.palabra, hoy.acta
#if os(iOS)
import SwiftUI
import CenitDesign
import CenitAnalytics

/// Palabra compacta del veredicto (FER-490): `EntrenarHilo` con radio `orbeCuerpo` (44).
/// Misma fuente que Entrenar (`LiquidHoyBuilder.hiloEntrenar`); abre la Acta al toque.
/// Grande (radio default) vive SOLO en Entrenar. Nunca pone el número de carga en esta fila.
struct HiloVeredictoCompacto: View {
    let prep: Preparedness.Read?
    let healthConnected: Bool
    let nights: Int
    let verdictPending: Bool
    var hasPlan: Bool = true
    var primerUsoSinPlan: Bool = false
    /// Si no nil, sustituye `hilo.consejo` (p. ej. la lectura muscular de Tu cuerpo).
    var advice: ((LiquidHoyBuilder.HiloEntrenar) -> LocalizedStringKey?)? = nil
    let onOpenActa: () -> Void

    var body: some View {
        if let hilo = LiquidHoyBuilder.hiloEntrenar(
            prep: prep,
            nights: nights,
            healthConnected: healthConnected,
            verdictPending: verdictPending,
            hasPlan: hasPlan,
            primerUsoSinPlan: primerUsoSinPlan) {
            EntrenarHilo(
                tone: hilo.tono.entrenarTone,
                word: LocalizedStringKey(hilo.palabra),
                advice: advice?(hilo) ?? hilo.consejo.map { LocalizedStringKey($0) },
                radio: EntrenarMetrics.orbeCuerpo,
                hint: "Opens today's ballot",
                action: onOpenActa)
        }
    }
}
#endif
