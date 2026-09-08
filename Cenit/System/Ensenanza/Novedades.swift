import Foundation
import CenitEnsenanza

// MARK: - Estado de «Novedades» (épico FER-428 · L2/FER-435, §3d)
//
// El paquete decide QUÉ está pendiente (`Novedades.pendientes`, puro); aquí vive lo que el
// paquete no puede saber: la versión que corre (`CFBundleShortVersionString`), la última versión
// que el usuario vio en la hoja (`novedades.ultimaVersionVista`) y la última que anunció la
// tarjeta de una vez al fondo de Hoy (`novedades.ultimaVistaTarjeta`). `""` = nunca.
//
// Primera instalación: `ContentView` marca las dos al terminar el onboarding — no hay nada que
// anunciar a quien acaba de llegar. Quien ACTUALIZA llega con `""` y ve el punto (y la tarjeta,
// si la versión está marcada `mayor`) en cuanto el registro declare una `.novedad`: correcto, sí
// hay novedades. Hoy el registro no declara ninguna (las del épico se registran en FER-439).
enum NovedadesEstado {
    static let claveUltimaVersionVista = "novedades.ultimaVersionVista"
    static let claveUltimaVistaTarjeta = "novedades.ultimaVistaTarjeta"

    /// La versión que corre: la misma que muestra el pie de Ajustes y «Acerca de».
    static var versionActual: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static var ultimaVersionVista: String? { leer(claveUltimaVersionVista) }
    static var ultimaVistaTarjeta: String? { leer(claveUltimaVistaTarjeta) }

    /// El registro que consume Novedades. En Debug, `-noop.novedades <version>` (misma técnica que
    /// `-cenit.restore`) le cuelga una novedad sintética `mayor` a «Cómo funciona Cénit» y a
    /// «Novedades» para ver vivos el punto, la hoja y la tarjeta SIN tocar el registro real.
    static var registro: [Funcionalidad] {
        #if DEBUG
        if let version = UserDefaults.standard.string(forKey: "noop.novedades"), !version.isEmpty {
            return Registro.todas.map { funcionalidad in
                guard funcionalidad.id == .ajustesAyuda || funcionalidad.id == .ajustesNovedades else {
                    return funcionalidad
                }
                return Funcionalidad(
                    id: funcionalidad.id,
                    pestana: funcionalidad.pestana,
                    requiere: funcionalidad.requiere,
                    piezas: funcionalidad.piezas + [.novedad(version: version, mayor: true)],
                    desde: funcionalidad.desde
                )
            }
        }
        #endif
        return Registro.todas
    }

    /// Todas las versiones con novedades, la más reciente primero.
    static var porVersion: [Novedades.Version] { Novedades.porVersion(registro) }

    /// Las versiones posteriores a `ultimaVista` (la fila de Ajustes pasa su `@AppStorage` para
    /// re-pintarse cuando la hoja marca vistas; el resto usa el valor guardado).
    static func pendientes(ultimaVista: String?) -> [Novedades.Version] {
        Novedades.pendientes(en: registro, ultimaVista: ultimaVista)
    }

    static var pendientes: [Novedades.Version] { pendientes(ultimaVista: ultimaVersionVista) }
    static var hayPendientes: Bool { !pendientes.isEmpty }

    /// La versión `mayor` más reciente del registro, vista o no — es la llave del id del tip de la
    /// tarjeta (`ajustes.novedades.mayor.<version>`), que TipKit muestra UNA vez por versión.
    static var versionMayor: String? { Novedades.mayorPendiente(en: registro, ultimaVista: nil) }

    /// Hay una versión `mayor` posterior a la última que anunció la tarjeta — alimenta el
    /// `@Parameter` de `NovedadMayorTip`.
    static var hayMayorPendiente: Bool {
        Novedades.mayorPendiente(en: registro, ultimaVista: ultimaVistaTarjeta) != nil
    }

    /// Al abrir la hoja de Novedades: el punto de Ajustes se apaga.
    static func marcarVistas() {
        UserDefaults.standard.set(versionActual, forKey: claveUltimaVersionVista)
    }

    /// Al cruzar la puerta de la tarjeta de novedad mayor.
    static func marcarTarjetaVista() {
        UserDefaults.standard.set(versionActual, forKey: claveUltimaVistaTarjeta)
    }

    /// Primera instalación (al terminar el onboarding): nada que anunciar.
    static func marcarTodoVisto() {
        marcarVistas()
        marcarTarjetaVista()
    }

    private static func leer(_ clave: String) -> String? {
        let valor = UserDefaults.standard.string(forKey: clave) ?? ""
        return valor.isEmpty ? nil : valor
    }
}
