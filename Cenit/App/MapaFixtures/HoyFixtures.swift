#if os(iOS) && DEBUG
import Foundation

/// Estados de fixture de la familia **Hoy** para el mapa 100 % (FER-381).
///
/// Sigue VACÍO a propósito en la Ola 2A — no por pereza, por un hueco real en los cimientos de la
/// Ola 1 (repórtalo al director, no lo parches aquí: `ScreenshotFixtures.swift` es de otra familia):
///
/// `ScreenshotFixtures.activeState()` filtra `-cenit.fixture` contra una lista blanca LITERAL
/// (`["primed", "strained", "balanced", "rundown", "insufficient", "calibrating", "downloading",
/// "train"]`) ANTES de que `FixtureRegistry.seed(named:_:)` — el que sí lee `HoyFixtures.all` — tenga
/// oportunidad de correr. Un estado nuevo aquí (p. ej. `"leyendo": { model in … }`) sería MUERTO: su
/// `"fixture":"leyendo"` en `hoy.json` pasaría `-cenit.fixture leyendo`, `activeState()` no lo
/// reconocería, devolvería `nil`, y `AppModel.init` seguiría al arranque de producción normal en vez
/// de sembrar nada — el nodo capturaría la pantalla EQUIVOCADA en silencio (el falso verde exacto que
/// este harness existe para matar). Cualquier familia con la MISMA necesidad choca con el mismo hueco.
///
/// Ola 2A (FER-383) rodeó el hueco reusando los 8 estados YA en la lista blanca
/// (`primed`/`insufficient`/`downloading`/…) combinados con overrides a nivel de presentación en
/// `TodayView.swift` (`-cenit.healthDenied`, `-cenit.hour`, `-cenit.syncStale`) y con `DebugRoute` para
/// las hojas sin disparador real — ver `docs/appmap/mapa/hoy.json` y sus `condicion`. Ningún nodo de
/// Hoy referencia una clave de este archivo. Arreglar el hueco de raíz (sumar `FixtureRegistry.all.keys`
/// al filtro de `activeState()`) es un cambio a `ScreenshotFixtures.swift`, fuera de esta familia.
enum HoyFixtures {
    static let all: [String: FixtureRegistry.Seed] = [:]
}
#endif
