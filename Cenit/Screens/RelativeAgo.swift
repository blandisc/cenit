import Foundation

/// Etiqueta gruesa de «hace cuánto», para la línea de estado «Historial sincronizado hace N».
/// Es pura: `now` se inyecta para poder probar los bordes de cada tramo (`RelativeAgoTests`).
/// Los tramos son a propósito los mismos que usa la app hermana de Android (`relativeAgo`,
/// LiveScreen.kt, ed6a31d), para que las dos se lean igual. Una marca de tiempo en el futuro
/// (desfase de reloj del sensor) se recorta a «hace un momento»: nunca sale un número negativo.
///
/// FER-417 — vive aquí, fuera del andamio oscuro retirado, para que sus consumidores vivos
/// (LiveView, DataSourcesView, RelativeAgoTests) lo conserven.
func relativeAgo(_ epochSeconds: TimeInterval,
                 now: TimeInterval = Date().timeIntervalSince1970) -> String {
    let segundos = max(0, Int(now - epochSeconds))
    switch segundos {
    case ..<60:     return String(localized: "just now")
    case ..<3600:   return String(localized: "\(segundos / 60) min ago")
    case ..<86_400: return String(localized: "\(segundos / 3600) h ago")
    default:        return String(localized: "\(segundos / 86_400) d ago")
    }
}
