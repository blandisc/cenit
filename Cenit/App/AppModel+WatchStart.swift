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
        // FER-499: «primer uso sin plan» con la MISMA regla nombrada que la portada y el widget
        // (`TrainWidgetPublisher.esPrimerUsoSinPlan`): sin sesión viva y sin plan. Sin ella, la muñeca
        // decía «Conecta Apple Salud» las mañanas en que el iPhone callaba a propósito (FER-376).
        // Si el store NO abre no se puede confirmar la semana → se trata como «hay plan» (semanaVacia =
        // false), igual que la portada con su split cacheado; asumir vacía empujaba `nil` mientras la
        // portada decía «Sin Apple Salud,» (hueco de la revisión adversarial de FER-499).
        var semanaVacia = false
        if let store = await repo.storeHandle(), let sched = try? await store.routineSchedule() {
            semanaVacia = sched.isEmpty
        }
        let hilo = Self.idleHilo(prep: repo.todayPreparedness, fullyLoaded: repo.fullyLoaded,
                                 healthConnected: healthBridge?.auth == .authorized,
                                 hasPlan: routine != nil,
                                 primerUsoSinPlan: TrainWidgetPublisher.esPrimerUsoSinPlan(
                                    sessionLive: strengthSession != nil, semanaVacia: semanaVacia))
        // C1 (FER-361): also push today's plan as a SEED so the watch can start a session STANDALONE
        // (offline). Same resolution the wrist start uses; nil on a rest day / empty plan → the watch
        // shows «Empieza en tu iPhone» (its no-seed branch). The seed's id/startTs are throwaway — the
        // watch mints a fresh identity via `asTemplate` when it actually starts.
        var seed: WorkoutMirrorMessage?
        var dose: WorkoutMirrorMessage?
        if let routine {
            let serving = await repo.programServing()
            let seeded = await resolveTodayDoseForWatch(routineId: routine.id, routineName: routine.name,
                                                       serving: serving, hilo: hilo)
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
        mirroringBridge?.pushIdleContext(word: hilo?.palabra, toneRaw: hilo.map(Self.watchToneRaw(_:)),
                                         advice: hilo?.consejo, routineName: routine?.name,
                                         seed: seed, dose: dose,
                                         hasWeeklyPlan: !semanaVacia)
    }

    /// Lo que viaja a la muñeca: el oráculo TAL CUAL (`LiquidHoyBuilder.hiloEntrenar`), sin re-derivar ni
    /// sustituir nada aquí. Puro y `internal` para que `OraculoUnicoTests` compare esta palabra con la
    /// del widget y la de la portada el mismo día (FER-499).
    static func idleHilo(prep: Preparedness.Read?, fullyLoaded: Bool, healthConnected: Bool,
                         hasPlan: Bool, primerUsoSinPlan: Bool) -> LiquidHoyBuilder.HiloEntrenar? {
        LiquidHoyBuilder.hiloEntrenar(prep: prep, nights: prep?.autonomicNights ?? 0,
                                      healthConnected: healthConnected,
                                      verdictPending: prep == nil && !fullyLoaded,
                                      hasPlan: hasPlan, primerUsoSinPlan: primerUsoSinPlan)
    }

    /// The wire vocabulary `CenitWatch` decodes (`"clear"/"caution"/"ease"/"hollow"`) for
    /// `LiquidHoyBuilder.HiloEntrenar.Tono` — the SAME 4-case mapping `EntrenarView.hiloTono(_:)` uses to
    /// reach `EntrenarHilo.Tone`, just ending in a plain `String` instead of the `CenitDesign` enum
    /// (`CenitShared` stays free of that import — Alcance §4).
    private static func watchToneRaw(_ hilo: LiquidHoyBuilder.HiloEntrenar) -> String {
        switch hilo.tono {
        case .claro:    return "clear"
        case .atencion: return "caution"
        case .alerta:   return "ease"
        case .hueco:    return "hollow"
        }
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
                                       serving: serving, hilo: nil).slots
    }

    /// FER-491: slots + typed `DosePlan` from the same owner (`repo.seedTodayDose`).
    private func resolveTodayDoseForWatch(routineId: String,
                                          routineName: String?,
                                          serving: ProgramServing.Context?,
                                          hilo: LiquidHoyBuilder.HiloEntrenar?) async
        -> (slots: [StrengthSessionModel.PlanSlot], plan: DosePlan?) {
        let verdict = hilo.map {
            DosePlan.Verdict(tone: Self.watchToneRaw($0), word: $0.palabra, advice: $0.consejo)
        }
        return await repo.seedTodayDose(routineId: routineId, advice: repo.trainingAdvice,
                                        inventory: plates.inventory, serving: serving,
                                        verdict: verdict, routineName: routineName)
    }
}
