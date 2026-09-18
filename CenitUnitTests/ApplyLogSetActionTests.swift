import XCTest
import CenitTraining
@testable import Cenit

/// FER-522 — `AppModel.applyLogSetAction` reuses StrengthSessionModel mutators; no-op without a
/// live session (mirror of `applyRestAction` guards).
@MainActor
final class ApplyLogSetActionTests: XCTestCase {

    private func slot(exerciseId: String = "bench", name: String = "Bench",
                      sets: Int = 2) -> StrengthSessionModel.PlanSlot {
        let re = RoutineExercise(id: "re-\(exerciseId)", routineId: "rt", exerciseId: exerciseId,
                                 position: 0, targetSets: sets, restMode: .fixed, restSeconds: 90)
        let exercise = Exercise(id: exerciseId, name: name, type: .weightReps, equipment: nil,
                                primaryMuscles: [], secondaryMuscles: [], instructions: [])
        return StrengthSessionModel.PlanSlot(re: re, exercise: exercise, lastSets: [])
    }

    private func logSet(sessionId: String?, exerciseId: String, kg: Double, reps: Int,
                        ts: Date = Date()) -> RestActivityBridge.PendingAction {
        RestActivityBridge.PendingAction(action: .logSet, ts: ts, sessionId: sessionId,
                                         exerciseId: exerciseId, weightKg: kg, reps: reps)
    }

    func testRegistraSerieSobreSesionViva() {
        let model = AppModel()
        model.startStrengthSession(routineId: "rt", routineName: "Empuje", slots: [slot()])
        guard let session = model.strengthSession else {
            XCTFail("expected live session"); return
        }
        let before = session.doneCount
        model.applyLogSetAction(logSet(sessionId: session.id, exerciseId: "bench", kg: 80, reps: 8))
        XCTAssertEqual(session.doneCount, before + 1)
        let logged = session.runs[0].sets.first { $0.done }
        XCTAssertEqual(logged?.weightKg, 80)
        XCTAssertEqual(logged?.reps, 8)
    }

    func testSinSesionEsNoOpSinCrash() {
        let model = AppModel()
        XCTAssertNil(model.strengthSession)
        model.applyLogSetAction(logSet(sessionId: nil, exerciseId: "bench", kg: 80, reps: 8))
        XCTAssertNil(model.strengthSession)
    }

    func testPasaLosNumerosTalCualSinRecalcular() {
        let model = AppModel()
        model.startStrengthSession(routineId: "rt", routineName: "Empuje", slots: [slot()])
        guard let session = model.strengthSession else {
            XCTFail("expected live session"); return
        }
        // Odd numbers the user dictated — must land unchanged (language, not math).
        model.applyLogSetAction(logSet(sessionId: session.id, exerciseId: "bench", kg: 77.5, reps: 11))
        let logged = session.runs[0].sets.first { $0.done }
        XCTAssertEqual(logged?.weightKg, 77.5)
        XCTAssertEqual(logged?.reps, 11)
    }

    func testSesionEquivocadaSeDescarta() {
        let model = AppModel()
        model.startStrengthSession(routineId: "rt", routineName: "Empuje", slots: [slot()])
        guard let session = model.strengthSession else {
            XCTFail("expected live session"); return
        }
        let before = session.doneCount
        model.applyLogSetAction(logSet(sessionId: "other-session", exerciseId: "bench", kg: 80, reps: 8))
        XCTAssertEqual(session.doneCount, before)
    }
}
