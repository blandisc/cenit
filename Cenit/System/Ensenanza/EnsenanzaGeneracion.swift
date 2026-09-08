import Foundation
import CenitEnsenanza

// MARK: - «Volver a ver los consejos» = generación por pestaña (épico FER-428 · L2/FER-435, §3c)
//
// TipKit no reinicia un tip: una vez que un `Tip` agotó su `MaxDisplayCount` o se invalidó, ese
// `id` no vuelve, y `Tips.resetDatastore()` es GLOBAL (borraría también los hitos de una vez para
// siempre, FER-436). La salida es cambiar el id: cada pestaña lleva una GENERACIÓN en
// UserDefaults; en la generación 0 el id es el del registro tal cual, y a partir de la 1 lleva el
// sufijo `#n`. Un id nuevo = un tip nuevo para TipKit (conteo y elegibilidad frescos). Los EVENTOS
// de reglas (`Tips.Event`) de esa pestaña llevan el mismo sufijo: un consejo que espera «nunca has
// usado el gesto» (`donations.count == 0`) tampoco volvería sin un evento fresco.
//
// Excepción documentada: los HITOS (FER-436) y la tarjeta de NOVEDAD MAYOR (FER-435) NO pasan por
// aquí — son de una vez para siempre, así que conservan su id sin generación.
enum EnsenanzaGeneracion {
    /// Clave de UserDefaults de la generación de una pestaña.
    static func clave(_ pestana: Pestana) -> String { "ensenanza.generacion.\(pestana.rawValue)" }

    /// Generación vigente de la pestaña (0 = nunca se pidió «volver a ver»).
    static func generacion(_ pestana: Pestana) -> Int {
        UserDefaults.standard.integer(forKey: clave(pestana))
    }

    /// Sufijo del id de TipKit por pestaña: `""` en la generación 0, `"#n"` después. En la
    /// generación 0 el id es idéntico al del registro (`Registro.tipIDs` lo contiene tal cual).
    static func id(_ base: String, _ pestana: Pestana) -> String {
        let generacion = generacion(pestana)
        return generacion == 0 ? base : "\(base)#\(generacion)"
    }

    /// El id de TipKit de un tip del registro, ya con la generación de SU pestaña: el
    /// `Registro.tipID` de L4 garantiza (en Debug, con `assert`) que el id base existe en el
    /// registro; la pestaña sale de la propia funcionalidad, así ningún tip la nombra a mano.
    static func tipID(_ id: FuncionalidadID, sufijo: String? = nil) -> String {
        self.id(Registro.tipID(id, sufijo: sufijo), Registro[id].pestana)
    }

    /// «Volver a ver los consejos de {pestaña}»: sube la generación (todos los tips y eventos de
    /// esa pestaña vuelven a ser elegibles) y, en Hoy, reactiva además los hints de gesto
    /// (`today.scrubHints`, `HoyModosHost`; `today.ecosistemaSeparaciones`, `TodayView`).
    static func reiniciar(_ pestana: Pestana) {
        let defaults = UserDefaults.standard
        defaults.set(generacion(pestana) + 1, forKey: clave(pestana))
        if pestana == .hoy {
            defaults.set(0, forKey: "today.scrubHints")
            defaults.set(0, forKey: "today.ecosistemaSeparaciones")
        }
    }
}
