import XCTest
@testable import CenitTraining

/// FER-491 · Ola 2 MOTOR · Codable probe, staleness, determinism, and the two «bajar» families.
final class DosePlanTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func samplePlan(dayKey: String = "2026-09-16",
                            lightWeek: Bool = false,
                            markOptional: Bool = false,
                            heldRaise: DoseRaise? = nil) -> DosePlan {
        let rawSets: [DoseSet] = [
            .init(reps: 8, seedWeightKg: 60, kind: .work, optional: false),
            .init(reps: 8, seedWeightKg: 60, kind: .work, optional: false),
            .init(reps: 8, seedWeightKg: 60, kind: .work, optional: false),
            .init(reps: 8, seedWeightKg: 60, kind: .work, optional: false),
        ]
        let sets = lightWeek
            ? Array(rawSets.prefix(ProgramDeload.lightWorkSetCount(rawSets.count)))
            : DosePlanMath.markOptionalSets(rawSets, markOptional: markOptional)
        let exercise = DoseExercise(
            exerciseId: "sq", name: "Sentadilla", order: 0,
            workSets: sets, restSeconds: 120, restMode: RestMode.fixed.rawValue,
            restBumpSeconds: nil, heldRaise: heldRaise, lightWeek: lightWeek)
        return DosePlan(
            computedAt: fixedNow, dayKey: dayKey,
            routineId: "push", routineName: "Empuje",
            programWeek: 3, deload: lightWeek,
            verdict: .init(tone: "caution", word: "Hoy ve leve", advice: "ve un poco más ligero"),
            exercises: [exercise])
    }

    // MARK: Codable probe (app ↔ widget ↔ Watch wire)

    func testDosePlanCodableRoundTrip() throws {
        let original = samplePlan(
            markOptional: true,
            heldRaise: DoseRaise(fromKg: 60, toKg: 62.5, phrase: "Hiciste 4×8 con 60 kg."))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DosePlan.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.exercises[0].restBumpSeconds, "hook inerte: restBumpSeconds sigue nil")
        XCTAssertEqual(decoded.exercises[0].workSets.filter(\.optional).count, 2)
        XCTAssertEqual(decoded.exercises[0].heldRaise?.toKg, 62.5)
    }

    // MARK: Caducidad

    func testIsStaleMatchesWidgetWindow() {
        let plan = samplePlan()
        XCTAssertFalse(plan.isStale(asOf: fixedNow))
        XCTAssertFalse(plan.isStale(asOf: fixedNow.addingTimeInterval(DosePlan.staleAfter)))
        XCTAssertTrue(plan.isStale(asOf: fixedNow.addingTimeInterval(DosePlan.staleAfter + 1)))
        XCTAssertEqual(DosePlan.staleAfter, 60 * 60 * 24 * 3)
    }

    func testIsForTodayUsesDayKey() {
        let plan = samplePlan(dayKey: "2026-09-16")
        XCTAssertTrue(plan.isForToday(dayKey: "2026-09-16"))
        XCTAssertFalse(plan.isForToday(dayKey: "2026-09-15"))
    }

    func testDayKeyFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15-ish UTC
        let key = DosePlan.dayKey(for: date, calendar: cal)
        XCTAssertEqual(key.count, 10)
        XCTAssertEqual(key.dropFirst(4).prefix(1), "-")
        XCTAssertEqual(key.dropFirst(7).prefix(1), "-")
    }

    // MARK: Determinismo

    func testSameInputsYieldEqualPlans() {
        let a = samplePlan(markOptional: true,
                           heldRaise: DoseRaise(fromKg: 60, toKg: 62.5, phrase: "x"))
        let b = samplePlan(markOptional: true,
                           heldRaise: DoseRaise(fromKg: 60, toKg: 62.5, phrase: "x"))
        XCTAssertEqual(a, b)
    }

    // MARK: Dos familias de «bajar»

    func testLightWeekCutsAndDoesNotMarkOptional() {
        let plan = samplePlan(lightWeek: true, markOptional: false)
        let ex = plan.exercises[0]
        XCTAssertTrue(ex.lightWeek)
        XCTAssertEqual(ex.workSets.count, 2)
        XCTAssertTrue(ex.workSets.allSatisfy { !$0.optional })
    }

    func testOptionalMarksExcessWithoutCutting() {
        let plan = samplePlan(lightWeek: false, markOptional: true)
        let ex = plan.exercises[0]
        XCTAssertFalse(ex.lightWeek)
        XCTAssertEqual(ex.workSets.count, 4)
        XCTAssertEqual(ex.workSets.map(\.optional), [false, false, true, true])
    }

    func testFamiliesAreDistinguishable() {
        let light = samplePlan(lightWeek: true)
        let optional = samplePlan(markOptional: true)
        XCTAssertTrue(light.exercises[0].lightWeek)
        XCTAssertFalse(light.exercises[0].workSets.contains(where: \.optional))
        XCTAssertFalse(optional.exercises[0].lightWeek)
        XCTAssertTrue(optional.exercises[0].workSets.contains(where: \.optional))
    }

    func testRestBumpSecondsHookStaysNil() {
        let plan = samplePlan()
        XCTAssertNil(plan.exercises[0].restBumpSeconds)
    }
}
