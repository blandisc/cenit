import XCTest
import CenitModels
@testable import CenitAnalytics

// WhatMovesItTests — «Tu patrón» over the FER-438 gate. (FER-438)
//
// The fixtures are the /estadistico gate's, verbatim, with an independent Python oracle (midranks →
// Pearson, exact t tail, Bartlett n_eff, BH) fixing the expected numbers: coefficients to ±0.01, p to an
// order of magnitude. Every relationship has a positive and a negative case; on top, the three pieces
// of the gate that the FER-209 block lacked — the minority-class floor, the effective n, and the
// Benjamini-Hochberg control over the family — each get a fixture that flips the verdict. The three
// lag +1 strain pairs read Spearman's ρ PARTIAL on the same-day strain (the post-implementation gate's
// finding), so their expected coefficients are the partial's — +0.747 where the plain ρ read +0.778 —
// and the calendar fixture that fired at ρ = −0.28 (q = 0.03) reads +0.04.
//
// Notation (CDO): J(i) = (i % 3) − 1 · K(i) = ((7i) % 5) − 2 · W(i) = 1 on i % 7 ∈ {1, 4} (two training
// days a week) else 0 · day(i) = 2026-01-01 + i. Strain = W(i)·(12 + i % 3): 0 on rest days.

final class WhatMovesItTests: XCTestCase {

    // MARK: - Fixture helpers

    private func day(_ i: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let d = cal.date(byAdding: .day, value: i, to: base)!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func J(_ i: Int) -> Double { Double(i % 3) - 1 }
    private func K(_ i: Int) -> Double { Double((7 * i) % 5) - 2 }
    private func W(_ i: Int) -> Double { i >= 0 && (i % 7 == 1 || i % 7 == 4) ? 1 : 0 }
    private func strain(_ i: Int) -> Double { W(i) * Double(12 + i % 3) }
    /// steps[i] = 7000 + 250·(eff − 88) + 400K(i), rounded to a count.
    private func stepsFor(eff: Double, _ i: Int) -> Int {
        let value: Double = 7000 + 250 * (eff - 88) + 400 * K(i)
        return Int(value.rounded())
    }

    private func row(_ i: Int, sleep: Double? = nil, eff: Double? = nil, strain: Double? = nil,
                     steps: Int? = nil, rhr: Double? = nil) -> DailyMetric {
        DailyMetric(day: day(i), totalSleepMin: sleep, efficiency: eff, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr.map { Int($0.rounded()) },
                    avgHrv: nil, recovery: nil, strain: strain, exerciseCount: nil, steps: steps)
    }

    private func candidate(_ rel: WhatMovesItRelationship, in days: [DailyMetric], today: String,
                           gate: WhatMovesItGate = .default) -> WhatMovesItCandidate? {
        WhatMovesItEngine.candidates(days: days, today: today, gate: gate).first { $0.relationship == rel }
    }

    private func finding(_ rel: WhatMovesItRelationship, _ trend: MetricTrend) -> WhatMovesItFinding {
        WhatMovesItFinding(relationship: rel, trend: trend)
    }

    // MARK: - sleep.priorStrain (strain[D] → duration[D+1], Spearman, lag +1)

    func testSleepPriorStrainRisesAfterHardDays() throws {
        // sleep[i] = 420 + 35·W(i−1) + 8K(i): longer the night after each training day.
        let days = (0..<60).map { row($0, sleep: 420 + 35 * W($0 - 1) + 8 * K($0), strain: strain($0)) }
        let c = try XCTUnwrap(candidate(.sleepPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.n, 59)
        XCTAssertEqual(c.r, 0.747, accuracy: 0.01, "the partial; the plain ρ reads +0.778")
        XCTAssertLessThan(c.p, 1e-10)
        XCTAssertEqual(c.nEffective, 59, accuracy: 1e-9, "a 0/not series has ρ₁ < 0 → truncated → n_eff = n")
        XCTAssertTrue(WhatMovesItEngine.family(days: days, today: day(60))["sleep"]?
            .contains(finding(.sleepPriorStrain, .rises)) ?? false)
    }

    func testSleepPriorStrainIgnoresTheCalendarArtefact() throws {
        // sleep[i] = 420 + 35·W(i) + 8K(i): longer ON training days, nothing about the night after. The
        // strain never trains two days running (ρ₁ = −0.39), so the plain lag +1 ρ inherits −0.78·0.39 of
        // the same-day relationship: −0.279, p = 0.032, q = 0.032 — a «shorter the night after» that
        // describes the calendar. Held on today's strain it reads ≈ 0.
        let days = (0..<60).map { row($0, sleep: 420 + 35 * W($0) + 8 * K($0), strain: strain($0)) }
        let strainSeries = (0..<60).map { (day: day($0), value: strain($0)) }
        let sleepSeries = (0..<60).map { (day: day($0), value: 420 + 35 * W($0) + 8 * K($0)) }
        let plain = try XCTUnwrap(CorrelationEngine.spearman(
            CorrelationEngine.pairs(x: strainSeries, y: sleepSeries, lagDays: 1)))
        XCTAssertEqual(plain.r, -0.279, accuracy: 0.01, "what the block asserted before the partial")
        XCTAssertLessThan(plain.pApprox, 0.05)

        let c = try XCTUnwrap(candidate(.sleepPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.n, 59)
        XCTAssertEqual(c.r, 0.042, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        // The auto-lag legitimately fires on this series (a long night is never followed by one); the
        // strain pair does not.
        XCTAssertFalse(WhatMovesItEngine.family(days: days, today: day(60))["sleep"]?
            .contains { $0.relationship == .sleepPriorStrain } ?? false)
    }

    func testSleepPriorStrainHiddenWithoutRelationship() throws {
        // A period-9 sine unrelated to the training days: ρ ≈ 0.
        let days = (0..<60).map { i in
            row(i, sleep: 420 + 30 * sin(2 * .pi * Double(i) / 9) + 8 * K(i), strain: strain(i))
        }
        let c = try XCTUnwrap(candidate(.sleepPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0.006, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        XCTAssertFalse(WhatMovesItEngine.family(days: days, today: day(60))["sleep"]?
            .contains { $0.relationship == .sleepPriorStrain } ?? false)
    }

    // MARK: - sleep.priorNight (duration[D] → duration[D+1], Pearson, lag +1, raw n)

    func testSleepPriorNightReboundFalls() throws {
        // ±40 alternating: a long night is followed by a short one (process S).
        let days = (0..<60).map { row($0, sleep: 420 + ($0 % 2 == 1 ? -40 : 40) + 6 * J($0)) }
        let c = try XCTUnwrap(candidate(.sleepPriorNight, in: days, today: day(60)))
        XCTAssertEqual(c.n, 59)
        XCTAssertEqual(c.r, -0.9925, accuracy: 0.01)
        XCTAssertLessThan(c.p, 1e-40)
        XCTAssertEqual(c.nEffective, 59, accuracy: 1e-12, "the auto-lag reads p on raw n, never on n_eff")
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)),
                       ["sleep": [finding(.sleepPriorNight, .falls)]])
    }

    func testSleepPriorNightHabitRises() throws {
        // A slow drift (+2/3 min a night): tonight resembles last night.
        let days = (0..<60).map { row($0, sleep: 400 + 2 * Double($0) / 3 + 6 * J($0)) }
        let c = try XCTUnwrap(candidate(.sleepPriorNight, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0.770, accuracy: 0.01)
        XCTAssertLessThan(c.p, 1e-11)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)),
                       ["sleep": [finding(.sleepPriorNight, .rises)]])
    }

    func testSleepPriorNightHiddenOnNoise() throws {
        // A period-4 sine has zero lag-1 autocorrelation.
        let days = (0..<60).map { i in row(i, sleep: 420 + 25 * sin(2 * .pi * Double(i) / 4) + 6 * J(i)) }
        let c = try XCTUnwrap(candidate(.sleepPriorNight, in: days, today: day(60)))
        XCTAssertEqual(c.r, -0.042, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)), [:])
    }

    // MARK: - strain.efficiency (efficiency[D] → strain[D], Spearman, lag 0, floor 56)

    func testStrainEfficiencyRises() throws {
        // eff[i] = 88 + 4J(i) + 5W(i): the nights before a training day are the efficient ones.
        let days = (0..<60).map { row($0, eff: 88 + 4 * J($0) + 5 * W($0), strain: strain($0)) }
        let c = try XCTUnwrap(candidate(.strainEfficiency, in: days, today: day(60)))
        XCTAssertEqual(c.n, 60)
        XCTAssertEqual(c.r, 0.691, accuracy: 0.01)
        XCTAssertLessThan(c.p, 1e-8)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60))["strain"],
                       [finding(.strainEfficiency, .rises)])
        // The same fixture fed the lag +1 pair −0.69·|ρ₁| of that same-day relationship: before the
        // partial, `efficiency.priorStrain` came out «falls» (ρ = −0.292, q = 0.025) — the calendar, not a
        // night. Held on today's strain it reads ≈ 0 and the efficiency sheet says nothing.
        let inherited = try XCTUnwrap(candidate(.efficiencyPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(inherited.r, -0.031, accuracy: 0.01)
        XCTAssertGreaterThan(inherited.p, 0.5)
        XCTAssertNil(WhatMovesItEngine.family(days: days, today: day(60))["sleep_efficiency"])
    }

    func testStrainEfficiencyHiddenWithoutRelationship() throws {
        let days = (0..<60).map { i in
            row(i, eff: 88 + 4 * J(i) + 3 * sin(2 * .pi * Double(i) / 9), strain: strain(i))
        }
        let c = try XCTUnwrap(candidate(.strainEfficiency, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0.120, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.1)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)), [:])
    }

    func testStrainEfficiencyNeedsTheEfficiencyFloor() throws {
        // 50 paired days clear the 42 calendar floor but not the 56 the efficiency pairs demand.
        let days = (0..<50).map { row($0, eff: 88 + 4 * J($0) + 5 * W($0), strain: strain($0)) }
        XCTAssertNil(candidate(.strainEfficiency, in: days, today: day(50)))
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(50)), [:])
        // …and a gate that lowers that floor sees it again.
        let lax = WhatMovesItGate(minPairsWithEfficiency: 42)
        XCTAssertNotNil(candidate(.strainEfficiency, in: days, today: day(50), gate: lax))
    }

    // MARK: - efficiency.priorStrain (strain[D] → efficiency[D+1], Spearman, lag +1, floor 56)

    func testEfficiencyPriorStrainRises() throws {
        let days = (0..<60).map { row($0, eff: 86 + 4 * J($0) + 6 * W($0 - 1), strain: strain($0)) }
        let c = try XCTUnwrap(candidate(.efficiencyPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.n, 59)
        XCTAssertEqual(c.r, 0.548, accuracy: 0.01, "the partial; the plain ρ reads +0.554")
        XCTAssertLessThan(c.p, 1e-4)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60))["sleep_efficiency"],
                       [finding(.efficiencyPriorStrain, .rises)])
    }

    func testEfficiencyPriorStrainHiddenWithoutRelationship() throws {
        let days = (0..<60).map { i in
            row(i, eff: 88 + 4 * J(i) + 3 * sin(2 * .pi * Double(i) / 9), strain: strain(i))
        }
        let c = try XCTUnwrap(candidate(.efficiencyPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.r, -0.012, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        XCTAssertNil(WhatMovesItEngine.family(days: days, today: day(60))["sleep_efficiency"])
    }

    // MARK: - steps.efficiency (efficiency[D] → steps[D], Spearman, lag 0, today excluded)

    private func stepsFixture() -> [DailyMetric] {
        (0..<60).map { i in
            let eff: Double = 88 + 4 * J(i) + 5 * W(i)
            return row(i, eff: eff, steps: stepsFor(eff: eff, i))
        }
    }

    func testStepsEfficiencyRises() throws {
        let days = stepsFixture()
        let c = try XCTUnwrap(candidate(.stepsEfficiency, in: days, today: day(60)))
        XCTAssertEqual(c.n, 60)
        XCTAssertEqual(c.r, 0.871, accuracy: 0.01)
        XCTAssertLessThan(c.p, 1e-17)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)),
                       ["steps": [finding(.stepsEfficiency, .rises)]])
    }

    func testStepsEfficiencyDropsTodaysPartialCount() throws {
        // Day 60 is TODAY with 900 steps so far: a running total, not a finished day. With today's key
        // passed, the pair is byte-identical to the 60-day one; without the filter the point would
        // enter (n = 61, r drops to ≈ 0.84 — and to 0.73 on Pearson).
        let full = stepsFixture()
        let withToday = full + [row(60, eff: 90, steps: 900)]
        let clean = try XCTUnwrap(candidate(.stepsEfficiency, in: full, today: day(60)))
        let filtered = try XCTUnwrap(candidate(.stepsEfficiency, in: withToday, today: day(60)))
        XCTAssertEqual(filtered.n, 60)
        XCTAssertEqual(filtered.r, clean.r, accuracy: 1e-12)
        XCTAssertEqual(filtered.p, clean.p, accuracy: 1e-24)
        let unfiltered = try XCTUnwrap(candidate(.stepsEfficiency, in: withToday, today: day(61)))
        XCTAssertEqual(unfiltered.n, 61)
        XCTAssertEqual(unfiltered.r, 0.842, accuracy: 0.01)
    }

    func testStepsEfficiencyHiddenWithoutRelationship() throws {
        let days = (0..<60).map { i -> DailyMetric in
            let eff: Double = 88 + 4 * J(i) + 3 * sin(2 * .pi * Double(i) / 9)
            let square: Double = i % 4 < 2 ? 1500 : -1500
            let steps: Double = 7000 + square + 400 * K(i)
            return row(i, eff: eff, steps: Int(steps.rounded()))
        }
        let c = try XCTUnwrap(candidate(.stepsEfficiency, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0.007, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)), [:])
    }

    // MARK: - rhr.sleepDuration (duration[D] → rhr[D], Pearson, lag 0, n_eff)

    func testRhrSleepDurationFalls() throws {
        // rhr[i] = 58 − 0.05·(sleep − 420) + K(i): a longer night, a lower resting HR. Stored as an Int
        // (schoolbook rounding of the .5s), which is what moves the oracle's −0.684 to −0.678.
        let days = (0..<60).map { i -> DailyMetric in
            let sl = 420 + 40 * J(i) + 10 * K(i)
            return row(i, sleep: sl, rhr: 58 - 0.05 * (sl - 420) + K(i))
        }
        let c = try XCTUnwrap(candidate(.rhrSleepDuration, in: days, today: day(60)))
        XCTAssertEqual(c.n, 60)
        XCTAssertEqual(c.r, -0.678, accuracy: 0.01)
        XCTAssertLessThan(c.p, 1e-8)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60))["rhr"],
                       [finding(.rhrSleepDuration, .falls)])
    }

    func testRhrSleepDurationHiddenWithoutRelationship() throws {
        let days = (0..<60).map { i in
            row(i, sleep: 420 + 25 * sin(2 * .pi * Double(i) / 4) + 6 * J(i), rhr: 58 + K(i))
        }
        let c = try XCTUnwrap(candidate(.rhrSleepDuration, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.9)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)), [:])
    }

    // MARK: - rhr.priorStrain (strain[D] → rhr[D+1], Spearman, lag +1)

    func testRhrPriorStrainRises() throws {
        let days = (0..<60).map { row($0, strain: strain($0), rhr: 58 + 3 * W($0 - 1) + K($0)) }
        let c = try XCTUnwrap(candidate(.rhrPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.n, 59)
        XCTAssertEqual(c.r, 0.640, accuracy: 0.01, "the partial; the plain ρ reads +0.678")
        XCTAssertLessThan(c.p, 1e-6)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)),
                       ["rhr": [finding(.rhrPriorStrain, .rises)]])
    }

    func testRhrPriorStrainHiddenWithoutRelationship() throws {
        let days = (0..<60).map { row($0, strain: strain($0), rhr: 58 + K($0)) }
        let c = try XCTUnwrap(candidate(.rhrPriorStrain, in: days, today: day(60)))
        XCTAssertEqual(c.r, 0.054, accuracy: 0.01)
        XCTAssertGreaterThan(c.p, 0.5)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(60)), [:])
    }

    // MARK: - The three gate pieces

    func testMinorityClassFloorHidesSevenTrainingDays() throws {
        // One training day a week over 49 days: 7 points carry the whole «relationship» (Pearson would
        // read r = +0.75, p = 8e−10 on them). min(#0, #>0) = 7 < 10 → not even a candidate.
        let days = (0..<49).map { i in
            row(i, sleep: 420 + 35 * ((i - 1) % 7 == 3 ? 1.0 : 0.0) + 8 * K(i),
                strain: i % 7 == 3 ? 14 : 0)
        }
        XCTAssertNil(candidate(.sleepPriorStrain, in: days, today: day(49)))
        XCTAssertFalse(WhatMovesItEngine.family(days: days, today: day(49))["sleep"]?
            .contains { $0.relationship == .sleepPriorStrain } ?? false)
        // At a floor of exactly 7 (≥) the same pair is testable again, on Spearman.
        let lax = WhatMovesItGate(minorityFloor: 7)
        let c = try XCTUnwrap(candidate(.sleepPriorStrain, in: days, today: day(49), gate: lax))
        XCTAssertEqual(c.n, 48)
        XCTAssertEqual(c.r, 0.606, accuracy: 0.01, "the partial; the plain ρ reads +0.619")
    }

    func testEffectiveNFlipsTheGateOnSmoothSeries() throws {
        // Two period-28 sines five days apart: r = +0.38 on n = 42 says p = 0.014 — a «finding» on raw n.
        // Their lag-1 autocorrelations (≈ 0.93 / 0.83) leave an effective n of ≈ 5.6 → p ≈ 0.49 → nothing.
        // (Resting HR is stored as an Int; rounded, the oracle's +0.381 reads +0.3755.)
        let days = (0..<42).map { i in
            row(i, sleep: 10 * sin(2 * .pi * Double(i) / 28) + 1.5 * J(i) + 400,
                rhr: 10 * sin(2 * .pi * Double(i + 5) / 28) + 1.5 * K(i) + 60)
        }
        let c = try XCTUnwrap(candidate(.rhrSleepDuration, in: days, today: day(42)))
        XCTAssertEqual(c.n, 42)
        XCTAssertEqual(c.r, 0.3755, accuracy: 0.02)
        XCTAssertLessThan(CorrelationEngine.pValue(r: c.r, n: 42), 0.05, "raw n would have passed")
        XCTAssertLessThan(c.nEffective, 8)
        XCTAssertGreaterThan(c.p, 0.3)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(42)), [:])
    }

    func testBenjaminiHochbergControlsTheFamily() throws {
        // Sleep on even days only (so the auto-lag has no consecutive pair and is NOT in the family),
        // resting HR every day — an integer, as stored — with a weak relationship: r = −0.32 on n = 45,
        // p = 0.030.
        func Z(_ i: Int) -> Double { Double((11 * i) % 7) - 3 }
        func sl(_ i: Int) -> Double { 420 + 40 * J(i) + 10 * K(i) }
        func rhr(_ i: Int) -> Double { 58 - 0.096 * (sl(i) - 420) + 5 * Z(i) }
        let alone = (0..<90).map { i in row(i, sleep: i % 2 == 0 ? sl(i) : nil, rhr: rhr(i)) }
        let solo = try XCTUnwrap(candidate(.rhrSleepDuration, in: alone, today: day(90)))
        XCTAssertEqual(solo.n, 45)
        XCTAssertEqual(solo.r, -0.324, accuracy: 0.01)
        XCTAssertEqual(solo.p, 0.030, accuracy: 0.003)
        XCTAssertEqual(solo.q, solo.p, accuracy: 1e-12, "a family of one: q = p")
        XCTAssertEqual(WhatMovesItEngine.family(days: alone, today: day(90)),
                       ["rhr": [finding(.rhrSleepDuration, .falls)]])

        // The same pair with two null strain pairs alongside (strain → sleep, strain → rhr): m = 3 and
        // the weak p sits at rank 1 → q = 0.030 · 3 = 0.09 → the finding is gone. Same numbers, same
        // r, same p; only the family changed.
        let family = (0..<90).map { i in
            row(i, sleep: i % 2 == 0 ? sl(i) : nil, strain: strain(i), rhr: rhr(i))
        }
        let candidates = WhatMovesItEngine.candidates(days: family, today: day(90))
        XCTAssertEqual(candidates.count, 3)
        let inFamily = try XCTUnwrap(candidates.first { $0.relationship == .rhrSleepDuration })
        XCTAssertEqual(inFamily.p, solo.p, accuracy: 1e-12)
        XCTAssertEqual(inFamily.q, 0.090, accuracy: 0.01)
        XCTAssertEqual(WhatMovesItEngine.family(days: family, today: day(90)), [:])
    }

    // MARK: - Sufficiency and scope

    func testTooFewDaysHidesEverything() throws {
        // Thirty days of the strongest fixtures across all five metrics: below every floor → nothing.
        let days = (0..<30).map { i -> DailyMetric in
            let eff: Double = 88 + 4 * J(i) + 5 * W(i)
            let sleep: Double = 420 + 35 * W(i - 1) + 8 * K(i)
            let rhr: Double = 58 + 3 * W(i - 1) + K(i)
            return row(i, sleep: sleep, eff: eff, strain: strain(i), steps: stepsFor(eff: eff, i), rhr: rhr)
        }
        XCTAssertTrue(WhatMovesItEngine.candidates(days: days, today: day(30)).isEmpty)
        XCTAssertEqual(WhatMovesItEngine.family(days: days, today: day(30)), [:])
    }

    func testRowsAfterTodayAreIgnored() throws {
        // A UTC «tomorrow» row carrying wild values must not enter any pair. Today (day 60) is present, so
        // without the `day <= today` guard the phantom day 61 would pair with it (strain[60] → rhr[61]).
        let clean = (0...60).map { row($0, strain: strain($0), rhr: 58 + 3 * W($0 - 1) + K($0)) }
        let withTomorrow = clean + [row(61, sleep: 900, strain: 21, rhr: 120)]
        let a = try XCTUnwrap(candidate(.rhrPriorStrain, in: clean, today: day(60)))
        let b = try XCTUnwrap(candidate(.rhrPriorStrain, in: withTomorrow, today: day(60)))
        XCTAssertEqual(a.n, b.n)
        XCTAssertEqual(a.r, b.r, accuracy: 1e-12)
    }

    func testNoRelationshipTargetsHRV() {
        // The FER-209 HRV block never painted (its series was cleared by the source lens); it is retired
        // rather than revived on SDNN. The family can only ever address these five metrics.
        XCTAssertEqual(Set(WhatMovesItRelationship.allCases.map(\.metricKey)),
                       ["sleep", "strain", "sleep_efficiency", "steps", "rhr"])
    }

    func testCopyKeyIsTheOneHomeOfTheSentence() {
        XCTAssertEqual(finding(.sleepPriorStrain, .rises).copyKey, "patron.sleep.priorStrain.rises")
        XCTAssertEqual(finding(.rhrPriorStrain, .falls).copyKey, "patron.rhr.priorStrain.falls")
        XCTAssertEqual(finding(.stepsEfficiency, .falls).id, "steps.efficiency")
    }
}
