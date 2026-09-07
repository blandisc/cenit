#if os(iOS)
import SwiftUI
import TipKit
import CenitEnsenanza

// MARK: - Consejos contextuales de Hoy (FER-432 · L5)
//
// Mismo patrón que `EntrenarTips`: un `Tip` por consejo, `id` del registro, rules + options.
// El estilo `LiquidConsejoTipStyle` ya vive en la raíz (`CenitApp`) — no se repite aquí.
// Cadencia diaria (`.displayFrequency(.daily)` en `EntrenarTips.configure`). TipGroup
// ordenado solo bajo iOS 18+; en iOS 17 la cadencia ya limita a uno por día.

// MARK: TipGroup (iOS 18+)

@available(iOS 18, *)
enum HoyTipGroup {
    /// Grupo ordenado de la pestaña Hoy (D8): uno a la vez, en el orden del registro.
    static let ordered = TipGroup(.ordered) {
        HoyHojaMetricaTip()
        HoyScrubTip()
        HoyEcosistemaTip()
        HoyManualesTip()
        HoySincronizarTip()
    }
}

// MARK: 1 · hoy.hoja-metrica

struct HoyHojaMetricaTip: Tip {
    @Parameter
    static var hayCeldaConDato: Bool = false

    var id: String { Registro.tipID(.hoyHojaMetrica) }
    var title: Text { Text("tip.hoy.hoja-metrica.title") }
    var message: Text? { Text("tip.hoy.hoja-metrica.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$hayCeldaConDato) { $0 == true }
    }
}

// MARK: 2 · hoy.scrub

struct HoyScrubTip: Tip {
    @Parameter
    static var hayCeldaConDosNoches: Bool = false

    static let scrubUsado: Event = Event(id: "hoy.scrub.usado")

    var id: String { Registro.tipID(.hoyScrub) }
    var title: Text { Text("tip.hoy.scrub.title") }
    var message: Text? { Text("tip.hoy.scrub.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$hayCeldaConDosNoches) { $0 == true }
        #Rule(Self.scrubUsado) { $0.donations.count == 0 }
    }
}

// MARK: 3 · hoy.ecosistema

struct HoyEcosistemaTip: Tip {
    @Parameter
    static var hayVeredicto: Bool = false

    static let separado: Event = Event(id: "hoy.ecosistema.separado")

    var id: String { Registro.tipID(.hoyEcosistema) }
    var title: Text { Text("tip.hoy.ecosistema.title") }
    var message: Text? { Text("tip.hoy.ecosistema.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.$hayVeredicto) { $0 == true }
        #Rule(Self.separado) { $0.donations.count == 0 }
    }
}

// MARK: 4 · hoy.manuales

struct HoyManualesTip: Tip {
    static let mananaConVeredicto: Event = Event(id: "hoy.manuales.manana-con-veredicto")

    var id: String { Registro.tipID(.hoyManuales) }
    var title: Text { Text("tip.hoy.manuales.title") }
    var message: Text? { Text("tip.hoy.manuales.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.mananaConVeredicto) { $0.donations.count >= 3 }
    }
}

// MARK: 5 · hoy.sincronizar

struct HoySincronizarTip: Tip {
    static let franjaSinSync: Event = Event(id: "hoy.sincronizar.franja-sin-sync")

    var id: String { Registro.tipID(.hoySincronizar) }
    var title: Text { Text("tip.hoy.sincronizar.title") }
    var message: Text? { Text("tip.hoy.sincronizar.message") }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
    var rules: [Rule] {
        #Rule(Self.franjaSinSync) { $0.donations.count >= 2 }
    }
}

// MARK: Helpers de donación / parámetros (capa app)

enum HoyTips {
    /// Donación de «mañana con veredicto» a lo sumo una vez por día civil local.
    static func donarMananaConVeredictoSiAplica(hayVeredicto: Bool, dayKey: String) {
        guard hayVeredicto else { return }
        let defaults = UserDefaults.standard
        let key = "hoy.tips.mananaConVeredicto.day"
        guard defaults.string(forKey: key) != dayKey else { return }
        defaults.set(dayKey, forKey: key)
        HoyManualesTip.mananaConVeredicto.sendDonation()
    }

    /// Alimenta los `@Parameter` que la Matriz / el héroe ya conocen.
    static func alimentarParametros(
        hayCeldaConDato: Bool,
        hayCeldaConDosNoches: Bool,
        hayVeredicto: Bool
    ) {
        HoyHojaMetricaTip.hayCeldaConDato = hayCeldaConDato
        HoyScrubTip.hayCeldaConDosNoches = hayCeldaConDosNoches
        HoyEcosistemaTip.hayVeredicto = hayVeredicto
    }
}
#endif
