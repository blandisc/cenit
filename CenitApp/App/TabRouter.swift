#if os(iOS)
import SwiftUI

/// App-level cross-tab navigation. A screen deep inside one tab (e.g. a sheet presented from «Cuerpo»)
/// can ask the app to switch tabs by calling `select(_:)`; `RootTabView` observes `requested` and applies
/// it, then clears it. Deliberately ADDITIVE — it does not own the tab selection (that stays
/// `RootTabView`'s `@State`); it only relays a one-shot request, so the tab shell keeps its existing
/// wiring. (FER-378 — the «Explóralo en el Coach» handoff.)
@MainActor
final class TabRouter: ObservableObject {
    /// Tres cuartos (FER-490): Entrenar · Cuerpo · Ajustes.
    enum Tab: String, Sendable { case cuerpo, train, settings }

    /// Modos de la pestaña Cuerpo (Ahora = ex-Hoy, Tiempo = ex-Tendencias). FER-490.
    enum CuerpoModo: String, Sendable { case ahora, tiempo }

    /// A one-shot tab-switch request. `RootTabView` consumes it (sets it back to nil) on receipt.
    @Published var requested: Tab?

    /// One-shot: modo de Cuerpo a aplicar al aterrizar en `.cuerpo`. Lo consume `CuerpoTabView`.
    @Published var cuerpoModo: CuerpoModo?

    /// One-shot: after landing on «Entrenar», push the muscle-fatigue map (`MuscleVolumeRoute`).
    /// Consumed (reset to false) by `RootTabView`. Lets the strength summary's «Ver mapa» reach the
    /// map in Entrenar without stacking a third sheet over the session (FER-409 → FER-186).
    @Published var openMuscleMapInTrain = false

    /// One-shot: after landing on «Entrenar», start today's guided session. Consumed (reset to false) by
    /// `EntrenarView`. Lets the Daily Brief's «Hoy en tu plan» block start the workout in one tap, reusing
    /// Entrenar's own prefetched slots instead of duplicating the load (FER-613).
    @Published var startTodaySession = false

    /// One-shot (FER-522): after landing on «Entrenar», open a named routine (ready to start — one tap).
    /// Consumed (reset to nil) by `EntrenarView`. Used when Siri asks for a routine that is NOT today's;
    /// today's still goes through `startTodaySession` (path FER-613). Does not force-start — FER-85.
    @Published var startRoutineId: String?

    /// One-shot (FER-435 / FER-490): after landing on Cuerpo/Ahora, open the verdict's acta — or
    /// «¿Qué decide tu día?» when there is no reading yet. Consumed (reset to false) by `TodayView`.
    /// The door in «Cómo funciona Cénit» (`AyudaScreen`) sets it.
    @Published var abrirActa = false

    /// One-shot (FER-435 / FER-490): after landing on Cuerpo/Ahora, open the guardian's sheet.
    /// Consumed (reset to false) by `TodayView`; set by `AyudaScreen`.
    @Published var abrirGuardian = false

    /// FER-502: la hoja «Cómo funciona Cénit» (`AyudaScreen`) está presentada, desde CUALQUIER pestaña.
    /// La marca la propia hoja (`onAppear`/`onDisappear`). Hoy la lee para pausar el ambiente que nadie
    /// está viendo (FER-73 M8) y para abrir la puerta pedida desde Ayuda (`abrirActa`/`abrirGuardian`)
    /// cuando la hoja YA se fue, en vez de adivinarlo con un reloj de 500 ms.
    @Published var ayudaPresentada = false

    func select(_ tab: Tab) { requested = tab }

    /// Cuerpo en modo Tiempo (ex-Tendencias). Sustituye `select(.body)`.
    func verTendencias() {
        cuerpoModo = .tiempo
        requested = .cuerpo
    }

    /// Cuerpo en modo Ahora (ex-Hoy). Sustituye `select(.today)`.
    func verAhora() {
        cuerpoModo = .ahora
        requested = .cuerpo
    }

    /// Switch to «Entrenar» and ask it to push the fatigue map (the strength summary's «Ver mapa»).
    func openFatigueMap() { openMuscleMapInTrain = true; requested = .train }

    /// Switch to «Entrenar» and ask it to start today's session (the Daily Brief's «Empezar»).
    func startTodayTraining() { startTodaySession = true; requested = .train }

    /// Switch to «Entrenar» and ask it to open a named routine ready to start (FER-522 · Siri).
    /// Additive — does not replace `startTodayTraining()`.
    func startTraining(routineId: String) { startRoutineId = routineId; requested = .train }
}
#endif
