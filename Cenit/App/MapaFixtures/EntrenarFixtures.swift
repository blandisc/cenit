#if os(iOS) && DEBUG
import Foundation
import CenitStore
import CenitTraining

/// Estados de fixture de la familia **Entrenar** para el mapa 100 % (FER-381).
///
/// La ola de captura de esta familia agrega aquí sus estados nuevos — un `"clave": { model in await
/// … }` por estado — y los referencia por `fixture` en su manifiesto `docs/appmap/mapa/entrenar.json`.
/// No toques `ScreenshotFixtures.swift` ni las otras familias.
enum EntrenarFixtures {
    static let all: [String: FixtureRegistry.Seed] = [
        // FER-495: el hub con una subida GANADA pero RETENIDA por el veredicto de hoy — la píldora
        // «Hoy mantengo {ejercicio} en {peso}; la subida queda a un toque en la sesión.»
        // (`EntrenarView.retainedText`). Compone dos patrones YA probados en vez de reinventarlos:
        //   (1) el veredicto: `ScreenshotFixtures.seed(state: "strained")` — la MISMA siembra que le
        //       da a Hoy su «Go light today» (1 eje fuera ⇒ `.caution`; `Repository.trainingAdvice`
        //       lo traduce a `.lighter`). El cálculo del veredicto no se reescribe aquí.
        //   (2) la subida ganada: el mismo plan + historial que `SingleOracleSeedTests.earnedSlot()`/
        //       `earnedHistory()` (banca, 3×8 @ 80 kg, dos sesiones cumplidas, progressionSessions=2,
        //       incremento 2.5 kg). `ProgressionPlanner.evaluate` clasifica `.readyToAdvance`, y como
        //       `.lighter` no permite subir (`TrainingRegulation.allowsRaise`), la degrada a
        //       `.deferred` (`raise.waiting == true`) — exactamente lo que `EntrenarView.load()` lee
        //       para llenar `retainedToday`.
        //
        // ORDEN (capturas reales 2026-09-15): el plan va PRIMERO y «strained» al FINAL. Lo que
        // dispara `EntrenarView.load()` es el bump de `repo.refreshSeq` que hace `repo.setDashboard`
        // dentro de «strained»: si llega antes de sembrar la banca, la portada carga «Descanso» y ya
        // no vuelve a leer. La carrera con `ScreenshotFixtures.seedTrainingPlan` (que antes re-sembraba
        // el plan de demo encima de éste) la cierra `AppModel.init`, que ahora se lo salta para los
        // fixtures de `EntrenarFixtures.all`.
        "train-retenida": { model in
            await seedBenchToday(model, priorSessions: 2)
            await ScreenshotFixtures.seed(model, state: "strained")   // publica al final → load()
        },

        // FER-495: el hub con plan de HOY pero SIN datos de preparación — el hilo (con
        // `-cenit.healthDenied YES`) cae al ramal «Sin Apple Salud, la progresión usa solo tu rutina
        // y lo que registras.» (`EntrenarView.hiloDelVeredicto`), sin que un veredicto fuera de rango
        // compita por la misma línea. UNA sola sesión previa a propósito (`seedBenchToday`,
        // `priorSessions: 1`): no alcanza `progressionSessions=2`, así que `ProgressionMath.classify`
        // se queda en `.inCycle` — sin subida (ni aplicada ni retenida) que mezcle otro estado en la
        // misma captura. Sin llamar a «strained»: `repo.todayPreparedness` queda nil a propósito.
        "train-hoy": { model in
            await seedBenchToday(model, priorSessions: 1)
            // Sin datos de preparación, pero SÍ el bump de `refreshSeq` que relee la portada.
            model.repo.setDashboard(days: [])
        },
    ]

    /// Rutina de HOY con progresión encendida (banca, 3×8 @ 80 kg, sube cada 2 sesiones cumplidas al
    /// mismo peso, +2.5 kg) — compartida por `"train-retenida"` y `"train-hoy"`, que solo difieren en
    /// cuántas sesiones previas ya cumplieron la meta. Hace su propio WIPE primero: el store del
    /// arnés persiste entre nodos de una misma corrida, así que una demo previa (`train`,
    /// `seedTrainingPlan` u otra) tiene que salir antes o el split/las sesiones de hoy quedarían
    /// mezclados. `store.deleteRoutine` ya borra en cascada el horario semanal de esa rutina
    /// (`routineSchedule`, FER-531) — no hace falta limpiarlo aparte.
    @MainActor
    private static func seedBenchToday(_ model: AppModel, priorSessions: Int) async {
        guard let store = await model.repo.storeHandle() else { return }
        if let stale = try? await store.routines() {
            for r in stale { try? await store.deleteRoutine(id: r.id) }
        }
        for s in (try? await store.recentSessions(limit: 500)) ?? [] {
            try? await store.deleteSession(id: s.id)
        }
        try? await store.clearInProgressSession()
        model.strengthSession = nil

        let cal = Calendar(identifier: .gregorian)
        let now = Int(Date().timeIntervalSince1970)
        let exerciseId = "Barbell_Bench_Press_-_Medium_Grip"

        let routine = Routine(name: "Empuje", createdTs: now, updatedTs: now, sortOrder: 0)
        var re = RoutineExercise(routineId: routine.id, exerciseId: exerciseId, position: 0,
                                 targetSets: 3, targetReps: 8, targetWeightKg: 80,
                                 restMode: .fixed, restSeconds: 90)
        re.progressionEnabled = true
        re.progressionSessions = 2
        re.progressionIncrementKg = 2.5
        try? await store.saveRoutine(routine, exercises: [re])
        let weekday = cal.component(.weekday, from: Date())
        try? await store.setRoutineSchedule(weekday: weekday, routineId: routine.id)

        // `priorSessions` sesiones PREVIAS (no hoy) que cumplen la meta al mismo peso — 2 gana la
        // subida (idéntico patrón a `SingleOracleSeedTests.earnedHistory()`); 1 se queda a media
        // racha (`.inCycle`, sin `raise` — ni aplicada ni retenida).
        let priorDaysAgo: [Int] = priorSessions >= 2 ? [5, 3] : [3]
        for daysAgo in priorDaysAgo {
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            let start = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 18 * 3600
            let session = StrengthSession(routineId: routine.id, startTs: start, endTs: start + 40 * 60)
            let sets = (0..<3).map { i in
                SetEntry(sessionId: session.id, exerciseId: exerciseId, position: i,
                        kind: .work, weightKg: 80, reps: 8, done: true, ts: start + i * 180)
            }
            try? await store.saveSession(session, sets: sets)
        }
    }
}
#endif
