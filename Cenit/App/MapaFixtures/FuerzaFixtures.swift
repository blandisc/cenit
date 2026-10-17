#if os(iOS) && DEBUG
import Foundation
import CenitStore
import CenitTraining

/// CEN-43 · fixtures de la raíz de Fuerza (`FuerzaRootView`), usados por `CenitUITests/FuerzaRootUITests`.
/// Deterministas: la rutina se agenda en el día de la semana en que corre la app (nada depende de qué día
/// sea) y cada fixture termina con el bump de `repo.refreshSeq` que hace releer la raíz — sembrar sin ese
/// bump dejaba la raíz mostrando el estado de ANTES de sembrar (CEN-56, defecto 3).
enum FuerzaFixtures {
    static let all: [String: FixtureRegistry.Seed] = [
        /// Rutina «Empuje» (banca + press inclinado) agendada HOY, con una sesión previa de cada ejercicio
        /// (así cada uno trae su «Última vez»), y SIN sesión terminada hoy → la raíz ofrece «Empezar».
        "fuerza-hoy": { model in
            await wipe(model)
            await seedEmpujeHoy(model)
            model.repo.setDashboard(days: [])
        },
        /// CEN-57: la rutina «Empuje» agendada MAÑANA y nada hoy → «Hoy descansas · Sigue: Empuje · mañana».
        "fuerza-descanso": { model in
            await wipe(model)
            await seedEmpujeHoy(model, enDias: 1)
            model.repo.setDashboard(days: [])
        },
        /// Store vacío: sin rutinas ni plan → la puerta de plan (plantillas / importar / crear).
        "fuerza-sin-rutina": { model in
            await wipe(model)
            model.repo.setDashboard(days: [])
        },
    ]

    @MainActor
    private static func wipe(_ model: AppModel) async {
        guard let store = await model.repo.storeHandle() else { return }
        if let stale = try? await store.routines() {
            for r in stale { try? await store.deleteRoutine(id: r.id) }
        }
        for s in (try? await store.recentSessions(limit: 500)) ?? [] {
            try? await store.deleteSession(id: s.id)
        }
        // El programa multisemana sirve rutinas por encima del split semanal (`ProgramServing`): sin
        // borrarlo, un plan instalado antes en el simulador seguía sirviendo «Día B — Tirón».
        try? await store.deleteProgram()
        for wd in 1...7 { try? await store.clearRoutineSchedule(weekday: wd) }
        try? await store.clearInProgressSession()
        model.strengthSession = nil
    }

    @MainActor
    private static func seedEmpujeHoy(_ model: AppModel, enDias: Int = 0) async {
        guard let store = await model.repo.storeHandle() else { return }
        let cal = Calendar(identifier: .gregorian)
        let now = Int(Date().timeIntervalSince1970)
        let bench = "Barbell_Bench_Press_-_Medium_Grip"
        let incline = "Incline_Dumbbell_Press"

        let routine = Routine(name: "Empuje", createdTs: now, updatedTs: now, sortOrder: 0)
        func rex(_ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double) -> RoutineExercise {
            RoutineExercise(routineId: routine.id, exerciseId: eid, position: pos,
                            targetSets: sets, targetReps: reps, targetWeightKg: kg,
                            restMode: .fixed, restSeconds: 90,
                            sets: (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) })
        }
        try? await store.saveRoutine(routine, exercises: [
            rex(bench, 0, sets: 3, reps: 8, kg: 80),
            rex(incline, 1, sets: 3, reps: 10, kg: 26),
        ])
        let dia = cal.date(byAdding: .day, value: enDias, to: Date()) ?? Date()
        let weekday = cal.component(.weekday, from: dia)
        try? await store.setRoutineSchedule(weekday: weekday, routineId: routine.id)

        // Una sesión previa (hace 3 días): da el «Última vez» de cada ejercicio.
        if let day = cal.date(byAdding: .day, value: -3, to: Date()) {
            let start = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 18 * 3600
            let session = StrengthSession(routineId: routine.id, startTs: start, endTs: start + 40 * 60)
            var sets: [SetEntry] = []
            for (pos, spec) in [(bench, 80.0, 8), (incline, 26.0, 10)].enumerated() {
                for i in 0..<3 {
                    sets.append(SetEntry(sessionId: session.id, exerciseId: spec.0, position: pos * 10 + i,
                                         kind: .work, weightKg: spec.1, reps: spec.2, done: true,
                                         ts: start + sets.count * 180))
                }
            }
            try? await store.saveSession(session, sets: sets)
        }
    }
}
#endif
