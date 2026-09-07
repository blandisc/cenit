#if os(iOS) && DEBUG
import Foundation
import StrandTraining

/// Estados de fixture de la familia **EntrenarHerramientas** para el mapa 100 % (FER-381/386).
///
/// `"sesion-en-curso"`: siembra una sesión de fuerza EN MEMORIA (`model.strengthSession`, sin tocar
/// el store) — el mismo patrón que `Cenit/App/AppMapSerieActiva.swift` (`StrengthSessionModel.make` +
/// `PlanSlot`) usa para sus `#Preview` de canvas, adaptado a un `FixtureRegistry.Seed` (una función
/// `(AppModel) async -> Void`) para que el arranque de la app YA tenga la sesión viva y presentada.
///
/// ⚠️ GAP conocido (repórtese al director, FER-386): HOY este seed es **inalcanzable** vía
/// `-cenit.fixture sesion-en-curso`. `ScreenshotFixtures.activeState()`
/// (`Cenit/App/ScreenshotFixtures.swift`) hard-gatea el launch-arg a una whitelist fija
/// (`primed`/`strained`/`balanced`/`rundown`/`insufficient`/`calibrating`/`downloading`/`train`)
/// ANTES de consultar `FixtureRegistry` — cualquier clave nueva de una familia cae a `nil` y nunca
/// llega a sembrar. Ese archivo está fuera del alcance de este lane (regla dura de la ola: solo
/// tocamos los archivos de Entrenar). El seed queda correcto y listo para el día que la whitelist se
/// abra a `FixtureRegistry.all.keys`; MIENTRAS TANTO, ningún nodo de `entrenar.json` lo referencia —
/// los 8 estados de «sesión viva» usan el patrón YA probado `fixture: "train"` + `tapText: "Empezar"`
/// (arranca la sesión por la UI real, como el nodo `sesion` que ya existía en el manifiesto).
enum EntrenarHerramientasFixtures {
    static let all: [String: FixtureRegistry.Seed] = [
        "sesion-en-curso": { model in
            func rex(_ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double) -> RoutineExercise {
                let planned = (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) }
                return RoutineExercise(routineId: "mapa-sesion", exerciseId: eid, position: pos,
                                       targetSets: sets, targetReps: reps, targetWeightKg: kg,
                                       restMode: .fixed, restSeconds: 90, sets: planned)
            }
            let plan = [
                rex("Barbell_Bench_Press_-_Medium_Grip", 0, sets: 4, reps: 8, kg: 80),
                rex("Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
                rex("Dumbbell_Lying_One-Arm_Rear_Lateral_Raise", 2, sets: 3, reps: 12, kg: 8),
            ]
            let slots = plan.map { re -> StrengthSessionModel.PlanSlot in
                // «La última vez»: una entrada previa por ejercicio, para que la tarjeta activa y el
                // modo foco tengan historia que enseñar (mismo truco que `AppMapSerieActiva`).
                let prev = SetEntry(sessionId: "mapa-sesion-prev", exerciseId: re.exerciseId, position: 0,
                                    kind: .work, weightKg: (re.targetWeightKg ?? 20) - 2.5,
                                    reps: max(1, (re.targetReps ?? 8) - 1), done: true, ts: 0)
                return StrengthSessionModel.PlanSlot(re: re, exercise: ExerciseCatalog.byID(re.exerciseId),
                                                     lastSets: [prev])
            }
            let session = StrengthSessionModel.make(routineId: "mapa-sesion", routineName: "Día A — Empuje",
                                                    slots: slots, startTs: Int(Date().timeIntervalSince1970))
            // Ej0 completo → fila hecha; ej1 activo → tarjeta flotante; ej2 → fila por venir (riel +
            // acordeón, el mismo layout que `SerieActivaPreviewCell(scenario: .plan)`).
            for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
            session.currentIndex = 1
            model.strengthSession = session
            model.strengthSheetPresented = true
        },
    ]
}
#endif
