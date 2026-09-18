import Foundation
import CenitTraining
import CenitAnalytics

/// FER-95 · E14 — «fuera de la app»: los dos widgets de pantalla de inicio + el recordatorio del día que
/// toca entrenar. Ver el `.sink` sobre `repo.$dashboard` en `AppModel.init()` que llama a este método.
extension AppModel {

    /// Fetches the split/routines/sessions ONCE and hands them to `TrainWidgetPublisher` (the App-Group
    /// snapshot + widget reload) and `TrainingDayReminder` (the notification plan) — one dashboard
    /// publish costs one store trip, and the two can't drift because they read the SAME split.
    @MainActor
    func publishTrainOutsideApp() async {
        guard let store = await repo.storeHandle() else { return }
        let sched = (try? await store.routineSchedule()) ?? []
        let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let routines = await repo.routines()
        let routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let sessions = await repo.recentSessions(limit: 200)

        // FER-491: populate widget from the same DosePlan owner as Watch/iPhone (never re-derive).
        var dose: DosePlan?
        if let tid = WeeklySplit.todayRoutineId(
            split: split, todayWeekday: Calendar.current.component(.weekday, from: Date())),
           let name = routineNames[tid] {
            let serving = await repo.programServing()
            let hilo = TrainWidgetPublisher.verdict(
                prep: repo.todayPreparedness, fullyLoaded: repo.fullyLoaded,
                healthConnected: healthBridge?.auth == .authorized,
                hasPlan: true,
                primerUsoSinPlan: TrainWidgetPublisher.esPrimerUsoSinPlan(
                    sessionLive: strengthSession != nil, semanaVacia: split.isEmpty))
            let verdict = hilo.map {
                DosePlan.Verdict(tone: $0.tone.rawValue, word: $0.word, advice: $0.advice)
            }
            dose = await repo.seedTodayDose(routineId: tid, advice: repo.trainingAdvice,
                                            inventory: plates.inventory, serving: serving,
                                            verdict: verdict, routineName: name).plan
        }

        TrainWidgetPublisher.publish(split: split, routineNames: routineNames, sessions: sessions,
                                     sessionLive: strengthSession != nil, prep: repo.todayPreparedness,
                                     fullyLoaded: repo.fullyLoaded,
                                     healthConnected: healthBridge?.auth == .authorized,
                                     dosePlan: dose)
        // FER-522: same store trip publishes the routine catalog Siri's RoutineEntityQuery reads
        // (id+name only). One flight with the widget snapshot — no extra store round-trip.
        RoutineCatalogSnapshot.write(RoutineCatalogSnapshot(
            writtenAt: Date(),
            routines: routines.map { .init(id: $0.id, name: $0.name) }))
        await TrainingDayReminder.reschedule(split: split, routineNames: routineNames)
    }
}
