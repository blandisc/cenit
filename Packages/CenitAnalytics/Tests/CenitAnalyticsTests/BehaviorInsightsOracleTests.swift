import XCTest
@testable import CenitAnalytics

/// Behavior effects against the hand-derived oracle: the two group means and their contrast, the
/// pooled Cohen's d, Welch's t with its Satterthwaite degrees of freedom, the significance gates,
/// the eligible-day universe, and the false-discovery-rate correction in the ranking.
final class BehaviorInsightsOracleTests: XCTestCase {

    /// A day key `n` days into January 2026.
    private func day(_ n: Int) -> String { String(format: "2026-01-%02d", n) }

    /// Build an outcome map and a behavior set from two explicit groups: the "with" values land on
    /// the first days, the "without" values on the ones after.
    private func split(with: [Double], without: [Double]) -> (Set<String>, [String: Double]) {
        var outcomes: [String: Double] = [:]
        var behaviorDays: Set<String> = []
        for (i, v) in with.enumerated() {
            outcomes[day(i + 1)] = v
            behaviorDays.insert(day(i + 1))
        }
        for (i, v) in without.enumerated() { outcomes[day(with.count + i + 1)] = v }
        return (behaviorDays, outcomes)
    }

    private func effect(with: [Double], without: [Double]) -> BehaviorEffect? {
        let (days, outcomes) = split(with: with, without: without)
        return BehaviorInsights.effect(behaviorDays: days, outcomeByDay: outcomes,
                                       behavior: "Alcohol", outcome: "Recovery")
    }

    // MARK: - One effect, by hand

    func testEffectMatchesHandComputedMomentsAndContrast() throws {
        let e = try XCTUnwrap(effect(with: [60, 62, 58, 61, 59, 63],
                                     without: [70, 72, 68, 71, 69, 73, 70, 68]))

        XCTAssertEqual(e.behavior, "Alcohol")
        XCTAssertEqual(e.outcome, "Recovery")
        XCTAssertEqual(e.nWith, 6)
        XCTAssertEqual(e.nWithout, 8)
        XCTAssertEqual(e.meanWith, 60.5, accuracy: 1e-12)
        XCTAssertEqual(e.meanWithout, 70.125, accuracy: 1e-12)
        XCTAssertEqual(e.delta, -9.625, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(e.pctChange), -13.725490196078432, accuracy: 1e-12)

        // Pooled d: sp = √((5·3.5 + 7·(91/28))/12) = 1.83428…
        XCTAssertEqual(e.cohensD, -5.247290322400142, accuracy: 1e-12)
        XCTAssertEqual(e.pApprox, 1.2852866266115468e-06, accuracy: 1e-14)
        XCTAssertTrue(e.significant, "p < α and both groups clear the floor")

        // The p really is Welch's t at the Satterthwaite df.
        let welchT = -9.66463146091556
        let welchDF = 10.704893127698876
        XCTAssertEqual(e.pApprox, CorrelationEngine.studentTTwoSided(t: welchT, df: welchDF),
                       accuracy: 1e-12)
    }

    func testDeltaAndEffectSizeCarryTheSameSign() throws {
        let down = try XCTUnwrap(effect(with: [58, 62, 60, 59, 61], without: [78, 82, 80, 79, 81]))
        XCTAssertLessThan(down.delta, 0)
        XCTAssertLessThan(down.cohensD, 0)

        let up = try XCTUnwrap(effect(with: [78, 82, 80, 79, 81], without: [58, 62, 60, 59, 61]))
        XCTAssertGreaterThan(up.delta, 0)
        XCTAssertGreaterThan(up.cohensD, 0)
        XCTAssertEqual(up.delta, -down.delta, accuracy: 1e-12)
        XCTAssertEqual(up.cohensD, -down.cohensD, accuracy: 1e-12)
    }

    func testCleanFiveVersusFiveContrast() throws {
        let e = try XCTUnwrap(effect(with: [58, 62, 60, 59, 61], without: [78, 82, 80, 79, 81]))
        XCTAssertEqual(e.meanWith, 60.0, accuracy: 1e-12)
        XCTAssertEqual(e.meanWithout, 80.0, accuracy: 1e-12)
        XCTAssertEqual(e.delta, -20.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(e.pctChange), -25.0, accuracy: 1e-12)
        XCTAssertEqual(e.cohensD, -12.649110640673516, accuracy: 1e-12)      // −20/√2.5
        XCTAssertEqual(e.pApprox, 4.073918328674927e-08, accuracy: 1e-16)
        // t = −20 at df = 8 (equal groups collapse Satterthwaite to n₁+n₂−2).
        XCTAssertEqual(e.pApprox, CorrelationEngine.studentTTwoSided(t: -20, df: 8), accuracy: 1e-15)
        XCTAssertTrue(e.significant)
    }

    // MARK: - Welch in isolation

    func testWelchOnEqualVariancesCollapsesToThePooledDegreesOfFreedom() throws {
        // m₁ = 60, v₁ = 4, n₁ = 3 against m₂ = 70, v₂ = 4, n₂ = 3.
        let a: [Double] = [58, 60, 62]   // mean 60, sample variance 4
        let b: [Double] = [68, 70, 72]   // mean 70, sample variance 4
        let e = try XCTUnwrap(effect(with: a, without: b))
        XCTAssertEqual(e.pApprox, 0.0036022326091040015, accuracy: 1e-9)
        XCTAssertEqual(e.pApprox, CorrelationEngine.studentTTwoSided(t: -6.123724356957945, df: 4.0),
                       accuracy: 1e-12)
        XCTAssertFalse(e.significant, "3 per side is under the group floor, whatever the p")
    }

    func testNoDispersionAnywhere() throws {
        let same = try XCTUnwrap(effect(with: [50, 50, 50], without: [50, 50, 50]))
        XCTAssertEqual(same.pApprox, 1.0, accuracy: 1e-15, "identical and unvarying: nothing to see")
        XCTAssertEqual(same.cohensD, 0.0, accuracy: 1e-15, "no pooled SD to scale by")

        let apart = try XCTUnwrap(effect(with: [50, 50, 50], without: [60, 60, 60]))
        XCTAssertEqual(apart.pApprox, 0.0, accuracy: 1e-15)
        XCTAssertEqual(apart.cohensD, 0.0, accuracy: 1e-15)
    }

    func testSingleValueGroupContributesNoVarianceTerm() throws {
        let e = try XCTUnwrap(effect(with: [60], without: [70, 72, 68, 71]))
        XCTAssertEqual(e.nWith, 1)
        XCTAssertEqual(e.nWithout, 4)
        XCTAssertGreaterThanOrEqual(e.pApprox, 0)
        XCTAssertLessThanOrEqual(e.pApprox, 1)
        XCTAssertFalse(e.significant)
    }

    // MARK: - Significance gates

    func testGroupFloorGatesSignificanceIndependentlyOfTheP() throws {
        let four = try XCTUnwrap(effect(with: [58, 62, 60, 59], without: [78, 82, 80, 79]))
        XCTAssertLessThan(four.pApprox, 0.05)
        XCTAssertFalse(four.significant, "4 per side is below the floor")

        let five = try XCTUnwrap(effect(with: [58, 62, 60, 59, 61], without: [78, 82, 80, 79, 81]))
        XCTAssertLessThan(five.pApprox, 0.05)
        XCTAssertTrue(five.significant, "5 per side clears it")

        XCTAssertEqual(BehaviorInsights.minGroupForSignificance, 5)
        XCTAssertEqual(BehaviorInsights.alpha, 0.05, accuracy: 1e-15)
    }

    func testHeavilyOverlappingGroupsAreNotSignificant() throws {
        let e = try XCTUnwrap(effect(with: [60, 62, 58, 61, 59, 63],
                                     without: [61, 59, 62, 58, 63, 60]))
        XCTAssertGreaterThan(e.pApprox, 0.05)
        XCTAssertFalse(e.significant)
    }

    func testUncomputableContrastsYieldNothing() throws {
        var outcomes: [String: Double] = [:]
        for i in 1...8 { outcomes[day(i)] = Double(60 + i) }
        let allDays = Set(outcomes.keys)

        XCTAssertNil(BehaviorInsights.effect(behaviorDays: allDays, outcomeByDay: outcomes,
                                             behavior: "Always", outcome: "Recovery"),
                     "logged every day: no 'without' group")
        XCTAssertNil(BehaviorInsights.effect(behaviorDays: [], outcomeByDay: outcomes,
                                             behavior: "Never", outcome: "Recovery"),
                     "never logged: no 'with' group")
        XCTAssertNil(BehaviorInsights.effect(behaviorDays: [day(1)],
                                             outcomeByDay: [day(1): 60, day(2): 70],
                                             behavior: "Thin", outcome: "Recovery"),
                     "two days total is below the variance floor")
    }

    func testABehaviorDayWithNoOutcomeDoesNotCount() throws {
        var outcomes: [String: Double] = [:]
        for i in 1...6 { outcomes[day(i)] = Double(60 + i) }
        // Day 99 is logged but has no outcome row at all.
        let e = try XCTUnwrap(BehaviorInsights.effect(behaviorDays: [day(1), day(2), "2026-04-09"],
                                                      outcomeByDay: outcomes,
                                                      behavior: "Sparse", outcome: "Recovery"))
        XCTAssertEqual(e.nWith, 2)
        XCTAssertEqual(e.nWithout, 4)
    }

    // MARK: - The eligible universe

    /// With an explicit universe a day with no entry is UNKNOWN, not "without". Counting it as
    /// "without" pulls the comparison group toward the population mean and washes the contrast out
    /// — the difference between the two calls below IS the correction.
    func testEligibleUniverseExcludesUnloggedDaysFromBothGroups() throws {
        var outcomes: [String: Double] = [:]
        var adherent: Set<String> = []
        var logged: Set<String> = []

        for i in 1...6 {                       // logged and adherent
            outcomes[day(i)] = 70
            adherent.insert(day(i))
            logged.insert(day(i))
        }
        for i in 7...12 {                      // logged, not adherent
            outcomes[day(i)] = 50
            logged.insert(day(i))
        }
        for i in 13...42 {                     // never logged at all
            outcomes[String(format: "2026-02-%02d", i - 12)] = 60
        }

        let restricted = try XCTUnwrap(
            BehaviorInsights.effect(behaviorDays: adherent, outcomeByDay: outcomes,
                                    behavior: "Diet", outcome: "Recovery", eligibleDays: logged))
        XCTAssertEqual(restricted.nWith, 6)
        XCTAssertEqual(restricted.nWithout, 6)
        XCTAssertEqual(restricted.meanWith, 70.0, accuracy: 1e-12)
        XCTAssertEqual(restricted.meanWithout, 50.0, accuracy: 1e-12)

        let unrestricted = try XCTUnwrap(
            BehaviorInsights.effect(behaviorDays: adherent, outcomeByDay: outcomes,
                                    behavior: "Diet", outcome: "Recovery"))
        XCTAssertEqual(unrestricted.nWith, 6)
        XCTAssertEqual(unrestricted.nWithout, 36)
        XCTAssertEqual(unrestricted.meanWith, 70.0, accuracy: 1e-12)
        XCTAssertEqual(unrestricted.meanWithout, (50 * 6 + 60 * 30) / 36.0, accuracy: 1e-12)

        XCTAssertNotEqual(restricted.meanWithout, unrestricted.meanWithout, accuracy: 1.0)
    }

    // MARK: - Ranking with FDR control

    /// The whole point of the correction: the SAME raw p is significant on its own and not
    /// significant inside a family of ten simultaneous tests.
    func testTheSameRawPChangesVerdictWithTheSizeOfTheFamily() throws {
        // Ten days: five low, five high. One behavior picks out the low five cleanly.
        var outcomes: [String: Double] = [:]
        let low: [Double] = [58, 60, 62, 59, 61]
        let high: [Double] = [61, 63, 65, 62, 64]
        for (i, v) in low.enumerated() { outcomes[day(i)] = v }
        for (i, v) in high.enumerated() { outcomes[day(5 + i)] = v }
        let clean = Set((0..<5).map { day($0) })

        // Nine companions that straddle both halves, so their contrasts are weak.
        var family: [String: Set<String>] = ["a_clean": clean]
        let pattern = [0, 1, 2, 5, 6]
        for shift in 1...9 {
            family["b\(shift)"] = Set(pattern.map { day(($0 + shift) % 10) })
        }

        let alone = BehaviorInsights.rank(behaviors: ["a_clean": clean],
                                          outcomeByDay: outcomes, outcome: "Recovery")
        let inFamily = BehaviorInsights.rank(behaviors: family,
                                             outcomeByDay: outcomes, outcome: "Recovery")

        let solo = try XCTUnwrap(alone.first { $0.behavior == "a_clean" })
        let crowded = try XCTUnwrap(inFamily.first { $0.behavior == "a_clean" })

        XCTAssertEqual(solo.pApprox, crowded.pApprox, accuracy: 1e-15,
                       "the raw p is the same number in both runs")
        XCTAssertGreaterThan(solo.pApprox, BehaviorInsights.alpha / 10)
        XCTAssertLessThan(solo.pApprox, BehaviorInsights.alpha)
        XCTAssertTrue(solo.significant, "alone, it clears α")
        XCTAssertFalse(crowded.significant, "inside ten simultaneous tests, it does not")
    }

    /// Whatever the family, `significant` must be exactly the q-based gate — never the single-test
    /// flag that `effect` set.
    func testRankedSignificanceIsExactlyTheQGate() throws {
        var outcomes: [String: Double] = [:]
        for i in 0..<20 { outcomes[day(i + 1)] = Double(50 + (i * 7) % 23) }

        var family: [String: Set<String>] = [:]
        for k in 0..<6 { family["b\(k)"] = Set((0..<7).map { day(($0 * 3 + k) % 20 + 1) }) }

        let ranked = BehaviorInsights.rank(behaviors: family, outcomeByDay: outcomes, outcome: "Recovery")
        XCTAssertFalse(ranked.isEmpty)

        let qValues = MultipleComparisons.benjaminiHochberg(ranked.map(\.pApprox))
        for (e, q) in zip(ranked, qValues) {
            let expected = q < BehaviorInsights.alpha
                && min(e.nWith, e.nWithout) >= BehaviorInsights.minGroupForSignificance
            XCTAssertEqual(e.significant, expected, "\(e.behavior)")
        }
    }

    func testRankOrderAndSilentDrops() throws {
        var outcomes: [String: Double] = [:]
        for i in 1...12 { outcomes[day(i)] = Double(50 + i) }
        let everyDay = Set(outcomes.keys)

        let family: [String: Set<String>] = [
            "strong": Set((1...6).map { day($0) }),
            "weak": Set([1, 4, 7, 10].map { day($0) }),
            "always": everyDay,          // no "without" group
            "never": [],                 // no "with" group
        ]
        let ranked = BehaviorInsights.rank(behaviors: family, outcomeByDay: outcomes, outcome: "Recovery")

        XCTAssertEqual(Set(ranked.map(\.behavior)), ["strong", "weak"],
                       "uncomputable behaviors are dropped silently")
        // Ordered: significant first, then by |d| descending.
        for (a, b) in zip(ranked, ranked.dropFirst()) {
            if a.significant == b.significant {
                XCTAssertGreaterThanOrEqual(abs(a.cohensD), abs(b.cohensD))
            } else {
                XCTAssertTrue(a.significant)
            }
        }
        XCTAssertTrue(BehaviorInsights.rank(behaviors: [:], outcomeByDay: outcomes,
                                            outcome: "Recovery").isEmpty)
    }

    /// Ties in significance and effect size fall back to the behavior name, so the order is stable.
    func testRankTiesBreakOnTheBehaviorName() throws {
        var outcomes: [String: Double] = [:]
        for i in 1...8 { outcomes[day(i)] = i <= 4 ? 60 : 70 }
        let lowHalf = Set((1...4).map { day($0) })
        let ranked = BehaviorInsights.rank(behaviors: ["zeta": lowHalf, "alpha": lowHalf],
                                           outcomeByDay: outcomes, outcome: "Recovery")
        XCTAssertEqual(ranked.map(\.behavior), ["alpha", "zeta"])
    }
}
