import Foundation

/// Resuelve una clave del catálogo de la app desde este paquete Foundation-only: el mismo puente
/// que `CenitAnalytics/AppLocalized.swift`, que no puede importarse porque este paquete no tiene
/// dependencias. `Bundle.main.localizedString` lee el String Catalog compilado de la app; si la
/// clave no está (tests del paquete, Linux), devuelve la clave tal cual.
enum Localizado {
    static func texto(_ clave: String) -> String {
        Bundle.main.localizedString(forKey: clave, value: clave, table: nil)
    }
}
