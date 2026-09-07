#if os(iOS) && DEBUG
import Foundation

/// Estados de fixture de la familia **Tendencias** para el mapa 100 % (FER-381).
///
/// Vacío en la Ola 1 (cimientos). La ola de captura de esta familia agrega aquí sus estados nuevos
/// — un `"clave": { model in await … }` por estado — y los referencia por `fixture` en su manifiesto
/// `docs/appmap/mapa/<familia>.json`. No toques `ScreenshotFixtures.swift` ni las otras familias.
enum TendenciasFixtures {
    static let all: [String: FixtureRegistry.Seed] = [:]
}
#endif
