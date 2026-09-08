import Foundation

// MARK: - Novedades por versión (épico FER-428, L2/FER-435)
//
// Funciones PURAS sobre el registro: agrupan las piezas `.novedad(version:mayor:)` por versión y
// deciden qué está pendiente respecto a la última versión que el usuario ya vio. El paquete no
// sabe qué versión corre la app ni qué vio el usuario — eso lo pasa la app (`NovedadesEstado` en
// `Cenit/System/Ensenanza/Novedades.swift`, que lee `CFBundleShortVersionString` y UserDefaults).
// Foundation-only, sin estado: corre en el fast loop y en la matriz de ubuntu.

public enum Novedades {
    /// Una versión y las funcionalidades que estrenó, en el orden del registro.
    public typealias Version = (version: String, funcionalidades: [Funcionalidad])

    /// Todas las versiones que declaran alguna `.novedad`, la más reciente primero. La comparación
    /// es numérica por componente (`"1.90" > "1.85"`, y `"1.100" > "1.90"`), no alfabética.
    public static func porVersion(_ registro: [Funcionalidad]) -> [Version] {
        var porVersion: [String: [Funcionalidad]] = [:]
        for funcionalidad in registro {
            for pieza in funcionalidad.piezas {
                guard case .novedad(let version, _) = pieza else { continue }
                // Una funcionalidad con dos `.novedad` de la misma versión se lista una vez.
                if !porVersion[version, default: []].contains(funcionalidad) {
                    porVersion[version, default: []].append(funcionalidad)
                }
            }
        }
        return porVersion.keys
            .sorted { esMayor($0, que: $1) }
            .map { (version: $0, funcionalidades: porVersion[$0] ?? []) }
    }

    /// Solo las versiones POSTERIORES a `ultimaVista`, la más reciente primero. `nil` (o vacío)
    /// = el usuario nunca abrió Novedades: todo está pendiente.
    public static func pendientes(en registro: [Funcionalidad], ultimaVista: String?) -> [Version] {
        let todas = porVersion(registro)
        guard let ultimaVista, !ultimaVista.isEmpty else { return todas }
        return todas.filter { esMayor($0.version, que: ultimaVista) }
    }

    /// La versión marcada `mayor: true` más reciente que sea posterior a `ultimaVista` — la que
    /// gana la tarjeta de una vez al fondo de Hoy (D2 del épico). `nil` = ninguna pendiente.
    public static func mayorPendiente(en registro: [Funcionalidad], ultimaVista: String?) -> String? {
        let mayores = registro.flatMap(\.piezas).compactMap { pieza -> String? in
            guard case .novedad(let version, let mayor) = pieza, mayor else { return nil }
            return version
        }
        let pendientes = mayores.filter { version in
            guard let ultimaVista, !ultimaVista.isEmpty else { return true }
            return esMayor(version, que: ultimaVista)
        }
        return pendientes.max { esMayor($1, que: $0) }
    }

    /// `a > b` comparando componente a componente como números (`.numeric`).
    static func esMayor(_ a: String, que b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }
}
