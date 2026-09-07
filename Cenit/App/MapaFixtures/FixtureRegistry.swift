#if os(iOS) && DEBUG
import Foundation

/// Registro de estados de fixture por familia de pantallas (FER-381 · mapa 100 %).
///
/// El mapa de estados se captura con un manifiesto JSON por familia (`docs/appmap/mapa/<f>.json`);
/// cada nodo puede pedir un `fixture` que siembre su estado. Los estados históricos (primed, strained…)
/// viven en `ScreenshotFixtures.seed`; los NUEVOS los aporta cada ola de captura en su propio archivo
/// `<Familia>Fixtures.swift`, y se registran aquí — así una familia agrega estados sin tocar el archivo
/// compartido `ScreenshotFixtures.swift` (evita que seis lanes colisionen en un hot file).
enum FixtureRegistry {
    /// Siembra un estado sobre el `AppModel` (mismo contrato que `ScreenshotFixtures.seed`).
    /// **`@MainActor`**: sembrar toca estado aislado al main actor de `AppModel` (p. ej.
    /// `strengthSession`, `runs`), así que el cierre corre en el main actor — como `ScreenshotFixtures.seed`,
    /// que ya es `@MainActor`. Sin esto, un fixture que muta esas propiedades no compila (FER-381).
    typealias Seed = @MainActor (AppModel) async -> Void

    /// Todos los estados registrados, unidos de cada familia. Una colisión de nombre entre familias es
    /// un bug de autoría (dos familias reclaman el mismo estado) — se marca fuerte en DEBUG.
    static let all: [String: Seed] = {
        var merged: [String: Seed] = [:]
        let families: [[String: Seed]] = [
            HoyFixtures.all, TendenciasFixtures.all, EntrenarFixtures.all,
            EntrenarHerramientasFixtures.all, AjustesFixtures.all, OnboardingFixtures.all,
        ]
        for family in families {
            for (key, seed) in family {
                if merged[key] != nil {
                    assertionFailure("FixtureRegistry: estado de fixture duplicado «\(key)» entre familias")
                }
                merged[key] = seed
            }
        }
        return merged
    }()

    /// Siembra el estado si alguna familia lo registró. `true` = lo tomó (el caller no sigue con su
    /// propio switch); `false` = nombre desconocido (es un estado histórico de `ScreenshotFixtures`).
    @MainActor
    static func seed(named state: String, _ model: AppModel) async -> Bool {
        guard let seed = all[state] else { return false }
        await seed(model)
        return true
    }
}
#endif
