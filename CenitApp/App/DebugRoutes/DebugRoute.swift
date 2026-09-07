#if os(iOS) && DEBUG
import Foundation

/// `-cenit.route <familia/clave>` (FER-381): lleva la captura del mapa a una pantalla que NO tiene
/// atajo `cenit.nav` (marcas, volumen muscular, tickets, detalle de sesión, editor de rutina…), sin
/// tener que tapear labels localizados.
///
/// La Ola 1 (cimientos) solo resuelve la **tab** por el primer segmento; cada familia consume su
/// prefijo con `DebugRoute.key(for:)` y empuja su pantalla concreta en su propia ola de captura.
enum DebugRoute {
    /// El valor crudo del arg, p. ej. `"entrenar/marcas"`. `nil` en un arranque normal.
    static var requested: String? {
        guard let r = UserDefaults.standard.string(forKey: "cenit.route"), !r.isEmpty else { return nil }
        return r
    }

    /// El primer segmento (la familia): `hoy` · `tendencias` · `entrenar` · `ajustes`.
    static var family: String? { requested?.split(separator: "/").first.map(String.init) }

    /// La clave sin el prefijo, solo si la ruta pertenece a `family`. Para que una pantalla de esa
    /// familia sepa qué abrir. `nil` si la ruta es de otra familia o no hay ruta.
    static func key(for family: String) -> String? {
        guard let r = requested else { return nil }
        let parts = r.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == family else { return nil }
        return parts[1]
    }
}
#endif
