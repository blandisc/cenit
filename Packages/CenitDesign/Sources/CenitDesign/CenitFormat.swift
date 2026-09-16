import Foundation

/// Shared presentation formatters (FER-326). Lives in the design system because formatting is
/// part of the visual language — screens consume these instead of re-declaring NumberFormatters.
public enum CenitFormat {
    /// Thousands-grouped integer (no fraction digits), e.g. 12345 → "12,345".
    ///
    /// FER-466: `Int(v.rounded())` (aquí en el fallback, y en todo sink a la medida) **trapea** con un
    /// `Double` no-finito (NaN/±Inf) o finito pero fuera de rango de `Int` (magnitud > ~9.2e18). Este es
    /// el camino guardado y compartido: dato malo → «—», nunca un crash. Enrutar los formateadores a la
    /// medida por aquí (o por `int`/`decimal`) es lo que mata la clase (gate `no-unsafe-int-cast`).
    public static func groupedInt(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return emptyDato }
        return groupedIntFormatter.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }

    /// Guarded plain integer string ("176") for display — non-finite / overflow-magnitude → «—», nunca
    /// un trap de `Int()`. Úsalo en vez de `"\(Int(v.rounded()))"` a la medida (FER-466).
    public static func int(_ v: Double) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return emptyDato }
        return "\(Int(v.rounded()))"
    }

    /// Guarded fixed-decimal string ("36.6") for display — non-finite → «—», nunca "nan"/"inf" (FER-466).
    public static func decimal(_ v: Double, places: Int) -> String {
        guard v.isFinite, abs(v) < 1e15 else { return emptyDato }
        return String(format: "%.\(max(0, places))f", v)
    }

    /// Δ% con signo tipográfico (FER-500 · C2, LENGUAJE §8): «+12%», «−12%», «0%». `pct` llega YA en
    /// puntos porcentuales (12.0 = 12 %). El «+» va explícito en positivo, el menos es el signo real
    /// `−` (U+2212, nunca el guion ASCII) y el cero no lleva signo: plano no es «+0». Localizado —
    /// es-MX/en-US pegan el «%» («+12%»); es-ES/de-DE/fr-FR meten su espacio y su coma decimal
    /// («+7,5 %») — eso lo decide el locale, no la pantalla. `places` fija los decimales (0 = entero);
    /// el redondeo es escolar (`.rounded()`: 12.5 → 13), no el bancario del formateador, para que el
    /// texto coincida con el tono que `LiquidNotaDelta` deriva del MISMO valor (`deltaRedondeado`).
    /// Guardado como sus hermanos: no finito o magnitud absurda → «—», nunca «nan%» ni un trap.
    public static func deltaPercent(_ pct: Double, places: Int = 0,
                                    locale: Locale = .autoupdatingCurrent) -> String {
        guard let redondeado = deltaRedondeado(pct, places: places) else { return emptyDato }
        let formateador = NumberFormatter()
        formateador.numberStyle = .percent
        formateador.locale = locale
        formateador.minimumFractionDigits = max(0, places)
        formateador.maximumFractionDigits = max(0, places)
        formateador.minusSign = menosReal
        if redondeado > 0 { formateador.positivePrefix = formateador.plusSign }
        return formateador.string(from: NSNumber(value: redondeado / 100)) ?? emptyDato
    }

    /// El signo menos real (U+2212) de LENGUAJE §8 — deltas y restas nunca con guion.
    public static let menosReal = "\u{2212}"

    /// El ÚNICO redondeo del Δ%: a `places` decimales, escolar, con «−0» normalizado a 0. Texto
    /// (`deltaPercent`) y valencia (`LiquidNotaDelta.tono`) parten de este valor para no
    /// contradecirse: un «0%» pintado en ámbar era exactamente el defecto de FER-500. `nil` = dato
    /// inválido (no finito o fuera de toda magnitud razonable).
    static func deltaRedondeado(_ pct: Double, places: Int) -> Double? {
        guard pct.isFinite, abs(pct) < 1e15 else { return nil }
        let escala = pow(10.0, Double(max(0, places)))
        let redondeado = (pct * escala).rounded() / escala
        return redondeado == 0 ? 0 : redondeado
    }

    /// El sentinel de dato ausente/ inválido, único en el sistema («—», guión largo).
    public static let emptyDato = "—"
    private static let groupedIntFormatter: NumberFormatter = {
        let formateador = NumberFormatter()
        formateador.numberStyle = .decimal
        formateador.maximumFractionDigits = 0
        return formateador
    }()

    /// «Sáb 15 ago» — a short weekday+day+month heading, capitalized, in the current locale. Shared
    /// between `EntrenarView`'s landing header and `TrainingBodyScreen`'s «Tu cuerpo» header
    /// (FER-136 · V7, quisquilloso ronda 4): the two copies drifted apart as a hand-synced duplicate.
    public static func weekdayHeading(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let s = f.string(from: date)
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
