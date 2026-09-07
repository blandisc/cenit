#if os(iOS)
import SwiftUI
import TipKit
import StrandTraining
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
// `id` sale del registro `CenitEnsenanza` (también el id estable de la funcionalidad).
//
// Copy es-MX final: `docs/specs/ola1-entrenar/tips-es.md` / issue 12 tabla de consejos. Ninguna
// cadena promete que una sesión cambia el veredicto (D-Q12) — estos seis conceptos son de Entrenar,
// no del veredicto de Hoy.

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
        #endif
        do {
            // .daily (D8, épico FER-428): entre tips DISTINTOS hay como máximo uno por día — antes
            // era `.immediate`, que podía mostrar varios consejos nuevos en la misma sesión. Los
            // cuatro tips de la primera sesión llevan `IgnoresDisplayFrequency(true)` y se saltan
            // este límite: se enseñan en el momento exacto en que ocurre su concepto.
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
/// (`HojaFilaSerie` en `RoutineSheetLiveTarjeta`, ola 1 · E7). Tip de primera sesión (D8): se
/// enseña en el momento exacto en que ocurre, sin esperar la cadencia diaria.
struct LasQuePuedasTip: Tip {
    var id: String { FuncionalidadID.entrenarAmrapDrop.rawValue + ".amrap" }
    var title: Text { Text("The as-many-as-you-can set") }
    var message: Text? {
        Text("Do every rep you can with good form and log how many you got. It counts for your records and to raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Bajar y seguir» — la primera vez que una fila de sesión muestra el chip de escalón drop.
/// Tip de primera sesión (D8).
struct BajarYSeguirTip: Tip {
    var id: String { FuncionalidadID.entrenarAmrapDrop.rawValue + ".drop" }
    var title: Text { Text("About drop and continue") }
    var message: Text? {
        Text("When you finish the set, drop the weight and keep going without resting. It adds volume; it doesn't count to raise or for records.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Reps en reserva» — el teclado de sesión, la primera vez que se registra una serie de trabajo.
/// Tip de primera sesión (D8).
struct RepsEnReservaTip: Tip {
    var id: String { FuncionalidadID.entrenarRir.rawValue }
    var title: Text { Text("About reps in reserve") }
    var message: Text? {
        Text("How many more reps you had left when you finished. 0 means you hit failure. The app uses it to decide whether you raise.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «¿Qué tan duro estuvo?» — el primer recibo que trae la pregunta de esfuerzo (ola 1 · E3).
/// Tip de primera sesión (D8).
struct EsfuerzoEstimadoTip: Tip {
    var id: String { FuncionalidadID.entrenarEsfuerzoEstimado.rawValue }
    var title: Text { Text("About how hard it was") }
    var message: Text? {
        Text("One tap when you finish. With minutes and effort, your session enters your load even without a watch.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1), Tip.IgnoresDisplayFrequency(true)] }
}

/// «Semana ligera» — la primera vez que Tu Plan la muestra en el kicker del programa (ola 1 · E11).
/// Respeta la cadencia diaria (no es de primera sesión).
struct SemanaLigeraTip: Tip {
    var id: String { FuncionalidadID.entrenarPlan.rawValue + ".semana-ligera" }
    var title: Text { Text("About the light week") }
    var message: Text? {
        Text("The last week of the cycle: half the sets, the same weight. You rest without stopping training.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
}

/// «Ritmo de subida» — la sección «Ritmo» de `ProgressionSetupScreen` (ola 1 · E5). Respeta la
/// cadencia diaria (no es de primera sesión).
struct RitmoDeSubidaTip: Tip {
    var id: String { FuncionalidadID.entrenarProgresion.rawValue + ".ritmo" }
    var title: Text { Text("About the raise rhythm") }
    var message: Text? {
        Text("Steady raises after 2 sessions in a row met; fast after 1; by reps in reserve, it raises 1 if you had 2 to spare and waits if you hit failure.")
    }
    var options: [any Tip.Option] { [Tip.MaxDisplayCount(1)] }
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
