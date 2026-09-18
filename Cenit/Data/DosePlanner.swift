import Foundation
import CenitTraining
import CenitAnalytics

// DosePlanner.swift · FER-491 · Ola 2 MOTOR.
//
// Single owner of the day's `DosePlan`. Called from `Repository.seedTodaySlots` after the
// served recipe + progression seed are known. Surfaces only PROJECT; they never re-derive
// series / seed weight / rest. Scientific rules still gated stay inert hooks here:
//   · restBumpSeconds = nil (regla «descansos más largos»)
//   · optional floor = existing `ProgramDeload.lightWorkSetCount` (no new numeric rule)
//   · loadAxis / FER-336 untouched

enum DosePlanner {

    /// One exercise's inputs after `ProgramServing.serve` + `sessionSeed`.
    struct ExerciseInput: Equatable {
        var exerciseId: String
        var name: String
        var order: Int
        var served: RoutineExercise
        var lightWeek: Bool
        var raise: ProgressionPlanner.Raise?
        /// FER-952 · D1: «la última vez» del ejercicio, para que el peso semilla la respete sobre la
        /// rutina-plantilla (la subida ganada/retenida va primero). nil = sin historial.
        var lastWeightKg: Double?
    }

    /// Builds the day's plan. Pure given its inputs (`now` / `dayKey` injected for determinism).
    static func plan(routineId: String,
                     routineName: String,
                     programWeek: Int?,
                     deload: Bool,
                     verdict: DosePlan.Verdict,
                     advice: TrainingRegulation.Advice,
                     exercises: [ExerciseInput],
                     computedAt: Date,
                     dayKey: String) -> DosePlan {
        let markOptional = !deload && (advice == .lighter || advice == .recover)
        let doseExercises: [DoseExercise] = exercises.enumerated().map { idx, input in
            let held: DoseRaise? = {
                guard let raise = input.raise, raise.waiting else { return nil }
                return DoseRaise(fromKg: raise.fromKg, toKg: raise.toKg, phrase: raise.phrase)
            }()
            let rawSets: [DoseSet] = input.served.plannedSets.map { set in
                var seedKg = set.weightKg
                // Seed precedence (FER-E + FER-952): subida ganada/retenida primero; luego «la última
                // vez» gana a la rutina-plantilla; el peso de la plantilla es el último recurso.
                if set.kind == .work {
                    if let held {
                        seedKg = held.fromKg
                    } else if let raise = input.raise, !raise.waiting {
                        seedKg = raise.toKg
                    } else if let last = input.lastWeightKg {
                        seedKg = last
                    }
                }
                return DoseSet(reps: set.reps, repsRangeTop: set.repsRangeTop,
                               seedWeightKg: seedKg, kind: set.kind, optional: false)
            }
            let sets = DosePlanMath.markOptionalSets(rawSets, markOptional: markOptional && !input.lightWeek)
            return DoseExercise(
                exerciseId: input.exerciseId,
                name: input.name,
                order: input.order >= 0 ? input.order : idx,
                workSets: sets,
                restSeconds: input.served.restSeconds,
                restMode: input.served.restMode.rawValue,
                hrRestReference: input.served.hrRestReference.rawValue,
                hrRestValue: input.served.hrRestValue,
                restBumpSeconds: nil,
                heldRaise: held,
                lightWeek: input.lightWeek)
        }
        return DosePlan(
            computedAt: computedAt,
            dayKey: dayKey,
            routineId: routineId,
            routineName: routineName,
            programWeek: programWeek,
            deload: deload,
            verdict: verdict,
            exercises: doseExercises)
    }

    /// Watch projection: the full typed plan (no ACWR ratio). Additive wire case.
    static func mirrorMessage(from plan: DosePlan) -> WorkoutMirrorMessage {
        .dosePlan(plan)
    }

    /// Widget projection: encode the plan into the snapshot's `dosePlanData`. Widget never re-derives.
    static func encodeForWidget(_ plan: DosePlan) -> Data? {
        try? JSONEncoder().encode(plan)
    }

    static func populateWidgetSnapshot(_ snapshot: TrainWidgetSnapshot,
                                       with plan: DosePlan?) -> TrainWidgetSnapshot {
        TrainWidgetSnapshot(
            writtenAt: snapshot.writtenAt,
            today: snapshot.today,
            verdict: snapshot.verdict,
            week: snapshot.week,
            dosePlanData: plan.flatMap(encodeForWidget))
    }
}
