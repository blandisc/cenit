import XCTest
import StrandModels
@testable import StrandAnalytics

/// The morning read: which signals fire, how they are printed, and the verdict they add up to.
///
/// Everything here is fixture-driven and deterministic — no clock, no store. The baseline days carry
/// a gentle alternation so the personal spread is small but non-zero, which is what makes «today» a
/// meaningful distance rather than a coin flip.
final class ReadinessEngineTests: XCTestCase {

    /// One day of March 2024, keyed the way the store keys days.
    private func d(_ i: Int, hrv: Double?, rhr: Double?, strain: Double?,
                   resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: rhr.map { Int($0) }, avgHrv: hrv, recovery: nil, strain: strain,
                    exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: resp)
    }

    /// 28 ordinary days (HRV ≈ 60, resting HR ≈ 52, breathing ≈ 14, steady load), and then today.
    private func baseline(todayHrv: Double?, todayRhr: Double?, todayStrain: Double?,
                          todayResp: Double? = nil) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...28 {
            days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: i % 2 == 0 ? 54 : 50,
                          strain: 10, resp: i % 2 == 0 ? 14.5 : 13.5))
        }
        days.append(d(29, hrv: todayHrv, rhr: todayRhr, strain: todayStrain, resp: todayResp))
        return days
    }

    /// The same 29 days, with a skin-temperature deviation on today's row.
    private func baselineWithSkinTemp(_ devC: Double) -> [DailyMetric] {
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: nil, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: nil, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: devC, respRateBpm: nil)
        return days
    }

    // MARK: - Nothing to say

    /// With no rows at all there is no honest read, and nothing is invented to fill the screen.
    func testEmptyInputIsInsufficient() {
        let r = ReadinessEngine.evaluate(days: [])
        XCTAssertEqual(r.level, .insufficient)
        XCTAssertTrue(r.signals.isEmpty)
        XCTAssertNil(r.acwr)
        XCTAssertNil(r.monotony)
    }

    /// Naming a day that is not in the data must NOT fall back to whichever row is newest. A stale
    /// import could otherwise synthesize this morning's read out of a row from months ago.
    func testUnknownTodayKeyIsInsufficientRatherThanTheNewestRow() {
        let days = baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10)
        XCTAssertEqual(ReadinessEngine.evaluate(days: days, today: "2024-04-15").level, .insufficient)
    }

    func testNamedTodayAndDefaultTodayBothRead() {
        let days = baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10)
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days, today: "2024-03-29").level, .insufficient)
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days).level, .insufficient)
    }

    // MARK: - Verdicts

    func testAlignedSignalsReadPrimed() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))
        XCTAssertEqual(r.level, .primed)
        XCTAssertEqual(r.signals.first { $0.key == "hrv" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "rhr" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .good)
    }

    /// Two body signals down at once is the run-down case.
    func testSuppressedHrvAndElevatedRhrReadRundown() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 40, todayRhr: 66, todayStrain: 10))
        XCTAssertEqual(r.signals.first { $0.key == "hrv" }?.flag, .bad)
        XCTAssertEqual(r.signals.first { $0.key == "rhr" }?.flag, .bad)
        XCTAssertEqual(r.level, .rundown)
    }

    /// A load spike with the body neutral: the load is what flags, and it alone is «strained».
    func testLoadSpikeAloneReadsStrained() {
        let r = ReadinessEngine.evaluate(days: acwrSpike())
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .bad)
        XCTAssertEqual(r.level, .strained)
        XCTAssertGreaterThan(r.acwr ?? 0, 1.5)
    }

    // MARK: - Respiratory rate

    func testImplausibleRespRateProducesNoSignal() {
        // A noisy RSA estimate of 40 bpm (outside the 8–25 plausible band) must produce NO resp
        // signal, no matter how far it sits from the ~14 baseline (FER-675).
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10, todayResp: 40))
        XCTAssertFalse(r.signals.contains { $0.key == "respRate" })
        // A sub-physiological 3 bpm is gated the same way.
        let low = ReadinessEngine.evaluate(days: baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10, todayResp: 3))
        XCTAssertFalse(low.signals.contains { $0.key == "respRate" })
    }

    func testNoisyRespRateDoesNotFlipVerdict() {
        // Everything else is aligned (primed). A spurious out-of-band resp (40 bpm) must NOT inject a
        // `.bad` and drag the verdict down — with the gate, the verdict is unchanged from the no-resp read.
        let clean = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))
        let noisy = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10, todayResp: 40))
        XCTAssertEqual(clean.level, .primed)
        XCTAssertEqual(noisy.level, clean.level)
        XCTAssertFalse(noisy.signals.contains { $0.key == "respRate" })
    }

    func testSkinTempRiseFlagsIllness() {
        // Today's skin temp well above the personal baseline (≥0.8 °C) → a "bad" illness
        // signal, which (now counted as a recovery-down driver) pushes readiness to strained.
        let r = ReadinessEngine.evaluate(days: baselineWithSkinTemp(1.0))
        XCTAssertEqual(r.signals.first { $0.key == "skinTemp" }?.flag, .bad)
        XCTAssertEqual(r.level, .strained)
    }

    // MARK: - Compact signal value (the «Señales» read-out, FER-292 v2)

    func testSignalValueIsRawDirectionalDeviation() {
        // HRV well above baseline (good), resting HR well below (good), load steady.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))

        // HRV: above baseline → a POSITIVE σ, even though "above" is the GOOD direction here.
        let hrv = r.signals.first { $0.key == "hrv" }
        XCTAssertEqual(hrv?.flag, .good)
        XCTAssertEqual(hrv?.value?.hasSuffix("σ"), true)
        XCTAssertEqual(hrv?.value?.hasPrefix("+"), true, "HRV above baseline should read as +Nσ")

        // Resting HR: below baseline → a NEGATIVE σ (raw direction), and that's the GOOD direction for RHR.
        // The number is direction, the flag is valence — they can disagree in sign.
        let rhr = r.signals.first { $0.key == "rhr" }
        XCTAssertEqual(rhr?.flag, .good)
        XCTAssertEqual(rhr?.value?.hasSuffix("σ"), true)
        XCTAssertEqual(rhr?.value?.hasPrefix("-"), true, "Resting HR below baseline should read as -Nσ")

        // Load: the bare acute:chronic ratio — no σ, parses as a number near 1.0.
        let acwr = r.signals.first { $0.key == "acwr" }
        XCTAssertNotNil(acwr?.value)
        XCTAssertEqual(acwr?.value?.contains("σ"), false)
        XCTAssertNotNil(acwr?.value.flatMap { Double($0) }, "Load value should parse as a plain ratio")
    }

    func testSkinTempSignalValueIsCelsius() {
        let r = ReadinessEngine.evaluate(days: baselineWithSkinTemp(1.0))
        let skin = r.signals.first { $0.key == "skinTemp" }
        XCTAssertEqual(skin?.value?.contains("°C"), true)
    }

    /// The load sentence glosses the ratio to TWO decimals while the compact read-out shows ONE.
    func testLoadSignalPrintsOneDecimalAndGlossesTwo() {
        let s = ReadinessEngine.acwrSignal(ratio: 1.234)
        XCTAssertEqual(s.value, "1.2")
        XCTAssertTrue(s.detail.contains("1.23"), "the sentence glosses the ratio to two decimals")
        XCTAssertNil(s.z, "load is a ratio, not a deviation in σ")
    }

    // MARK: - Numeric z for axis positioning (FER-476)

    func testNumericZMatchesDisplayedSigmaForZScoredSignals() {
        // HRV above baseline, resting HR below — both z-scored, so both expose a raw signed z.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))

        // The numeric `z` agrees in sign and magnitude with the displayed «+N.Nσ» string (raw direction).
        let hrv = r.signals.first { $0.key == "hrv" }
        XCTAssertNotNil(hrv?.z, "HRV (z-scored) should carry a numeric z")
        XCTAssertGreaterThan(hrv?.z ?? 0, 0, "HRV above baseline → positive z")
        XCTAssertEqual(hrv?.z ?? 0, Double(hrv?.value?.dropLast().replacingOccurrences(of: "+", with: "") ?? "0") ?? 0,
                       accuracy: 0.05, "Numeric z must match the displayed σ string")

        let rhr = r.signals.first { $0.key == "rhr" }
        XCTAssertNotNil(rhr?.z)
        XCTAssertLessThan(rhr?.z ?? 0, 0, "Resting HR below baseline → negative z (raw direction)")
    }

    func testNumericZIsNilForSkinTempAndLoad() {
        // Skin temperature is °C (asymmetric), and load is a ratio — neither carries a σ z.
        let r = ReadinessEngine.evaluate(days: baselineWithSkinTemp(1.0))
        XCTAssertNil(r.signals.first { $0.key == "skinTemp" }?.z, "Skin temperature carries no σ z")
        XCTAssertNil(r.signals.first { $0.key == "acwr" }?.z, "Training load carries no σ z")
    }

    // MARK: - Confidence (short-night) flag

    /// Replace the last day of a baseline with one carrying `sleepMin` of sleep (everything else neutral).
    private func baselineWithSleep(_ sleepMin: Double?) -> [DailyMetric] {
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: sleepMin, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: nil, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
        return days
    }

    func testShortNightFlagsLowConfidence() {
        // 5h12m last night (< 6h) → the morning read is honestly flagged low-confidence.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(312))
        XCTAssertTrue(r.confidenceLow)
        XCTAssertNotNil(r.confidenceNote)
    }

    func testFullNightIsHighConfidence() {
        // 7h24m → normal confidence, no caveat.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(444))
        XCTAssertFalse(r.confidenceLow)
        XCTAssertNil(r.confidenceNote)
    }

    func testMissingSleepIsNotLowConfidence() {
        // No sleep duration recorded (an HR-only day) → we don't claim low confidence.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(nil))
        XCTAssertFalse(r.confidenceLow)
    }

    // MARK: - The verdict sentence

    /// A load spike (→ strained, acwr `.bad`) with the body signals neutral, so `acwr` is the lead.
    private func acwrSpike() -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...21 {
            days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: i % 2 == 0 ? 54 : 50, strain: 5))
        }
        for i in 22...28 {
            days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: i % 2 == 0 ? 54 : 50, strain: 15))
        }
        days.append(d(29, hrv: 60, rhr: 52, strain: 15))
        return days
    }

    func testBridgeNoneWhenInsufficient() {
        let r = ReadinessEngine.evaluate(days: [])
        XCTAssertEqual(r.bridgeKind, .none)
        XCTAssertNil(r.bridge)
    }

    func testBridgeAlignedWhenPrimed() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))
        XCTAssertEqual(r.bridgeKind, .aligned)
        XCTAssertNotNil(r.bridge)
        XCTAssertNil(r.culpritNoun)   // nothing to blame on an aligned day
    }

    func testBridgeRundownWhenSeveralDown() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 40, todayRhr: 66, todayStrain: 10))
        XCTAssertEqual(r.bridgeKind, .rundown)
    }

    /// A strained day names the signal that drove it in the sublabel.
    func testBridgeStrainedFlatNamesTheLeadSignal() {
        let r = ReadinessEngine.evaluate(days: acwrSpike())
        XCTAssertEqual(r.bridgeKind, .strainedFlat)
        XCTAssertNotNil(r.bridge)
        XCTAssertEqual(r.culpritNoun?.lowercased().contains("load"), true)
    }

    // MARK: - Confidence shrinkage (FER-13)

    /// `n` baseline days with the same gentle ±2 HRV variation (mean ≈ 60), then `today`.
    private func hrvHistory(days n: Int, todayHrv: Double) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...n { days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: 52, strain: 10)) }
        days.append(d(n + 1, hrv: todayHrv, rhr: 52, strain: 10))
        return days
    }

    private func severity(_ flag: ReadinessEngine.Flag?) -> Int {
        switch flag {
        case .good, .neutral, .none: return 0
        case .watch: return 1
        case .bad:   return 2
        }
    }

    private func hrvFlag(days n: Int, todayHrv: Double) -> ReadinessEngine.Flag? {
        ReadinessEngine.evaluate(days: hrvHistory(days: n, todayHrv: todayHrv))
            .signals.first { $0.key == "hrv" }?.flag
    }

    /// Across a sweep of suppressed-HRV nights, a thin (provisional) baseline never
    /// flags MORE severely than a long (trusted) one, and for at least one night it
    /// flags strictly LESS severely — the z is shrunk toward neutral on weak evidence
    /// so the engine doesn't sound the alarm prematurely (FER-13).
    func testThinBaselineNeverMoreSevereAndSometimesLess() {
        var sawDowngrade = false
        for today in stride(from: 58.0, through: 50.0, by: -1.0) {
            let thin = severity(hrvFlag(days: 9, todayHrv: today))      // provisional → shrunk
            let trusted = severity(hrvFlag(days: 28, todayHrv: today))  // trusted → unshrunk
            XCTAssertLessThanOrEqual(thin, trusted, "thin baseline more severe at hrv=\(today)")
            if thin < trusted { sawDowngrade = true }
        }
        XCTAssertTrue(sawDowngrade, "shrinkage never downgraded a flag across the sweep")
    }

    // MARK: - Monotony (Foster 1998)

    /// A week of identical load has zero spread: the ratio is undefined, so nothing is reported.
    func testConstantWeekReportsNoMonotony() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10))
        XCTAssertNil(r.monotony, "σ = 0 — a monotony ratio would be a division by zero")
        XCTAssertFalse(r.signals.contains { $0.key == "monotony" })
    }

    /// One varied day in an otherwise identical week: monotony is high and flags for watching.
    func testNearlyConstantWeekFlagsHighMonotony() {
        var days: [DailyMetric] = []
        for i in 1...28 { days.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        days[days.count - 1] = d(28, hrv: nil, rhr: nil, strain: 11)
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertGreaterThanOrEqual(r.monotony ?? 0, 2.0)
        XCTAssertEqual(r.signals.first { $0.key == "monotony" }?.flag, .watch)
    }

    /// A genuinely varied week sits well under the watch threshold and reports no signal.
    func testVariedWeekReportsMonotonyWithoutFlagging() {
        var days: [DailyMetric] = []
        for i in 1...28 { days.append(d(i, hrv: nil, rhr: nil, strain: i % 2 == 0 ? 14.0 : 5.0)) }
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertNotNil(r.monotony)
        XCTAssertLessThan(r.monotony ?? .greatestFiniteMagnitude, 2.0)
        XCTAssertFalse(r.signals.contains { $0.key == "monotony" })
    }

    /// The window is a TRUE trailing calendar week. With only three known days inside it there is no
    /// sample standard deviation worth trusting, and the engine must not reach further back to find a
    /// fourth — that would compare this week against a previous one.
    func testFewerThanFourKnownDaysInTheWeekReportsNoMonotony() {
        var days: [DailyMetric] = []
        for i in 1...22 { days.append(d(i, hrv: nil, rhr: nil, strain: i % 2 == 0 ? 14.0 : 5.0)) }
        // Days 23…29 are the trailing week; only three of them carry a load.
        for i in 23...29 {
            days.append(d(i, hrv: nil, rhr: nil, strain: [23, 26, 29].contains(i) ? 9.0 : nil))
        }
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertNil(r.monotony)
    }

    // MARK: - Small statistics

    func testMeanAndSampleSDGuards() {
        XCTAssertNil(ReadinessEngine.mean([]))
        XCTAssertNil(ReadinessEngine.sampleSD([1.0]))
        XCTAssertNil(ReadinessEngine.sampleSD([]))
    }

    /// Mean 5, sum of squares 32 over 7 degrees of freedom → √(32/7).
    func testSampleSDIsTheNMinusOneDefinition() {
        XCTAssertEqual(ReadinessEngine.sampleSD([2, 4, 4, 4, 5, 5, 7, 9]) ?? 0,
                       (32.0 / 7.0).squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(ReadinessEngine.mean([2, 4, 4, 4, 5, 5, 7, 9]) ?? 0, 5.0, accuracy: 1e-12)
    }

    /// Foster's ratio, hand-derived. A near-flat week: mean 720/7 = 102.857…, sum of squares
    /// 342.857… over 6 degrees of freedom → σ = 7.5593…, ratio = 13.6067…
    /// A genuinely varied week: mean 650/7 = 92.857…, σ = √(17142.857…/6) = 53.4522…, ratio = 1.7372.
    func testFosterMonotonyRatioIsMeanOverSampleSD() {
        let loads: [Double] = [100, 100, 100, 100, 100, 100, 120]
        let m = ReadinessEngine.mean(loads)!
        let sd = ReadinessEngine.sampleSD(loads)!
        XCTAssertEqual(m, 720.0 / 7.0, accuracy: 1e-12)
        XCTAssertEqual(sd, (342.857142857142857 / 6.0).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(m / sd, 13.606721, accuracy: 1e-6)

        let varied: [Double] = [50, 150, 50, 150, 50, 150, 50]
        XCTAssertEqual(ReadinessEngine.mean(varied)! / ReadinessEngine.sampleSD(varied)!,
                       1.737198, accuracy: 1e-6)
    }

    // MARK: - ACWR series (FER-705 — Gabbett 2016; descriptive only, Impellizzeri 2020)

    /// Constant strain → the acute mean equals the chronic mean on every day, so every ratio is 1.0.
    func testAcwrSeriesConstantStrainIsFlat() {
        var days: [DailyMetric] = []
        for i in 1...28 { days.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        let series = ReadinessEngine.acwrSeries(days: days)
        XCTAssertEqual(series.count, 15, "days 14…28 each carry a ratio once minChronic is met")
        for p in series { XCTAssertEqual(p.ratio, 1.0, accuracy: 1e-9) }
        XCTAssertEqual(series.first?.day, "2024-03-14")
        XCTAssertEqual(series.last?.day, "2024-03-28")
    }

    /// A late acute ramp lifts the tail of the series above the flat head (input→output direction).
    func testAcwrSeriesRampLiftsTail() {
        var days: [DailyMetric] = []
        for i in 1...21 { days.append(d(i, hrv: nil, rhr: nil, strain: 5)) }
        for i in 22...28 { days.append(d(i, hrv: nil, rhr: nil, strain: 15)) }
        let series = ReadinessEngine.acwrSeries(days: days)
        XCTAssertEqual(series.first!.ratio, 1.0, accuracy: 1e-9)   // flat prefix
        XCTAssertGreaterThan(series.last!.ratio, 1.5)              // spike reads as a spike
    }

    /// Below `minChronic` (14) strain days there is no honest ratio — the series is empty,
    /// matching the single-day read's calibration gate.
    func testAcwrSeriesEmptyBelowMinChronic() {
        var days: [DailyMetric] = []
        for i in 1...13 { days.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        XCTAssertTrue(ReadinessEngine.acwrSeries(days: days).isEmpty)
    }

    /// The series' last point is EXACTLY today's `evaluate().acwr` — one fold, replayed, so the
    /// card's mini-trend can never end on a different number than the engine's own read.
    func testAcwrSeriesLastPointMatchesEvaluate() {
        var days: [DailyMetric] = []
        for i in 1...28 { days.append(d(i, hrv: nil, rhr: nil, strain: Double(5 + i % 7))) }
        let r = ReadinessEngine.evaluate(days: days)
        let series = ReadinessEngine.acwrSeries(days: days)
        XCTAssertEqual(series.last!.ratio, r.acwr!, accuracy: 1e-9)
        // And `lastN` trims from the head, never the tail.
        let trimmed = ReadinessEngine.acwrSeries(days: days, lastN: 5)
        XCTAssertEqual(trimmed.count, 5)
        XCTAssertEqual(trimmed.last!.ratio, r.acwr!, accuracy: 1e-9)
    }

    /// Unordered input folds identically (the engine sorts by day key, same as `evaluate`).
    func testAcwrSeriesOrderIndependent() {
        var days: [DailyMetric] = []
        for i in 1...28 { days.append(d(i, hrv: nil, rhr: nil, strain: Double(5 + i % 7))) }
        let sorted = ReadinessEngine.acwrSeries(days: days)
        let shuffled = ReadinessEngine.acwrSeries(days: days.shuffled())
        XCTAssertEqual(sorted.map(\.day), shuffled.map(\.day))
        for (a, b) in zip(sorted, shuffled) { XCTAssertEqual(a.ratio, b.ratio, accuracy: 1e-12) }
    }

    // MARK: - Coupled EWMA + active-days piso (CARGA VIVA)

    /// After real load, pure rest days must DECAY the acute leg — not freeze the ratio at 1.0.
    /// 4 active days (clears minActiveDays) + 13 rest → coverage 17 ≥ 14; acute << chronic → rampingDown.
    func testEwmaDecaysInRest() {
        var days: [DailyMetric] = []
        for i in 1...4 { days.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        for i in 5...17 { days.append(d(i, hrv: nil, rhr: nil, strain: 0)) }
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: r.acwr!), .rampingDown)
    }

    /// Once the only real active days age out of the trailing 28-calendar-day window, the piso
    /// reasserts itself — no ACWR from pure zeros, even after the cold-start gate was once cleared.
    func testActiveDaysAgingOutOfChronicWindowYieldsNil() {
        // Use real calendar keys (not "2024-03-32") so DayKey.parseUTC can span into April.
        func key(_ offset: Int) -> String {
            let start = DayKey.parseUTC("2024-03-01")!
            return DayKey.utc(DayKey.utcCalendar.date(byAdding: .day, value: offset, to: start)!)
        }
        func row(_ offset: Int, strain: Double?) -> DailyMetric {
            DailyMetric(day: key(offset), totalSleepMin: nil, efficiency: nil,
                        deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                        avgHrv: nil, recovery: nil, strain: strain, exerciseCount: nil,
                        spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
        }
        var days: [DailyMetric] = []
        // Offsets 0…3 = 4 active days; 4…31 = 28 rest days. At offset 31 the trailing-28 window
        // is offsets 4…31 — none of the original active days remain.
        for i in 0..<4 { days.append(row(i, strain: 10)) }
        for i in 4...31 { days.append(row(i, strain: 0)) }
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertNil(r.acwr)
    }

    /// 14 pure-rest days clear coverage but fail the active-days piso → nil.
    /// 14 days with exactly 4 real loads clear both gates → non-nil.
    func testActiveDaysPisoAtMinChronic() {
        var pureRest: [DailyMetric] = []
        for i in 1...14 { pureRest.append(d(i, hrv: nil, rhr: nil, strain: 0)) }
        XCTAssertNil(ReadinessEngine.evaluate(days: pureRest).acwr)

        var withActive: [DailyMetric] = []
        for i in 1...4 { withActive.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        for i in 5...14 { withActive.append(d(i, hrv: nil, rhr: nil, strain: 0)) }
        XCTAssertNotNil(ReadinessEngine.evaluate(days: withActive).acwr)
    }

    /// Inserting `.missing` (nil strain) calendar days must not move the EWMA vs the same known
    /// sequence without gaps — missing holds, never folds.
    func testMissingDaysHoldEwma() {
        // Version A: 4 active + 10 rest, 14 consecutive calendar days.
        var a: [DailyMetric] = []
        for i in 1...4 { a.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        for i in 5...14 { a.append(d(i, hrv: nil, rhr: nil, strain: 0)) }

        // Version B: same 14 known values, but 3 nil-strain days inserted in the rest run
        // (spans 17 calendar days; still 4 active, all inside the un-aged trailing-28 window).
        var b: [DailyMetric] = []
        for i in 1...4 { b.append(d(i, hrv: nil, rhr: nil, strain: 10)) }
        b.append(d(5, hrv: nil, rhr: nil, strain: 0))
        b.append(d(6, hrv: nil, rhr: nil, strain: nil))   // missing
        b.append(d(7, hrv: nil, rhr: nil, strain: 0))
        b.append(d(8, hrv: nil, rhr: nil, strain: nil))   // missing
        b.append(d(9, hrv: nil, rhr: nil, strain: 0))
        b.append(d(10, hrv: nil, rhr: nil, strain: nil))  // missing
        for i in 11...17 {
            // remaining rest days to match the 10 rest of A (used 3 so far → 7 more)
            b.append(d(i, hrv: nil, rhr: nil, strain: 0))
        }
        // A has 10 rest; B has rest on 5,7,9,11…17 = 3 + 7 = 10 rest + 3 missing. Good.

        let acwrA = ReadinessEngine.evaluate(days: a).acwr
        let acwrB = ReadinessEngine.evaluate(days: b).acwr
        XCTAssertNotNil(acwrA)
        XCTAssertNotNil(acwrB)
        XCTAssertEqual(acwrA!, acwrB!, accuracy: 1e-9)
    }
}
