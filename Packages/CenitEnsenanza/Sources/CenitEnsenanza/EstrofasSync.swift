import Foundation

// MARK: - Las estrofas de la espera del onboarding (épico FER-428 · L8/FER-437 · decisión D1)
//
// EXCEPCIÓN DOCUMENTADA a la regla dura de este paquete («texto y rutas, nunca lógica ni estado»,
// ver `Tipos.swift` y docs/ARCHITECTURE.md § Enseñanza): esta es la única regla ejecutable que
// vive aquí, y es pura — Foundation-only, sin estado, sin fecha, sin temporizador. Dado qué etapas
// de `HealthKitBridge.sync` ya terminaron y cuántas filas trajo cada una, dice qué estrofas se
// ganaron. Vive aquí y no en la vista del acto para que `swift test` la cubra sin simulador ni
// HealthKit: el acto solo la consume.

/// Las cuatro estrofas de «la espera enseña», en el orden en que se leen. `Int` para que el orden
/// de salida sea siempre el del enum y nunca el de llegada de las etapas.
public enum EstrofaSync: Int, CaseIterable, Sendable {
    case corazon, noches, entrenos, guardado
}

public enum EstrofasSync {
    /// Grupos de etapas por estrofa (claves de `SyncProgress.stageKey`). Cada clave vive en UN solo
    /// grupo; las etapas que no enseñan nada (`avg_hr`, `steps`, `vo2max`…) no están en ninguno.
    public static let grupos: [EstrofaSync: [String]] = [
        .corazon: ["resting_hr"],
        .noches: ["sleep", "hrv", "skin_temp", "resp_rate"],
        .entrenos: ["workouts", "hr_apple_workouts", "active_kcal"],
        .guardado: ["saving"],
    ]

    /// Dado el historial de etapas terminadas con sus filas, qué estrofas ya se ganaron, en orden.
    /// Una estrofa se gana cuando TODAS las etapas de su grupo terminaron y la suma de sus filas
    /// es ≥ 1 (`.guardado`: cuando `saving` terminó con filas ≥ 1). Una etapa que aún no terminó
    /// no cuenta como cero: deja al grupo a medias. Si una clave llega dos veces, manda la última.
    public static func ganadas(terminadas: [(clave: String, filas: Int)]) -> [EstrofaSync] {
        var filasPorClave: [String: Int] = [:]
        for t in terminadas { filasPorClave[t.clave] = t.filas }
        return EstrofaSync.allCases.filter { estrofa in
            let etapas = grupos[estrofa] ?? []
            guard !etapas.isEmpty, etapas.allSatisfy({ filasPorClave[$0] != nil }) else { return false }
            return etapas.reduce(0) { $0 + (filasPorClave[$1] ?? 0) } >= 1
        }
    }
}
