#if os(iOS)
import SwiftUI
import TipKit
import CenitDesign
import CenitEnsenanza
import CenitAnalytics

// ensenanza: hoy.primer-veredicto, hoy.base-firme, tendencias.pestana, tendencias.carga, entrenar.historial, entrenar.marcas

// MARK: - Hitos del motor (épico FER-428 · L3/FER-436 · D4 = B)
//
// Seis tarjetas de una vez, cada una DEBAJO de su héroe/módulo, en el momento en que el motor
// cumple su promesa: primera lectura (noche 4), base firme (noche 14), primera tendencia, carga
// leída, primera sesión de fuerza, primer récord. Mismo patrón que `HoyTips`/`TendenciasTips`/
// `EntrenarTips`: un `Tip` por hito, `id` del registro (`.hito`), `@Parameter` + `#Rule`. La
// diferencia con los consejos: son de una vez para siempre (`MaxDisplayCount(1)`, sin generación)
// y se saltan la cadencia diaria (`IgnoresDisplayFrequency(true)`), porque ocurren cuando ocurren.
//
// Honestidad temporal (`HitoPuerta`, CenitEnsenanza): un hito solo dispara si su umbral se cruzó
// DESPUÉS de la primera evaluación con esta versión. `Hitos.evaluar` guarda el estado inicial por
// hito en `UserDefaults` («hitos.inicial.<id>») y aplica la regla; los que ya estaban cruzados se
// invalidan para que TipKit no los muestre jamás. Se llama desde la vista dueña del dato cada vez
// que el dato cambia (`.onChange`/`.task`/tras `load()`), nunca desde un timer.
//
// Los umbrales salen del MOTOR, no de la UI: `Baselines.minNightsSeed` (4), `Baselines.minNightsTrust`
// (14), `acwr != nil` (calibración real del ACWR), sesiones guardadas, `latestPersonalRecord`.
// El copy interpola 4 y 14 desde `Baselines` (nunca literales).
//
// El dibujo es `CenitDesign.LiquidUnaVezTipStyle` (Lane C), aplicado EN CADA anclaje con el tono y
// régimen de la pestaña huésped (Hoy/Tendencias sobrio; hub de Entrenar mosaico verde). Nunca
// encima de la palabra/orbe/héroe; nunca modal; sin confeti ni sonido; un solo hito visible por
// pantalla (invalidación en Hoy, `antes:` + `TipGroup(.ordered)` iOS 18 en Tendencias y Entrenar).

/// Un hito del motor: un `Tip` de una vez con su `@Parameter` de elegibilidad y su kicker ya
/// localizado (título de la tarjeta y anuncio de VoiceOver).
protocol HitoTip: Tip {
    init()
    /// Lo enciende `Hitos.evaluar` cuando la regla dice `.disparar`; TipKit lo persiste.
    static var elegible: Bool { get set }
    /// Kicker ya localizado («Primera lectura»).
    var kicker: String { get }
}

extension HitoTip {
    var title: Text { Text(kicker) }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
    // `rules` va en cada struct: `#Rule(Self.$elegible)` necesita el `@Parameter` concreto.
}

// MARK: 1 · hoy.primer-veredicto (noche 4)

struct PrimerVeredictoHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.hoyPrimerVeredicto) }
    var kicker: String { String(localized: "hito.hoy.primer-veredicto.titulo", defaultValue: "First reading") }
    var message: Text? {
        Text(String(localized: "hito.hoy.primer-veredicto.arranque", defaultValue: "I can read you now.")).bold()
            + Text(verbatim: " ")
            + Text(String(format: String(localized: "hito.hoy.primer-veredicto.resto",
                                         defaultValue: "This word came from your %lld nights with the watch. At %lld I'll know your normal and stop flagging confidence."),
                          Baselines.minNightsSeed, Baselines.minNightsTrust))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: Hitos.puertaID,
                     title: String(localized: "hito.hoy.puerta.acta", defaultValue: "Where it came from"))]
    }
}

// MARK: 2 · hoy.base-firme (noche 14)

struct BaseFirmeHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.hoyBaseFirme) }
    var kicker: String { String(localized: "hito.hoy.base-firme.titulo", defaultValue: "Firm baseline") }
    var message: Text? {
        Text(String(localized: "hito.hoy.base-firme.arranque", defaultValue: "Your baseline is firm.")).bold()
            + Text(verbatim: " ")
            + Text(String(format: String(localized: "hito.hoy.base-firme.resto",
                                         defaultValue: "From today I compare you against %lld of your own nights, and the confidence line steps back."),
                          Baselines.minNightsTrust))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: Hitos.puertaID,
                     title: String(localized: "hito.hoy.puerta.acta", defaultValue: "Where it came from"))]
    }
}

// MARK: 3 · tendencias.pestana.primera-tendencia

struct PrimeraTendenciaHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.tendenciasPestana, sufijo: "primera-tendencia") }
    var kicker: String { String(localized: "hito.tendencias.primera-tendencia.titulo", defaultValue: "There's a trend") }
    var message: Text? {
        Text(String(localized: "hito.tendencias.primera-tendencia.arranque", defaultValue: "There's a trend now.")).bold()
            + Text(verbatim: " ")
            + Text(String(localized: "hito.tendencias.primera-tendencia.resto",
                          defaultValue: "Change the period above and tap any value to see its detail."))
    }
    // Sin puerta: solo «Entendido».
}

// MARK: 4 · tendencias.carga.leida

struct CargaLeidaHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.tendenciasCarga, sufijo: "leida") }
    var kicker: String { String(localized: "hito.tendencias.carga-leida.titulo", defaultValue: "Load read") }
    var message: Text? {
        Text(String(localized: "hito.tendencias.carga-leida.arranque", defaultValue: "I can read your load now:")).bold()
            + Text(verbatim: " ")
            + Text(String(localized: "hito.tendencias.carga-leida.resto",
                          defaultValue: "about two weeks of effort are enough. Tap the card to see the hill."))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: Hitos.puertaID,
                     title: String(localized: "hito.tendencias.carga-leida.puerta", defaultValue: "See the hill"))]
    }
}

// MARK: 5 · entrenar.historial.primera-sesion

struct PrimeraSesionHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.entrenarHistorial, sufijo: "primera-sesion") }
    var kicker: String { String(localized: "hito.entrenar.primera-sesion.titulo", defaultValue: "First session") }
    var message: Text? {
        Text(String(localized: "hito.entrenar.primera-sesion.arranque", defaultValue: "Your first session is on record.")).bold()
            + Text(verbatim: " ")
            + Text(String(localized: "hito.entrenar.primera-sesion.resto",
                          defaultValue: "Below go your worked muscles and your log; when you hit your reps, I'll propose a raise."))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: Hitos.puertaID,
                     title: String(localized: "hito.entrenar.primera-sesion.puerta", defaultValue: "See history"))]
    }
}

// MARK: 6 · entrenar.marcas.primer-record

struct PrimerRecordHitoTip: HitoTip {
    @Parameter
    static var elegible: Bool = false

    var rules: [Rule] {
        #Rule(Self.$elegible) { $0 == true }
    }

    var id: String { Registro.tipID(.entrenarMarcas, sufijo: "primer-record") }
    var kicker: String { String(localized: "hito.entrenar.primer-record.titulo", defaultValue: "First record") }
    var message: Text? {
        Text(String(localized: "hito.entrenar.primer-record.arranque", defaultValue: "Your first record is in.")).bold()
            + Text(verbatim: " ")
            + Text(String(localized: "hito.entrenar.primer-record.resto",
                          defaultValue: "They're all kept in Your marks."))
    }
    var actions: [Tips.Action] {
        [Tips.Action(id: Hitos.puertaID,
                     title: String(localized: "hito.entrenar.primer-record.puerta", defaultValue: "See Your marks"))]
    }
}

// MARK: - TipGroups ordenados (iOS 18): dos hitos de la misma pantalla nunca juntos

/// Retenidos como `TendenciasTipGroup.ordered` (FER-432): TipKit muestra uno a la vez y el
/// siguiente al día siguiente. En iOS 17 lo emula `HitoTarjeta(antes:)`.
@available(iOS 18, *)
private enum HitosTipGroups {
    static let tendencias = TipGroup(.ordered) {
        PrimeraTendenciaHitoTip()
        CargaLeidaHitoTip()
    }
    static let entrenar = TipGroup(.ordered) {
        PrimeraSesionHitoTip()
        PrimerRecordHitoTip()
    }
}

// MARK: - Evaluación (capa app): snapshot inicial + regla pura + TipKit

@MainActor
enum Hitos {
    /// El id de la única `Tips.Action` de un hito (la puerta); `LiquidUnaVezTipStyle` toma `actions.first`.
    nonisolated static let puertaID = "puerta"

    /// Días con dato en al menos una señal decisiva para que Tendencias pueda dibujar una línea
    /// (issue FER-436, hito 3). El conteo es el MISMO que alimenta `TendenciasPeriodoTip`
    /// (`CuerpoView.alimentarTendenciasTips`): VFC o FC en reposo de la noche.
    nonisolated static let minDiasPrimeraTendencia = 7

    private static func claveInicial(_ id: String) -> String { "hitos.inicial.\(id)" }

    /// Lee el estado inicial registrado (`nil` = nunca se registró), aplica `HitoPuerta.decidir` y
    /// actúa: `.registrarInicial(x)` guarda x (y si x, invalida el tip para siempre); `.disparar`
    /// enciende `elegible`; `.nunca`/`.esperar` no tocan nada. `cruzadoAhora == nil` = el dato aún
    /// no está (motor sin calcular, `repo` cargando): no registra nada.
    @discardableResult
    static func evaluar<T: HitoTip>(_ tipo: T.Type, cruzadoAhora: Bool?) -> HitoPuerta.Veredicto {
        let tip = T()
        let clave = claveInicial(tip.id)
        let defaults = UserDefaults.standard
        // `object(forKey:)` distingue «no registrado» (nil) de «registrado en false».
        let inicial = defaults.object(forKey: clave) as? Bool
        let veredicto = HitoPuerta.decidir(inicial: inicial, cruzadoAhora: cruzadoAhora)
        switch veredicto {
        case .registrarInicial(let cruzado):
            defaults.set(cruzado, forKey: clave)
            if cruzado { tip.invalidate(reason: .actionPerformed) }
        case .disparar:
            T.elegible = true
        case .nunca, .esperar:
            break
        }
        return veredicto
    }

    /// Hoy (hitos 1 y 2), desde `TodayView` con `repo.todayPreparedness`. `listo` = `repo.fullyLoaded`
    /// (la regla del repo: nada que PERSISTA un valor derivado de `days` antes del pase completo).
    /// El mapeo `Read → (primeraLectura, baseFirme)` vive en `HitoHoy` (CenitEnsenanza, puro y con
    /// test); aquí solo se extraen los campos. Sin historia real (store vacío pre-onboarding: el
    /// pase full publica `lowSignal`/`drivers: []`/0 noches) ambos son `nil` = dato ausente, NO
    /// «umbral no cruzado» (FER-436 · qa r1). Sin reloj ambos son `false`. Un solo hito en Hoy: si
    /// la base ya es firme, «Primera lectura» ya no tiene sentido (nadie recibe «salió de tus 4
    /// noches» con 14) y se invalida.
    static func evaluarHoy(prep: Preparedness.Read?, listo: Bool) {
        guard listo, let prep else {
            evaluar(BaseFirmeHitoTip.self, cruzadoAhora: nil)
            evaluar(PrimerVeredictoHitoTip.self, cruzadoAhora: nil)
            return
        }
        // «No encontré tu día», igual que `Repository.conservaVeredictoPrevio`: sin historia real.
        let hayHistoria = !(prep.drivers.isEmpty && prep.autonomicNights == 0)
        let hayVeredicto = prep.verdict != .lowSignal && prep.isNightAnchored
        let sinReloj = prep.drivers.first(where: { $0.axis == .autonomic })?.state == .noData
        let elegible = HitoHoy.elegibilidad(
            hayHistoria: hayHistoria, hayVeredicto: hayVeredicto, sinReloj: sinReloj,
            autonomicNights: prep.autonomicNights,
            seed: Baselines.minNightsSeed, trust: Baselines.minNightsTrust)
        evaluar(BaseFirmeHitoTip.self, cruzadoAhora: elegible.baseFirme)
        evaluar(PrimerVeredictoHitoTip.self, cruzadoAhora: elegible.primeraLectura)
        if elegible.baseFirme == true { PrimerVeredictoHitoTip().invalidate(reason: .actionPerformed) }
    }

    /// Tendencias (hitos 3 y 4), desde `CuerpoView.alimentarTendenciasTips`. `diasConDato == nil`
    /// mientras `repo` no ha completado el pase; `cargaLeida == nil` mientras no hay cálculo de carga.
    static func evaluarTendencias(diasConDato: Int?, cargaLeida: Bool?) {
        evaluar(PrimeraTendenciaHitoTip.self, cruzadoAhora: diasConDato.map { $0 >= minDiasPrimeraTendencia })
        evaluar(CargaLeidaHitoTip.self, cruzadoAhora: cargaLeida)
    }

    /// Entrenar (hitos 5 y 6), desde el hub tras `load()`. `nil` mientras carga o si la lectura falló.
    static func evaluarEntrenar(sesionGuardada: Bool?, hayMarca: Bool?) {
        evaluar(PrimeraSesionHitoTip.self, cruzadoAhora: sesionGuardada)
        evaluar(PrimerRecordHitoTip.self, cruzadoAhora: hayMarca)
    }

    /// Retiene el `TipGroup(.ordered)` de la pestaña (iOS 18+) para que dos hitos de la misma
    /// pantalla nunca salgan juntos; en iOS 17 lo emula `HitoTarjeta(antes:)`.
    static func retenerGrupoOrdenado(_ pestana: Pestana) {
        guard #available(iOS 18, *) else { return }
        switch pestana {
        case .tendencias: _ = HitosTipGroups.tendencias
        case .entrenar: _ = HitosTipGroups.entrenar
        case .hoy, .ajustes, .transversal: break
        }
    }

    #if DEBUG
    /// Palanca de depuración (FER-436 §5): `-noop.hitos reset` borra el registro inicial de los seis
    /// hitos, para poder probar la secuencia «primera ejecución → cruza el umbral» en el simulador
    /// sin borrar la app. Va junto a `-noop.tips reset` (TipKit también tiene que olvidar que ya
    /// los mostró). Se aplica en `EntrenarTips.configure()`, antes de `Tips.configure`.
    static func aplicarPalancaDebug() {
        guard UserDefaults.standard.string(forKey: "noop.hitos")?.lowercased() == "reset" else { return }
        let ids = [PrimerVeredictoHitoTip().id, BaseFirmeHitoTip().id,
                   PrimeraTendenciaHitoTip().id, CargaLeidaHitoTip().id,
                   PrimeraSesionHitoTip().id, PrimerRecordHitoTip().id]
        for id in ids { UserDefaults.standard.removeObject(forKey: claveInicial(id)) }
    }
    #endif
}

// MARK: - La tarjeta en su anclaje

/// Envuelve `LiquidUnaVezTipStyle` para anunciar el hito a VoiceOver UNA vez, justo cuando la
/// tarjeta se pinta: `makeBody` solo corre cuando TipKit muestra el tip, así que su `onAppear` es
/// el momento exacto (un `onAppear` sobre el `TipView` vacío no es fiable).
private struct HitoTipStyle: TipViewStyle {
    let base: LiquidUnaVezTipStyle
    let alAparecer: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        base.makeBody(configuration: configuration)
            .onAppear(perform: alAparecer)
    }
}

/// Un hito en su sitio: `TipView` inline (sin flecha) vestido con la tarjeta de una vez, con el
/// tono/régimen de la pestaña huésped y la puerta que navega. TipKit decide si se pinta (regla +
/// «una sola vez»); esta vista solo emula el «uno a la vez» de iOS 17 (`antes:`, como
/// `EntrenarConsejoInline`) y aplica el aire SOLO cuando hay tarjeta: sin hito, sin hueco.
/// Sin `.transition` propia: Reduce Motion lo respeta el estilo (`transaction` nulo).
struct HitoTarjeta<T: HitoTip>: View {
    let tip: T
    /// Hitos de la misma pantalla que van antes: si alguno quiere mostrarse, este espera.
    var antes: [any Tip] = []
    var tono: LiquidTono = .neutro
    var regimen: LiquidRegimen = .sobrio
    /// Aire arriba, solo cuando la tarjeta se pinta.
    var arriba: CGFloat = .zero
    /// La puerta («De qué salió ›», «Ver historial ›»…). `nil` = solo «Entendido».
    var puerta: (() -> Void)? = nil
    @State private var anunciado = false

    var body: some View {
        if antes.allSatisfy({ !$0.shouldDisplay }) {
            TipView(tip, arrowEdge: nil) { _ in puerta?() }
                .tipViewStyle(HitoTipStyle(
                    base: LiquidUnaVezTipStyle(tono: tono, regimen: regimen, entendido: Text("Got it")),
                    alAparecer: anunciar))
                .padding(.top, arriba)
        }
    }

    /// VoiceOver: el kicker, una sola vez al aparecer (patrón `OnboardingActoEncendido.anunciarHitos`).
    private func anunciar() {
        guard !anunciado else { return }
        anunciado = true
        AccessibilityNotification.Announcement(tip.kicker).post()
    }
}
#endif
