import SwiftUI

// MARK: - Liquid Glass · Nota de Δ% con signo y valencia (FER-500 · C2)
//
// El renglón «+12%» que va entre la frase de nivel y la gráfica en las hojas de detalle y en el
// explorador de Tendencias. Vivía cinco veces a mano (MetricExplorer, MetricDetail, Strain, Stress,
// Sleep) y cada copia derivaba distinto: guion ASCII en negativos, «+0%» pintado en verde, esfuerzo
// con valencia sobre una hoja descriptiva, coma forzada ignorando región. Esta pieza encapsula la
// decisión completa:
//
//   · texto = `CenitFormat.deltaPercent` (signo «+», menos real U+2212, cero sin signo, localizado);
//   · tono  = SOLO con polaridad declarada y delta distinto de 0 tras redondear — dirección buena
//     `LiquidColor.positivo`, contraria `LiquidColor.atencionTexto` (ámbar de texto AA: la hoja no
//     es un semáforo, así que nunca `negativo`); `.neutral` o plano → la tinta quieta de
//     `LiquidNotaLine`.
//
// Compone `LiquidNotaLine`: no duplica su tipografía ni su tinta. Sin fondo, sin flecha, sin
// pastilla — es texto de lectura (el chip con fondo de Entrenar es `LiquidStatePill(valencia:)`).
//
// VoiceOver: el DS no conoce locales (mismo contrato que `LiquidNotaLine` / `LiquidResumenVentana`):
// la app pasa la frase YA localizada («12 % más que el periodo anterior» / «sin cambio»); sin ella
// se lee el texto visible. `direccion(pct:places:)` es la fuente para elegir esa frase sin
// re-derivar el redondeo — si el renglón dice «0%», la voz dice «sin cambio».

/// Qué dirección del cambio es buena para la métrica — el único conocimiento de dominio que aporta
/// el caller: VFC / sueño / recuperación suben = bien (`higherIsBetter`); estrés / FC en reposo
/// bajan = bien (`lowerIsBetter`); esfuerzo no juzga (`neutral`). Vocabulario ÚNICO del sistema:
/// nació como `TrendStatSummary.Polarity`, que hoy es un alias de este tipo.
public enum LiquidPolaridad: Sendable, Equatable {
    case higherIsBetter
    case lowerIsBetter
    case neutral
}

public struct LiquidNotaDelta: View {
    /// Hacia dónde se movió el Δ% una vez redondeado a `places` — la base de la frase de VoiceOver
    /// que arma la app («más» / «menos» / «sin cambio»).
    public enum Direccion: Sendable, Equatable {
        case sube, baja, igual
    }

    private let pct: Double
    private let polaridad: LiquidPolaridad
    private let places: Int
    private let accessibilityLabel: String?

    /// - Parameters:
    ///   - pct: el Δ% del periodo vs el anterior, en puntos porcentuales (12.0 = 12 %).
    ///   - polaridad: qué dirección es buena; `.neutral` deja el renglón en tinta quieta.
    ///   - places: decimales del renglón (0 = entero). Texto y tono redondean igual.
    ///   - accessibilityLabel: la frase YA localizada por la app para VoiceOver («12 % más que el
    ///     periodo anterior»); `nil` deja que se lea el texto visible.
    public init(pct: Double, polaridad: LiquidPolaridad, places: Int = 0,
                accessibilityLabel: String? = nil) {
        self.pct = pct
        self.polaridad = polaridad
        self.places = places
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        nota.accessibilityLabel(Text(verbatim: accessibilityLabel ?? texto))
    }

    private var texto: String { CenitFormat.deltaPercent(pct, places: places) }

    /// Con tono → `LiquidNotaLine(_, tono:)`; sin tono → su tinta por defecto (no se repite aquí
    /// el token: si la nota cambia su quietud, esta pieza la sigue).
    @ViewBuilder private var nota: some View {
        if let tono = Self.tono(pct: pct, polaridad: polaridad, places: places) {
            LiquidNotaLine(texto, tono: tono)
        } else {
            LiquidNotaLine(texto)
        }
    }

    // MARK: Reglas puras (se prueban en frío, fuera de MainActor)

    /// La dirección del Δ% tras el redondeo de `CenitFormat.deltaRedondeado`; `nil` con dato inválido.
    nonisolated public static func direccion(pct: Double, places: Int = 0) -> Direccion? {
        guard let redondeado = CenitFormat.deltaRedondeado(pct, places: places) else { return nil }
        if redondeado > 0 { return .sube }
        if redondeado < 0 { return .baja }
        return .igual
    }

    /// El tono del renglón: dirección buena → `positivo`; contraria → `atencionTexto`; plano,
    /// `.neutral` o dato inválido → `nil` (tinta quieta). La única regla de valencia del Δ%.
    nonisolated public static func tono(pct: Double, polaridad: LiquidPolaridad,
                                        places: Int = 0) -> Color? {
        guard let direccion = direccion(pct: pct, places: places), direccion != .igual else {
            return nil
        }
        switch polaridad {
        case .neutral:
            return nil
        case .higherIsBetter:
            return direccion == .sube ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .lowerIsBetter:
            return direccion == .baja ? LiquidColor.positivo : LiquidColor.atencionTexto
        }
    }
}

#if DEBUG
#Preview("Liquid · NotaDelta (6 casos)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s300) {
        // +12 % y subir es bueno (VFC) → positivo
        LiquidNotaDelta(pct: 12, polaridad: .higherIsBetter)
        // −12 % y subir era lo bueno → atención (ámbar de texto, nunca rojo)
        LiquidNotaDelta(pct: -12, polaridad: .higherIsBetter)
        // −12 % y bajar es lo bueno (FC en reposo) → positivo
        LiquidNotaDelta(pct: -12, polaridad: .lowerIsBetter)
        // +7.5 % con un decimal en métrica descriptiva (esfuerzo) → signo sí, juicio no
        LiquidNotaDelta(pct: 7.5, polaridad: .neutral, places: 1)
        // plano → «0%» sin signo y sin color
        LiquidNotaDelta(pct: 0, polaridad: .higherIsBetter)
        // dato malo → «—», nunca «nan%»
        LiquidNotaDelta(pct: .nan, polaridad: .higherIsBetter)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}

#Preview("Liquid · NotaDelta (en la hoja)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s300) {
        LiquidFraseNivel(nivel: "En tu base", conteo: "21 de tus últimos 30 días",
                         tono: LiquidColor.cian)
        LiquidNotaDelta(pct: 12, polaridad: .higherIsBetter,
                        accessibilityLabel: "12 % más que el periodo anterior")
        LiquidNotaLine("SDNN sobre los latidos nocturnos, comparado contra tu base de 21 noches (Task Force, 1996).")
    }
    .liquidTarjetaSeccion()
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
