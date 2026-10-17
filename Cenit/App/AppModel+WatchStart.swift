import Foundation
import CenitAnalytics
import CenitTraining
import CenitStore

/// FER-96 — the Apple Watch's idle-face verdict, and a wrist-initiated «Empezar». Both need the SAME
/// resolution `EntrenarView` already does for «today» (its routine, and — for the start path — that
/// routine's guided-session slots): the one-oracle invariant is that the watch never resolves either
/// itself, it only asks; the iPhone remains the single source of truth.
///
/// `EntrenarView.swift` is out of THIS phase's scope (owned by E4/FER-85, and — while this phase is in
/// flight — locked by a parallel FER-96 sibling lane working `Cenit/Screens/Routine*`), so
/// `startToday()`/`startTodayNow()` there can't be extracted into a shared call site in this same
/// change. This resolves with the identical store/repo primitives `EntrenarView.load()` and
/// `startToday()` use (`WeeklySplit.todayRoutineId`, `repo.sessionSeed`, `repo.trainingAdvice`) — never
/// a shortcut straight into `startStrengthSession` with guessed/stale slots. A follow-up should point
/// `EntrenarView.startToday()` at this same method once `Cenit/Screens/**` is free to touch, so there is
/// exactly one implementation, not two that happen to agree today.
extension AppModel {

    // MARK: - Idle-face verdict push

    /// Push the resting-face context (today's routine name + the already-resolved daily verdict) to the
    /// watch. Best-effort and silent on every failure path (no store, no plan, no watch) — the watch
    /// simply keeps whatever it last knew, or its existing «sin lectura» look.
    func pushWatchIdleContext() async {
        let routine = await todayRoutineForWatch()
        // CEN-65 (barrido 2): la muñeca ya no recibe la palabra del día; el oráculo de recuperación se
        // retiró. Solo viaja la rutina de hoy, su semilla y si hay plan semanal.
        var semanaVacia = false
        if let store = await repo.storeHandle(), let sched = try? await store.routineSchedule() {
            semanaVacia = sched.isEmpty
        }
        // C1 (FER-361): also push today's plan as a SEED so the watch can start a session STANDALONE
        // (offline). Same resolution the wrist start uses; nil on a rest day / empty plan → the watch
        // shows «Empieza en tu iPhone» (its no-seed branch). The seed's id/startTs are throwaway — the
        // watch mints a fresh identity via `asTemplate` when it actually starts.
        var seed: WorkoutMirrorMessage?
        var dose: WorkoutMirrorMessage?
        if let routine {
            let serving = await repo.programServing()
            let seeded = await resolveTodayDoseForWatch(routineId: routine.id, routineName: routine.name,
                                                       serving: serving)
            if !seeded.slots.isEmpty {
                let model = StrengthSessionModel.make(routineId: routine.id, routineName: routine.name,
                                                      slots: seeded.slots,
                                                      startTs: Int(Date().timeIntervalSince1970))
                model.programWeek = serving.flatMap(\.stampWeek)
                model.deload = serving.flatMap(\.stampDeload)
                seed = .sessionModel(model.snapshot())
            }
            // FER-491: typed DosePlan projection (additive). Pre-FER-491 watches drop unknown cases.
            if let plan = seeded.plan {
                dose = DosePlanner.mirrorMessage(from: plan)
            }
        }
        mirroringBridge?.pushIdleContext(word: nil, toneRaw: nil,
                                         advice: nil, routineName: routine?.name,
                                         seed: seed, dose: dose,
                                         hasWeeklyPlan: !semanaVacia)
    }

    // MARK: - Wrist-initiated start

    /// «Empezar» tapped on the wrist's idle face (`.startFromWrist`), outside any session. A no-op with a
    /// session already running, on a rest day, or with an empty routine — exactly what
    /// `EntrenarView.startTodayNow(_:)` already refuses («guard !todaySlots.isEmpty else { openRoutine…
    /// }» — the watch has no routine screen to fall back into, so it simply doesn't start).
    func startTodayFromWrist() async {
        guard strengthSession == nil else { return }
        guard let routine = await todayRoutineForWatch() else { return }
        // Ola 1 · E10 (FER-329): arrancar desde la muñeca sirve EL MISMO plan del día que el teléfono,
        // así que la semana se lee UNA vez y va tanto al recorte de los slots como a la marca de la
        // sesión. Sin la marca, entrenar desde el reloj en la semana ligera guardaría una sesión
        // recortada SIN la frontera, y el ciclo la leería como un mal día.
        let serving = await repo.programServing()
        let slots = await resolveTodaySlotsForWatch(routineId: routine.id, serving: serving)
        guard !slots.isEmpty else { return }
        startStrengthSession(routineId: routine.id, routineName: routine.name, slots: slots,
                             programWeek: serving.flatMap(\.stampWeek),
                             deload: serving.flatMap(\.stampDeload))
    }

    /// Today's scheduled routine, or nil on a rest day / with no plan — the same resolution
    /// `EntrenarView.todayRoutine` uses (`WeeklySplit.todayRoutineId` over the stored weekly split).
    private func todayRoutineForWatch() async -> Routine? {
        guard let tid = await repo.todayRoutineId() else { return nil }
        guard let store = await repo.storeHandle() else { return nil }
        return (try? await store.routines())?.first { $0.id == tid }
    }

    /// Los slots de hoy para `routineId`, construidos fresco en cada llamada — sin la `@State`
    /// cacheada que el teléfono tiene que reconstruir contra el veredicto vivo. El bucle NO vive
    /// aquí: es `repo.seedTodaySlots`, el MISMO que siembra el héroe del teléfono (FER-124). Antes
    /// era una copia del bucle que coincidía con la del teléfono por buena voluntad; ahora es la
    /// misma, y no pueden divergir.
    private func resolveTodaySlotsForWatch(routineId: String,
                                           serving: ProgramServing.Context?) async
        -> [StrengthSessionModel.PlanSlot] {
        await resolveTodayDoseForWatch(routineId: routineId, routineName: nil,
                                       serving: serving).slots
    }

    /// FER-491: slots + typed `DosePlan` from the same owner (`repo.seedTodayDose`).
    private func resolveTodayDoseForWatch(routineId: String,
                                          routineName: String?,
                                          serving: ProgramServing.Context?) async
        -> (slots: [StrengthSessionModel.PlanSlot], plan: DosePlan?) {
        await repo.seedTodayDose(routineId: routineId, advice: repo.trainingAdvice,
                                 inventory: plates.inventory, serving: serving,
                                 verdict: nil, routineName: routineName)
    }
}
