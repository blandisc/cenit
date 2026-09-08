import Foundation

// MARK: - Las estrofas de la espera del onboarding (épico FER-428 · L8/FER-437 · decisión D1)
//
// EXCEPCIÓN DOCUMENTADA a la regla dura de este paquete («texto y rutas, nunca lógica ni estado»,
// ver `Tipos.swift` y docs/ARCHITECTURE.md § Enseñanza): esta es la única regla ejecutable que
// vive aquí, y es pura — Foundation-only, sin estado, sin fecha, sin temporizador. Dado qué etapas
// de `HealthKitBridge.sync` ya terminaron y cuántas filas trajo cada una, dice qué estrofas se
// ganaron. Vive aquí y no en la vista del acto para que `swift test` la cubra sin simulador ni
// HealthKit: el acto solo la consume.
//
// Ancla por grupo (qa r1 · D1/O1). «Trajo datos» lo decide UNA etapa del grupo, no la suma de sus
// filas. La suma mentía con datos de iPhone reales: el HRV diurno del Watch trae filas sin una sola
// noche registrada, y la energía activa del día trae filas sin un solo entreno — y «Tus noches» /
// «Tus entrenamientos» salían igual, enseñando algo que no existe. Cada grupo declara su ancla:
// `resting_hr` para el corazón, `sleep` para las noches, `workouts` para los entrenos, `saving` para
// el guardado. Las demás etapas del grupo siguen teniendo que TERMINAR (no se anuncia un grupo a
// medias), pero sus filas no votan.

/// Las cuatro estrofas de «la espera enseña», en el orden en que se leen. `Int` para que el orden
/// de salida sea siempre el del enum y nunca el de llegada de las etapas.
public enum EstrofaSync: Int, CaseIterable, Sendable {
    case corazon, noches, entrenos, guardado
}

public enum EstrofasSync {
    /// Grupos de etapas por estrofa (claves de `SyncProgress.stageKey`). `etapas` son TODAS las que
    /// deben terminar antes de leer la estrofa; `ancla` es la única cuyas filas deciden si se ganó,
    /// y vive dentro de `etapas`. Cada clave vive en UN solo grupo; las etapas que no enseñan nada
    /// (`avg_hr`, `steps`, `vo2max`…) no están en ninguno.
    public static let grupos: [EstrofaSync: (ancla: String, etapas: [String])] = [
        .corazon: (ancla: "resting_hr", etapas: ["resting_hr"]),
        .noches: (ancla: "sleep", etapas: ["sleep", "hrv", "skin_temp", "resp_rate"]),
        .entrenos: (ancla: "workouts", etapas: ["workouts", "hr_apple_workouts", "active_kcal"]),
        .guardado: (ancla: "saving", etapas: ["saving"]),
    ]

    /// Dado el historial de etapas terminadas con sus filas, qué estrofas ya se ganaron, en orden.
    /// Una estrofa se gana cuando TODAS las etapas de su grupo terminaron Y su etapa ancla trajo
    /// ≥ 1 fila (`.guardado`: cuando `saving` terminó con filas ≥ 1). Una etapa que aún no terminó
    /// no cuenta como cero: deja al grupo a medias. Si una clave llega dos veces, manda la última.
    public static func ganadas(terminadas: [(clave: String, filas: Int)]) -> [EstrofaSync] {
        var filasPorClave: [String: Int] = [:]
        for t in terminadas { filasPorClave[t.clave] = t.filas }
        return EstrofaSync.allCases.filter { estrofa in
            guard let grupo = grupos[estrofa],
                  grupo.etapas.allSatisfy({ filasPorClave[$0] != nil }) else { return false }
            return (filasPorClave[grupo.ancla] ?? 0) >= 1
        }
    }
}
