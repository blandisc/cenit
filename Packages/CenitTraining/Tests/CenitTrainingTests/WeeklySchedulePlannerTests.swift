import XCTest
@testable import CenitTraining

// FER-377 — the per-group frequency recipe (`StarterGroupSchedule`) and its `taken`-aware placement
// onto a real week (`WeeklySchedulePlanner`). Pure; no store, no app.

final class WeeklySchedulePlannerTests: XCTestCase {

    /// Monday-first display order (Calendar weekday: 2 = Monday … 1 = Sunday).
    private let W = [2, 3, 4, 5, 6, 7, 1]

    /// Compare a session list to an expected `"weekday:templateId"` list (tuples aren't Equatable).
    private func norm(_ s: [StarterGroupSchedule.Session]) -> [String] {
        s.map { "\($0.weekday):\($0.templateId)" }
    }

    // MARK: placement — clean week returns the ideal verbatim (the owner's drawn examples)

    func testFullBodyCleanWeekIsThreeSpreadDays() {
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .fullBody),
                                              taken: [], weekOrder: W)
        XCTAssertEqual(norm(out), ["2:full-body", "4:full-body", "6:full-body"])   // L/X/V, non-consecutive
    }

    func testUpperLowerCleanWeekIsEachHalfTwice() {
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .upperLower),
                                              taken: [], weekOrder: W)
        XCTAssertEqual(norm(out), ["2:upper", "3:lower", "5:upper", "6:lower"])    // each half 2×
    }

    func testPushPullLegsCleanWeekIsSixDaysTwicePerMuscle() {
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .pushPullLegs),
                                              taken: [], weekOrder: W)
        XCTAssertEqual(out.count, 6)
        for id in ["ppl-push", "ppl-pull", "ppl-legs"] {
            XCTAssertEqual(out.filter { $0.templateId == id }.count, 2, "\(id) should run 2×/week")
        }
    }

    // MARK: placement — respecting days the user already scheduled

    func testTakenDayIsNeverOverwritten() {
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .fullBody),
                                              taken: [4], weekOrder: W)
        XCTAssertFalse(out.map(\.weekday).contains(4), "must not schedule onto the taken Wednesday")
        XCTAssertEqual(norm(out), ["2:full-body", "6:full-body", "1:full-body"])   // re-placed to Sunday
    }

    func testFullWeekSchedulesNothing() {
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .pushPullLegs),
                                              taken: Set(W), weekOrder: W)
        XCTAssertTrue(out.isEmpty, "no free days → best-effort empty (routines still get saved by the caller)")
    }

    func testPartialWeekIsBestEffort() {
        // Upper/Lower wants 4 sessions but only 3 days are free → 3 scheduled, none on a taken day.
        let out = WeeklySchedulePlanner.place(ideal: StarterGroupSchedule.ideal(for: .upperLower),
                                              taken: [2, 3, 4, 1], weekOrder: W)
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out.allSatisfy { ![2, 3, 4, 1].contains($0.weekday) })
    }

    // MARK: invariants over every group × a spread of taken configurations

    func testInvariantsHoldEverywhere() {
        let takenConfigs: [Set<Int>] = [[], [2], [4], [2, 3, 4], [2, 6], Set(W)]
        for group in StarterTemplate.Group.allCases {
            let ideal = StarterGroupSchedule.ideal(for: group)
            for taken in takenConfigs {
                let out = WeeklySchedulePlanner.place(ideal: ideal, taken: taken, weekOrder: W)
                XCTAssertTrue(out.allSatisfy { !taken.contains($0.weekday) },
                              "\(group) with taken \(taken): output landed on a taken day")
                XCTAssertLessThanOrEqual(out.count, ideal.count,
                                         "\(group) with taken \(taken): scheduled more than the ideal")
                XCTAssertEqual(Set(out.map(\.weekday)).count, out.count,
                               "\(group) with taken \(taken): a weekday was used twice")
            }
        }
    }
}

// MARK: - The recipe itself

final class StarterGroupScheduleTests: XCTestCase {

    /// Every session references a real template that belongs to the group it's scheduled under.
    func testEveryTemplateIdResolvesInItsGroup() {
        for group in StarterTemplate.Group.allCases {
            for session in StarterGroupSchedule.ideal(for: group) {
                let t = StarterTemplates.byID(session.templateId)
                XCTAssertNotNil(t, "\(group): templateId \(session.templateId) is not in the catalog")
                XCTAssertEqual(t?.group, group, "\(group): \(session.templateId) belongs to \(String(describing: t?.group))")
            }
        }
    }

    /// Weekly frequency per group (day count is programming convention; the ≥2×/muscle floor is the
    /// evidence — Schoenfeld 2016 / ACSM 2009).
    func testWeeklyFrequencies() {
        XCTAssertEqual(StarterGroupSchedule.ideal(for: .fullBody).count, 3)
        XCTAssertEqual(StarterGroupSchedule.ideal(for: .upperLower).count, 4)   // each half 2×
        XCTAssertEqual(StarterGroupSchedule.ideal(for: .pushPullLegs).count, 6) // each muscle 2×
        XCTAssertEqual(StarterGroupSchedule.ideal(for: .home).count, 3)
        XCTAssertEqual(StarterGroupSchedule.ideal(for: .mobility).count, 2)
    }

    /// Single source of spacing: the recipe matches `ProgramTemplate.weekdays` wherever a program
    /// exists, so editing one without the other trips this test.
    func testSpacingMatchesProgramTemplates() {
        let pairs: [(StarterTemplate.Group, String)] = [
            (.fullBody, "full-body-3"), (.upperLower, "upper-lower-4"), (.pushPullLegs, "ppl-6"),
        ]
        for (group, programId) in pairs {
            let recipe = Dictionary(uniqueKeysWithValues: StarterGroupSchedule.ideal(for: group).map { ($0.weekday, $0.templateId) })
            let program = ProgramTemplate.byID(programId)?.weekdays
            XCTAssertEqual(recipe, program, "\(group) spacing diverged from ProgramTemplate \(programId)")
        }
    }
}
