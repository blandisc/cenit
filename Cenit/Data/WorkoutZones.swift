import Foundation
import CenitStore

// MARK: - Zonas de FC guardadas por entrenamiento
//
// `zonesJSON` es el objeto de porcentajes de zona que quedó guardado en filas de entrenamientos
// importados. Del mismo dato existen DOS formas de llave — «z1»…«z5» y «zone1»…«zone5» — según qué
// importador lo escribió; se toleran las dos para que una copia movida entre plataformas siga
// pintando. Los valores son porcentaje (0–100) de la duración del entrenamiento y pueden sumar menos
// de 100: el tiempo por debajo de la zona 1 nunca se exportó.
enum WorkoutZones {

    /// Cuántas zonas maneja el modelo. Fijo: la tarjeta pinta exactamente cinco barras.
    private static let zoneCount = 5

    /// Los porcentajes Z1…Z5 (0–100) de un entrenamiento, o `nil` cuando la fila no trae nada usable.
    ///
    /// «Nada usable» incluye el caso de que las cinco zonas den cero: pintar cinco ceros diría que el
    /// entrenamiento se pasó fuera de toda zona, y lo que en realidad pasó es que no hay dato.
    static func percents(_ zonesJSON: String?) -> [Double]? {
        guard let zonesJSON,
              let bytes = zonesJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        else { return nil }

        let values = (1...zoneCount).map { zone -> Double in
            let raw = object["z\(zone)"] ?? object["zone\(zone)"]
            let percent = (raw as? NSNumber)?.doubleValue ?? 0
            return percent.clampedToPercent
        }
        return values.contains { $0 > 0 } ? values : nil
    }

    /// Minutos por zona sumados sobre varios entrenamientos, pesados por su duración.
    ///
    /// APROXIMACIÓN declarada: es un agregado hecho en el teléfono a partir de porcentajes ya
    /// importados (minutos × pct ÷ 100), no una cifra que haya calculado la fuente original.
    struct Summary {
        /// Índice 0 = Z1 … 4 = Z5. Siempre trae `zoneCount` posiciones.
        let minutes: [Double]
        /// Cuántas filas aportaron zonas (las demás se saltan, no cuentan como cero).
        let sessionsWithZones: Int

        var totalMinutes: Double { minutes.reduce(0, +) }
    }

    static func summary(from rows: [WorkoutRow]) -> Summary? {
        var minutes = [Double](repeating: 0, count: zoneCount)
        var contributing = 0

        for row in rows {
            guard let percents = percents(row.zonesJSON) else { continue }
            // Una fila vieja puede no traer duración explícita; ahí manda el lapso de reloj.
            let durationMinutes = (row.durationS ?? Double(row.endTs - row.startTs)) / 60.0
            guard durationMinutes > 0 else { continue }

            for zone in minutes.indices {
                minutes[zone] += durationMinutes * percents[zone] / 100.0
            }
            contributing += 1
        }

        guard contributing > 0, minutes.reduce(0, +) > 0 else { return nil }
        return Summary(minutes: minutes, sessionsWithZones: contributing)
    }
}

private extension Double {
    /// Un porcentaje guardado fuera de rango se recorta en vez de deformar la barra.
    var clampedToPercent: Double { Swift.min(Swift.max(self, 0), 100) }
}
