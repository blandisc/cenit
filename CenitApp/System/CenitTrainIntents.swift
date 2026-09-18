#if os(iOS)
import Foundation
import AppIntents

// MARK: - «¿Qué toca hoy?» (FER-522)

/// Spoken answer from the already-published `TrainWidgetSnapshot` — never recomputes, never a score.
struct WhatIsDueTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "What's due today?" }
    static var description = IntentDescription("Hear today's routine and the day's word from Cénit.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = TodaySpokenSummary.from(snapshot: TrainWidgetSnapshot.read())
        return .result(dialog: IntentDialog("\(summary.spokenText)"))
    }
}

// MARK: - «Arranca {rutina}» (FER-522)

/// Opens Cénit into the named routine (or today's guided path). Full-screen session → openAppWhenRun.
struct StartRoutineIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a routine" }
    static var description = IntentDescription("Open Cénit ready to start a routine.")
    static var openAppWhenRun = true

    @Parameter(title: "Routine")
    var routine: RoutineEntity

    init() { routine = RoutineEntity(id: "", name: "") }
    init(routine: RoutineEntity) { self.routine = routine }

    func perform() async throws -> some IntentResult {
        StartRoutineBridge.request(routineId: routine.id)
        return .result()
    }
}

// MARK: - «Registra {peso}×{reps} de {ejercicio}» (FER-522)

/// Enqueues weight×reps into the App-Group inbox. Numbers pass through as-is (no load math).
struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a set" }
    static var description = IntentDescription("Log weight and reps for an exercise in the live session.")
    static var openAppWhenRun = false

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Weight (kg)")
    var weightKg: Double

    @Parameter(title: "Reps")
    var reps: Int

    init() {
        exercise = ExerciseEntity(id: "", name: "")
        weightKg = 0
        reps = 0
    }

    init(exercise: ExerciseEntity, weightKg: Double, reps: Int) {
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Honest gate from the published snapshot — the intent process has no live StrengthSessionModel.
        guard let live = ActiveSessionSnapshot.read(),
              live.exercises.contains(where: { $0.id == exercise.id }) else {
            return .result(dialog: "You don't have an active session. Start your routine and try again.")
        }
        RestActivityBridge.enqueueLogSet(exerciseId: exercise.id, weightKg: weightKg, reps: reps)
        return .result(dialog: "Set logged.")
    }
}
#endif
