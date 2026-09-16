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
        "train-retenida": { model in
            guard let store = await model.repo.storeHandle() else { return }
            // WIPE + RESEED (mismo motivo que `ScreenshotFixtures.seedTrainingPlan`): el store del
            // arnés persiste entre nodos de una misma corrida, así que una demo previa («train» u
            // otra) tiene que salir primero o el split/las sesiones de hoy quedarían mezclados.
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

            // Rutina de HOY con progresión encendida — el mínimo que ejercita la regla.
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

            // Dos sesiones PREVIAS (no hoy) que cumplen la meta al mismo peso — la racha que gana la
            // subida (idéntico patrón a `SingleOracleSeedTests.earnedHistory()`, ya persistido).
            for daysAgo in [5, 3] {
                guard let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
                let start = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 18 * 3600
                let session = StrengthSession(routineId: routine.id, startTs: start, endTs: start + 40 * 60)
                let sets = (0..<3).map { i in
                    SetEntry(sessionId: session.id, exerciseId: exerciseId, position: i,
                            kind: .work, weightKg: 80, reps: 8, done: true, ts: start + i * 180)
                }
                try? await store.saveSession(session, sets: sets)
            }

            // El veredicto del día: reutiliza el patrón «strained» ya probado — publica el dashboard
            // al final, lo que dispara el `refreshSeq` que hace que `EntrenarView.load()` vea todo lo
            // de arriba junto.
            await ScreenshotFixtures.seed(model, state: "strained")
        },
    ]
}
#endif
