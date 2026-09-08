#if os(iOS)
import SwiftUI
import TipKit
import CenitTraining
import CenitEnsenanza

// MARK: - Consejos contextuales de Entrenar (ola 1 · E12, issue 12-vocabulario-tutorial;
// cadencia diaria + id del registro, épico FER-428 L4/FER-430)
//
// Capa 2 del tutorial sin tour (artefacto `ola1-pantallas.html` §4): un `Tip` por concepto, sin
// reglas de aparición explícitas más allá de la cadencia — cada uno se ancla con `.popoverTip(_:)`
// justo donde el concepto aparece en pantalla por primera vez. El estilo visual (tinta sobre
// vidrio) vive en `CenitDesign.LiquidConsejoTipStyle`, aplicado una sola vez en la raíz de la app
// (`CenitApp.swift:97`, sobre `ContentView()`) — ningún sitio de anclaje repite `.tipViewStyle(_:)`.
//
// D8 (épico FER-428): cadencia diaria entre tips DISTINTOS (`.displayFrequency(.daily)`), grupo
// ordenado por pestaña — los cuatro de la primera sesión (`LasQuePuedasTip`, `BajarYSeguirTip`,
// `RepsEnReservaTip`, `EsfuerzoEstimadoTip`) llevan `IgnoresDisplayFrequency(true)` porque son
// conceptos que se enseñan en el momento exacto en que ocurren, no una campaña de notificaciones
// que deba esperar su turno; `SemanaLigeraTip`/`RitmoDeSubidaTip` sí respetan la cadencia. Cada
// `id` sale del registro `CenitEnsenanza` (también el id estable de la funcionalidad), con la
// generación de la pestaña por delante (`EnsenanzaGeneracion.tipID`, FER-435: «Volver a ver»).
//
// Copy es-MX final: `docs/specs/ola1-entrenar/tips-es.md` / issue 12 tabla de consejos. Ninguna
// cadena promete que una sesión cambia el veredicto (D-Q12) — estos seis conceptos son de Entrenar,
// no del veredicto de Hoy. L7 (FER-434) suma seis consejos INLINE con reglas (ver el MARK abajo).

/// Arranca TipKit una sola vez al lanzar la app (`CenitApp.init`). 100% on-device: TipKit persiste
/// su datastore local (qué tip ya se mostró) sin red — no rompe la regla offline del repo.
/// Ancla un consejo SOLO si `condition` — el overload de `popoverTip` que acepta un `Tip?` opcional
/// es iOS 26+, así que en iOS 17 la condición va aquí, no en el argumento (ola 1 · E12, fix build).
extension View {
    @ViewBuilder
    func popoverTipIf<T: Tip>(_ condition: Bool, _ tip: @autoclosure () -> T) -> some View {
        if condition { self.popoverTip(tip()) } else { self }
    }

}

enum EntrenarTips {
    static func configure() {
        #if DEBUG
        // Palanca de depuración para el Mapa 100 % (FER-359/FER-379): `-noop.tips <all|none|reset>`
        // fuerza el estado de TipKit antes de `configure()`, para poder capturar/probar cada tip
        // sin esperar su cadencia real ni recorrer la app entera.
        switch UserDefaults.standard.string(forKey: "noop.tips")?.lowercased() {
        case "all":   Tips.showAllTipsForTesting()
        case "none":  Tips.hideAllTipsForTesting()
        case "reset": try? Tips.resetDatastore()
        default: break
        }
        // FER-436: `-noop.hitos reset` borra el registro inicial de los seis hitos del motor.
        // `Hitos` es @MainActor y `configure()` corre en el arranque de la app (hilo principal).
        MainActor.assumeIsolated { Hitos.aplicarPalancaDebug() }
        #endif
        do {
            // .daily (D8): como máximo un tip DISTINTO por día; los de primera sesión se saltan el
            // límite con `IgnoresDisplayFrequency(true)` (ver la cabecera del archivo).
            try Tips.configure([.displayFrequency(.daily)])
        } catch {
            // Nunca bloquear el arranque de la app por un consejo — mismo criterio que el resto
            // del repo (p. ej. HealthKitBridge): un fallo de TipKit apaga los consejos, no la app.
            #if DEBUG
            print("EntrenarTips.configure failed: \(error)")
            #endif
        }
    }
}

/// «Serie «las que puedas»» — la primera vez que una fila de sesión muestra el chip AMRAP
/// (`HojaFilaSerie` en `RoutineSheetLiveTarjeta`, ola 1 · E7).
struct LasQuePuedasTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarAmrapDrop, sufijo: "amrap") }
    var title: Text { Text("The as-many-as-you-can set") }
    var message: Text? {
        Text("Do every rep you can with good form and log how many you got. It counts for your records and to raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Bajar y seguir» — la primera vez que una fila de sesión muestra el chip de escalón drop.
struct BajarYSeguirTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarAmrapDrop, sufijo: "drop") }
    var title: Text { Text("About drop and continue") }
    var message: Text? {
        Text("When you finish the set, drop the weight and keep going without resting. It adds volume; it doesn't count to raise or for records.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Reps en reserva» — el teclado de sesión, la primera vez que se registra una serie de trabajo.
struct RepsEnReservaTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarRir) }
    var title: Text { Text("About reps in reserve") }
    var message: Text? {
        Text("How many more reps you had left when you finished. 0 means you hit failure. The app uses it to decide whether you raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «¿Qué tan duro estuvo?» — el primer recibo que trae la pregunta de esfuerzo (ola 1 · E3).
struct EsfuerzoEstimadoTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarEsfuerzoEstimado) }
    var title: Text { Text("About how hard it was") }
    var message: Text? {
        Text("One tap when you finish. With minutes and effort, your session enters your load even without a watch.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Semana ligera» — la primera vez que Tu Plan la muestra en el kicker del programa (ola 1 · E11).
struct SemanaLigeraTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarPlan, sufijo: "semana-ligera") }
    var title: Text { Text("About the light week") }
    var message: Text? {
        Text("The last week of the cycle: half the sets, the same weight. You rest without stopping training.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Ritmo de subida» — la sección «Ritmo» de `ProgressionSetupScreen` (ola 1 · E5).
struct RitmoDeSubidaTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarProgresion, sufijo: "ritmo") }
    var title: Text { Text("About the raise rhythm") }
    var message: Text? {
        Text("Steady raises after 2 sessions in a row met; fast after 1; by reps in reserve, it raises 1 if you had 2 to spare and waits if you hit failure.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

// MARK: - L7 (FER-434): seis consejos más — reglas de TipKit (eventos y parámetros) y orden por pantalla
//
// Regla del épico (D8 + issue): inline, uno a la vez, `MaxDisplayCount(3)`; los tres que ocurren en
// sesión (entrar a Foco, salir, discos) llevan `IgnoresDisplayFrequency(true)` como los primerizos
// de arriba. Cada regla es un `Tips.Event` que dona la Hoja viva (`RoutineSheetLive.swift`,
// `RoutineSheetLiveLogic.swift`) o un `@Parameter` que fija la pantalla dueña del dato
// (`EntrenarView`, `RoutineSheet`, `RestEditorScreen`). Usar la función invalida el consejo
// (`.actionPerformed`); «Volver a ver» (L2, FER-435) lo revive subiendo la generación de la pestaña
// (`EnsenanzaGeneracion`: id y eventos nuevos), no con `Tips.resetDatastore()` (global: se
// llevaría los hitos de una vez para siempre).

/// Los eventos de TipKit que alimentan las reglas de L7. Un solo sitio, porque dos consejos
/// comparten `focoEntrado` (el de entrar lo exige en cero; el de salir presupone ≥ 1).
/// FER-435: cada id lleva la generación de la pestaña (`EnsenanzaGeneracion`) — «Volver a ver los
/// consejos de Entrenar» estrena eventos, y «nunca has entrado a Foco» vuelve a ser verdad.
enum EntrenarTipEvents {
    /// Se dona al montar la Hoja viva (`HojaSesionViva.body`).
    static var sesionIniciada: Tips.Event<Tips.EmptyDonation> {
        Tips.Event(id: EnsenanzaGeneracion.id("entrenar.sesion-viva.sesion-iniciada", .entrenar))
    }
    /// Se dona al entrar a Foco (`focusMode` → `true`).
    static var focoEntrado: Tips.Event<Tips.EmptyDonation> {
        Tips.Event(id: EnsenanzaGeneracion.id("entrenar.sesion-viva.foco-entrado", .entrenar))
    }
    /// Se dona al salir de Foco (`focusMode` → `false`).
    static var focoSalido: Tips.Event<Tips.EmptyDonation> {
        Tips.Event(id: EnsenanzaGeneracion.id("entrenar.sesion-viva.foco-salido", .entrenar))
    }
    /// Se dona al registrar una serie de TRABAJO con peso real (`registerActiveSet`).
    static var serieDeTrabajoConPeso: Tips.Event<Tips.EmptyDonation> {
        Tips.Event(id: EnsenanzaGeneracion.id("entrenar.sesion-viva.serie-de-trabajo-con-peso", .entrenar))
    }
}

/// «Entra a Foco» — bajo la tarjeta activa, desde la primera sesión viva y mientras nunca se haya
/// entrado a Foco. Copy honesto: la puerta es el «⤢» de la tarjeta (orden del dueño 2026-08-29:
/// tocar el cromo abre el detalle del ejercicio, no Foco).
struct EntrarAFocoTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarSesionViva, sufijo: "foco-entrar") }
    var title: Text { Text(String(localized: "tip.entrenar.foco-entrar.titulo", defaultValue: "Enter Focus")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.foco-entrar.mensaje",
                    defaultValue: "Tap ⤢ on the card and the set takes the whole screen: set, rest, done."))
    }
    var rules: [Rule] {
        #Rule(EntrenarTipEvents.sesionIniciada) { $0.donations.count >= 1 }
        #Rule(EntrenarTipEvents.focoEntrado) { $0.donations.count < 1 }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Para salir» — dentro de Foco, junto al asa, hasta la primera salida.
struct ParaSalirTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarSesionViva, sufijo: "foco-salir") }
    var title: Text { Text(String(localized: "tip.entrenar.foco-salir.titulo", defaultValue: "To leave")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.foco-salir.mensaje",
                    defaultValue: "Drag the handle down, or tap Exit."))
    }
    var rules: [Rule] {
        #Rule(EntrenarTipEvents.focoEntrado) { $0.donations.count >= 1 }
        #Rule(EntrenarTipEvents.focoSalido) { $0.donations.count < 1 }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Qué discos poner» — bajo la tarjeta activa (solo con barra), tras la primera serie de trabajo
/// con peso. Copy honesto: tocar el peso abre la consola; la tecla «discos» de la consola abre la
/// calculadora.
struct QueDiscosPonerTip: Tip {
    var id: String { EnsenanzaGeneracion.tipID(.entrenarSesionViva, sufijo: "discos") }
    var title: Text { Text(String(localized: "tip.entrenar.discos.titulo", defaultValue: "Which plates to load")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.discos.mensaje",
                    defaultValue: "Tap the weight, then «plates» on the keypad: you'll see what to load per side, with the warm-up ramp."))
    }
    var rules: [Rule] {
        #Rule(EntrenarTipEvents.serieDeTrabajoConPeso) { $0.donations.count >= 1 }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Hoy descansas» — el hub, junto al pliegue «Otra forma», en día de descanso.
struct HoyDescansasTip: Tip {
    /// Lo fija `EntrenarView` (es quien sabe si hoy hay rutina).
    @Parameter static var hoyEsDescanso: Bool = false

    var id: String { EnsenanzaGeneracion.tipID(.entrenarOtraForma) }
    var title: Text { Text(String(localized: "tip.entrenar.otra-forma.titulo", defaultValue: "You rest today")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.otra-forma.mensaje",
                    defaultValue: "In «Other ways» there's Breathe, Intervals and Mobility, no guilt."))
    }
    var rules: [Rule] {
        #Rule(Self.$hoyEsDescanso) { $0 == true }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
}

/// «Sube solo» — la tarjeta abierta de un ejercicio de peso×reps en el editor, cuando ninguna
/// progresión está activa.
struct SubeSoloTip: Tip {
    /// Lo fija `RoutineSheet` (editor con ≥ 1 ejercicio de peso×reps y ninguna progresión activa).
    @Parameter static var rutinaSinProgresion: Bool = false

    var id: String { EnsenanzaGeneracion.tipID(.entrenarProgresion, sufijo: "activar") }
    var title: Text { Text(String(localized: "tip.entrenar.progresion.titulo", defaultValue: "Raise on its own")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.progresion.mensaje",
                    defaultValue: "Turn on progression from each card's «···»: hit your reps and the routine raises the weight."))
    }
    var rules: [Rule] {
        #Rule(Self.$rutinaSinProgresion) { $0 == true }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
}

/// «Descanso por pulso» — el editor de descanso, solo con Apple Watch emparejado (sin reloj nunca
/// aparece: no hay «vista FC» que enseñar sin inventarla).
struct DescansoPorPulsoTip: Tip {
    /// Lo fija `RestEditorScreen` al aparecer, desde `AppModel.watchPaired`.
    @Parameter static var relojEmparejado: Bool = false

    var id: String { EnsenanzaGeneracion.tipID(.entrenarDescanso, sufijo: "por-fc") }
    var title: Text { Text(String(localized: "tip.entrenar.descanso-fc.titulo", defaultValue: "Rest by pulse")) }
    var message: Text? {
        Text(String(localized: "tip.entrenar.descanso-fc.mensaje",
                    defaultValue: "With a watch, rest can end when your pulse drops. Choose it here."))
    }
    var rules: [Rule] {
        #Rule(Self.$relojEmparejado) { $0 == true }
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(3)] }
}

/// Un consejo INLINE de Entrenar, en el orden de su pantalla (D8: uno a la vez). `TipGroup(.ordered)`
/// es iOS 18 y pide un `@State` compartido por todos los anclajes de la pantalla; con target iOS 17 y
/// anclajes repartidos en vistas distintas, se emula con el mismo criterio: `tip` solo se monta si
/// ninguno de los consejos ANTERIORES de su pantalla (`antes`) quiere mostrarse (`shouldDisplay`,
/// iOS 17). Subir a `TipGroup` cuando el target lo permita es un cambio de UN sitio: este.
/// El aire (`arriba`/`abajo`) se aplica SOLO cuando el consejo se pinta: sin consejo, sin hueco.
struct EntrenarConsejoInline<T: Tip>: View {
    let tip: T
    var antes: [any Tip] = []
    var arriba: CGFloat = .zero
    var abajo: CGFloat = .zero

    var body: some View {
        if antes.allSatisfy({ !$0.shouldDisplay }) {
            TipView(tip, arrowEdge: nil)
                .padding(.top, arriba)
                .padding(.bottom, abajo)
        }
    }
}

extension View {
    /// El consejo de «las que puedas» / «bajar y seguir», anclado a la fila de sesión que YA
    /// muestra el chip de ese tipo (ola 1 · E12, ancla en `RoutineSheetLiveTarjeta`). `SetMode`
    /// (fuente de verdad tipada, no el string ya localizado) decide cuál de los dos aplica; una
    /// serie estándar no lleva consejo. TipKit garantiza «una sola vez» de forma global: el mismo
    /// `Tip` puede anclarse en los 3 sitios de `HojaFilaSerie` (ejercicio suelto, superserie,
    /// escalón) sin riesgo de mostrarse dos veces — tras cerrarlo en cualquiera, no vuelve en
    /// ninguno.
    @ViewBuilder
    func entrenarConsejoTipoSerie(_ mode: SetMode) -> some View {
        switch mode {
        case .amrap: self.popoverTip(LasQuePuedasTip())
        case .drop:  self.popoverTip(BajarYSeguirTip())
        case .standard: self
        }
    }
}
#endif
