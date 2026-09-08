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
