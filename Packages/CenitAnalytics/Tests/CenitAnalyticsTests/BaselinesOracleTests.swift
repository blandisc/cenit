import XCTest
@testable import CenitAnalytics

/// Baselines against the hand-derived oracle: descriptive statistics computed from the formula, the
/// EWMA trace night by night, the log-domain geometry, and the discrete rules (seeding, holding,
/// the hard gate, the epoch cut, the prefix invariant).
final class BaselinesOracleTests: XCTestCase {

    /// Resting-HR-like series whose statistics are known by hand: mean 54, sample SD √(60/9).
    private let restingSeries: [Double] = [52, 55, 51, 58, 54, 53, 57, 50, 56, 54]
    /// Sample SD (ddof = 1) of `restingSeries`.
    private let restingSD = 2.581988897471611

    private var restingCfg: MetricCfg { Baselines.metricCfg["resting_hr"]! }

    /// Fold a series of present nights, oldest first.
    private func fold(_ values: [Double], _ cfg: MetricCfg) -> BaselineState {
        Baselines.foldHistory(values.map { Optional($0) }, cfg: cfg)
    }

    // MARK: - Simple rolling window (linear metric)

    func testRollingWindowMatchesHandComputedMeanAndSD() throws {
        let s = Baselines.rollingMeanSD(restingSeries.map { Optional($0) }, cfg: restingCfg, window: 30)

        XCTAssertEqual(s.baseline, 54.0, accuracy: 1e-12)
        XCTAssertEqual(s.nValid, 10)
        XCTAssertEqual(s.status, .provisional)
        XCTAssertFalse(s.logDomain)

        // spread = max(floor, SD₁ / 1.253); the floor (2.0) does not bind here.
        XCTAssertEqual(s.spread, 2.060645568612619, accuracy: 1e-12)
        // …and multiplying back by the bridge returns the sample SD exactly.
        XCTAssertEqual(1.253 * s.spread, restingSD, accuracy: 1e-12)
    }

    func testRollingWindowNormalRangeAndDeviation() throws {
        let s = Baselines.rollingMeanSD(restingSeries.map { Optional($0) }, cfg: restingCfg, window: 30)

        let band = Baselines.normalRange(s, k: 1)
        XCTAssertEqual(band.lowerBound, 51.41801110252839, accuracy: 1e-12)
        XCTAssertEqual(band.upperBound, 56.58198889747161, accuracy: 1e-12)

        let d = Baselines.deviation(62, state: s)
        XCTAssertEqual(d.z, 3.0983866769659336, accuracy: 1e-12)
        XCTAssertEqual(d.delta, 8.0, accuracy: 1e-12)
        XCTAssertEqual(d.ratio, 0.14814814814814814, accuracy: 1e-12)
        XCTAssertFalse(d.inNormalRange)
    }

    /// Cross-check of MAGNITUDE only, against the other canonical robust scale: the scaled MAD,
    /// 1.4826·median|xᵢ − median| (Rousseeuw & Croux 1993). It is not the estimator this engine
    /// uses; it just has to land in the same neighbourhood, which is what makes 1.253·spread
    /// credible as a σ.
    func testScaledMADAgreesInMagnitudeWithTheSigmaBridge() throws {
        let median = HRVAnalyzer.median(restingSeries)
        XCTAssertEqual(median, 54.0, accuracy: 1e-12)
        let scaledMAD = 1.4826 * HRVAnalyzer.median(restingSeries.map { abs($0 - median) })
        XCTAssertEqual(scaledMAD, 2.9652, accuracy: 1e-12)

        // Same order of magnitude as the sample SD; the two z's for 62 stay within ~15 % of each other.
        let zSD = (62 - 54.0) / restingSD
        let zMAD = (62 - median) / scaledMAD
        XCTAssertEqual(zSD, 3.0983866769659336, accuracy: 1e-12)
        XCTAssertEqual(zMAD, 2.697963037906381, accuracy: 1e-12)
    }

    // MARK: - Log domain

    func testLogDomainCentersOnTheGeometricMeanNotTheArithmeticOne() throws {
        // A log-symmetric series: the geometric mean is exactly 50, the arithmetic mean is 52.
        let values: [Double] = [50 / 1.5, 50 / 1.2, 50, 50 * 1.2, 50 * 1.5]
        let s = Baselines.rollingMeanSD(values.map { Optional($0) }, cfg: Baselines.hrvCfg)

        XCTAssertTrue(s.logDomain)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)
        XCTAssertNotEqual(s.baseline, 52.0, accuracy: 1.0)

        // SD₁ of the logs, and the spread it implies once divided by the bridge.
        let sdOfLogs = 0.31435895403577774
        XCTAssertEqual(s.spread, 0.25088503913469895, accuracy: 1e-12)
        XCTAssertEqual(1.253 * s.spread, sdOfLogs, accuracy: 1e-12)
    }

    func testLogDomainBandIsMultiplicativeAndAsymmetricInDisplayUnits() throws {
        let values: [Double] = [50 / 1.5, 50 / 1.2, 50, 50 * 1.2, 50 * 1.5]
        let s = Baselines.rollingMeanSD(values.map { Optional($0) }, cfg: Baselines.hrvCfg)

        let band = Baselines.normalRange(s, k: 1)
        XCTAssertEqual(band.lowerBound, 36.512842623169064, accuracy: 1e-9)
        XCTAssertEqual(band.upperBound, 68.46905966213743, accuracy: 1e-9)
        // Asymmetric in ms: the upper reach is wider than the lower one.
        XCTAssertGreaterThan(band.upperBound - s.baseline, s.baseline - band.lowerBound)
        // …and multiplicative: the two edges are the same ratio away from the center.
        XCTAssertEqual(band.upperBound / s.baseline, s.baseline / band.lowerBound, accuracy: 1e-9)
    }

    func testLogDomainZIsSymmetricInRatio() throws {
        let values: [Double] = [50 / 1.5, 50 / 1.2, 50, 50 * 1.2, 50 * 1.5]
        let s = Baselines.rollingMeanSD(values.map { Optional($0) }, cfg: Baselines.hrvCfg)

        XCTAssertEqual(Baselines.deviation(65, state: s).z, 0.8346008952480201, accuracy: 1e-12)
        // At the center, and equal ratios either side give equal and opposite z. The symmetry is
        // exact in the model but not in binary floating point — `log` is not bit-antisymmetric about
        // a computed geometric center — so it is asserted at 1e-12, not at zero.
        XCTAssertEqual(Baselines.deviation(50, state: s).z, 0.0, accuracy: 1e-12)
        XCTAssertEqual(Baselines.deviation(50 * 1.3, state: s).z,
                       -Baselines.deviation(50 / 1.3, state: s).z, accuracy: 1e-12)
        // delta and ratio stay in DISPLAY units even in log domain.
        let d = Baselines.deviation(65, state: s)
        XCTAssertEqual(d.delta, 15.0, accuracy: 1e-9)
        XCTAssertEqual(d.ratio, 0.3, accuracy: 1e-9)
    }

    // MARK: - EWMA trace, young base

    /// Six nights folded one at a time, against the hand trace. The table it is checked against is
    /// carried to six decimals, so 1e-6 is the tightest honest tolerance for the center and spread;
    /// the derived readings after the sixth night are exact and checked at 1e-9.
    func testSixNightTraceOnAYoungBase() throws {
        let cfg = restingCfg
        let nights: [Double] = [52, 55, 51, 58, 54, 53]
        let expected: [(baseline: Double, spread: Double, n: Int, status: BaselineStatus)] = [
            (52.000000, 2.000000, 1, .calibrating),
            (52.618898, 3.000000, 2, .calibrating),
            (52.284921, 3.000000, 3, .calibrating),
            (53.463938, 3.049873, 4, .provisional),
            (53.574528, 3.000000, 5, .provisional),
            (53.456003, 2.917401, 6, .provisional),
        ]

        var state: BaselineState?
        for (i, v) in nights.enumerated() {
            state = Baselines.update(state, value: v, cfg: cfg)
            let s = try XCTUnwrap(state)
            XCTAssertEqual(s.baseline, expected[i].baseline, accuracy: 1e-6, "night \(i + 1) center")
            XCTAssertEqual(s.spread, expected[i].spread, accuracy: 1e-6, "night \(i + 1) spread")
            XCTAssertEqual(s.nValid, expected[i].n, "night \(i + 1) nValid")
            XCTAssertEqual(s.status, expected[i].status, "night \(i + 1) status")
            XCTAssertEqual(s.nightsSinceUpdate, 0)
        }

        let final = try XCTUnwrap(state)
        XCTAssertEqual(1.253 * final.spread, 3.655503375825673, accuracy: 1e-6)
        let band = Baselines.normalRange(final, k: 1)
        XCTAssertEqual(band.lowerBound, 49.800499514495215, accuracy: 1e-6)
        XCTAssertEqual(band.upperBound, 57.11150626614656, accuracy: 1e-6)
        let d = Baselines.deviation(60, state: final)
        XCTAssertEqual(d.z, 1.7901767381629103, accuracy: 1e-6)
        XCTAssertEqual(d.delta, 6.543997109679111, accuracy: 1e-6)
        XCTAssertEqual(d.ratio, 0.12241837690531865, accuracy: 1e-6)
    }

    /// The EWMA smoothing weight is λ(h) = 1 − 0.5^(1/h): after h nights a value's weight has halved.
    /// Read out of the first fold rather than from a private helper.
    func testSmoothingWeightMatchesTheHalfLifeDefinition() throws {
        // A young base uses `earlyHalfLifeB` (3 nights) for its center.
        let seeded = Baselines.update(nil, value: 52, cfg: restingCfg)
        let stepped = Baselines.update(seeded, value: 55, cfg: restingCfg)
        let lambdaEarly = (stepped.baseline - 52) / (55 - 52)
        XCTAssertEqual(lambdaEarly, 1 - pow(0.5, 1.0 / Baselines.earlyHalfLifeB), accuracy: 1e-12)
        XCTAssertEqual(lambdaEarly, 0.2062994740159002, accuracy: 1e-12)
    }

    // MARK: - The mature path carries no young branch

    /// Hard acceptance criterion: once `nValid ≥ minNightsTrust` the update is exactly the mature
    /// model — mature half-life, gate on, inflation exactly 1.0. Checked against the formula written
    /// out by hand, with no young knob anywhere in it.
    func testMaturePathIsExactlyTheMatureFormula() throws {
        let cfg = restingCfg
        // 20 identical nights: mature, and the spread has settled on the UNinflated floor.
        let mature = fold(Array(repeating: 54.0, count: 20), cfg)
        XCTAssertGreaterThanOrEqual(mature.nValid, Baselines.minNightsTrust)
        XCTAssertEqual(mature.status, .trusted)
        XCTAssertEqual(mature.spread, cfg.floorSpread, accuracy: 1e-12,
                       "inflation must be exactly 1.0 at maturity, not \(Baselines.earlySpreadInflation)")

        // One more night, inside the winsor reach and inside the hard gate.
        let next = Baselines.update(mature, value: 57, cfg: cfg)
        let lambdaB = 1 - pow(0.5, 1 / cfg.halfLifeB)
        let lambdaS = 1 - pow(0.5, 1 / cfg.halfLifeS)
        let reach = Baselines.winsorK * mature.spread          // 3 · 2.0 = 6, so 57 is not clamped
        XCTAssertLessThanOrEqual(abs(57 - mature.baseline), reach)

        let expectedCenter = lambdaB * 57 + (1 - lambdaB) * mature.baseline
        XCTAssertEqual(next.baseline, expectedCenter, accuracy: 1e-12)
        let expectedSpread = max(cfg.floorSpread,
                                 lambdaS * abs(57 - expectedCenter) + (1 - lambdaS) * mature.spread)
        XCTAssertEqual(next.spread, expectedSpread, accuracy: 1e-12)
    }

    func testMatureGateSeesAHardOutlierWithoutFoldingIt() throws {
        let mature = fold(Array(repeating: 50.0, count: 16), Baselines.hrvCfg)
        XCTAssertGreaterThanOrEqual(mature.nValid, Baselines.minNightsTrust)

        let after = Baselines.update(mature, value: 200, cfg: Baselines.hrvCfg)
        XCTAssertEqual(after.baseline, mature.baseline, accuracy: 1e-12, "an outlier must not fold")
        XCTAssertEqual(after.spread, mature.spread, accuracy: 1e-12)
        XCTAssertEqual(after.nValid, mature.nValid)
        XCTAssertEqual(after.nightsSinceUpdate, 0, "the night WAS read, so the gap resets")
    }

    func testYoungBaseHasNoGateSoAGenuineShiftCanCorrectTheSeed() throws {
        let cfg = Baselines.hrvCfg
        let seeded = fold(Array(repeating: 65.0, count: 4), cfg)
        XCTAssertLessThan(seeded.nValid, Baselines.minNightsTrust)

        // One low night already moves a young center (a mature gate would have rejected it).
        let oneNight = Baselines.update(seeded, value: 40, cfg: cfg)
        XCTAssertLessThan(oneNight.baseline, seeded.baseline)

        // And a genuine regime change converges within days.
        let converged = Baselines.foldHistory(
            (Array(repeating: 65.0, count: 4) + Array(repeating: 40.0, count: 7)).map { Optional($0) },
            cfg: cfg)
        XCTAssertLessThan(converged.baseline, 45)
        XCTAssertGreaterThan(converged.baseline, 38)
    }

    // MARK: - Discrete rules

    func testFlatSeriesSettlesOnTheDispersionFloor() throws {
        let s = fold(Array(repeating: 50.0, count: 30), Baselines.hrvCfg)
        XCTAssertEqual(s.baseline, 50.0, accuracy: 1e-9)
        XCTAssertEqual(s.spread, 0.08, accuracy: 1e-12)
        XCTAssertEqual(s.status, .trusted)
    }

    func testLifecycleThresholds() throws {
        let cfg = Baselines.hrvCfg
        let three = fold(Array(repeating: 50.0, count: 3), cfg)
        XCTAssertEqual(three.status, .calibrating)
        XCTAssertFalse(three.usable)
        XCTAssertFalse(three.trusted)

        let four = fold(Array(repeating: 50.0, count: 4), cfg)
        XCTAssertEqual(four.status, .provisional)
        XCTAssertTrue(four.usable)
        XCTAssertFalse(four.trusted)

        let fourteen = fold(Array(repeating: 50.0, count: 14), cfg)
        XCTAssertEqual(fourteen.status, .trusted)
        XCTAssertTrue(fourteen.usable)
        XCTAssertTrue(fourteen.trusted)
    }

    func testStaleAfterTooManyUnseenNights() throws {
        let cfg = Baselines.hrvCfg
        let mature = fold(Array(repeating: 50.0, count: 20), cfg)
        var s = mature
        for _ in 0..<(Baselines.staleDays + 1) { s = Baselines.update(s, value: nil, cfg: cfg) }
        XCTAssertEqual(s.nightsSinceUpdate, Baselines.staleDays + 1)
        XCTAssertEqual(s.status, .stale)
        XCTAssertEqual(s.nValid, mature.nValid)
    }

    func testMissingAndOutOfBoundsNightsHoldTheBaseline() throws {
        let cfg = Baselines.hrvCfg
        let seeded = Baselines.update(nil, value: 50, cfg: cfg)

        let missing = Baselines.update(seeded, value: nil, cfg: cfg)
        XCTAssertEqual(missing.baseline, 50.0, accuracy: 1e-12)
        XCTAssertEqual(missing.spread, seeded.spread, accuracy: 1e-12)
        XCTAssertEqual(missing.nValid, 1)
        XCTAssertEqual(missing.nightsSinceUpdate, 1)

        // 300 ms is past the 250 ceiling: identical to a missing night.
        let outOfRange = Baselines.update(seeded, value: 300, cfg: cfg)
        XCTAssertEqual(outOfRange, missing)
    }

    func testMidpointSeedIsReplacedByTheFirstRealNight() throws {
        let cfg = Baselines.hrvCfg
        let parked = Baselines.update(nil, value: nil, cfg: cfg)
        XCTAssertEqual(parked.baseline, (cfg.minVal + cfg.maxVal) / 2, accuracy: 1e-12)
        XCTAssertEqual(parked.nValid, 0)
        XCTAssertEqual(parked.nightsSinceUpdate, 1)
        XCTAssertEqual(parked.status, .calibrating)

        let anchored = Baselines.update(parked, value: 50, cfg: cfg)
        XCTAssertEqual(anchored.baseline, 50.0, accuracy: 1e-12,
                       "the first real night anchors, it does not drag the midpoint")
        XCTAssertEqual(anchored.spread, cfg.floorSpread, accuracy: 1e-12)
        XCTAssertEqual(anchored.nValid, 1)
        XCTAssertEqual(anchored.nightsSinceUpdate, 0)
    }

    func testRollingWindowFiltersAndTruncates() throws {
        let cfg = Baselines.hrvCfg
        let mixed = Baselines.rollingMeanSD([nil, 50, 300, 50, 50], cfg: cfg)
        XCTAssertEqual(mixed.nValid, 3)
        XCTAssertEqual(mixed.baseline, 50.0, accuracy: 1e-9)

        let none = Baselines.rollingMeanSD([], cfg: cfg)
        XCTAssertEqual(none.nValid, 0)
        XCTAssertEqual(none.status, .calibrating)

        let values = Array(repeating: 100.0, count: 5) + Array(repeating: 50.0, count: 30)
        let windowed = Baselines.rollingMeanSD(values.map { Optional($0) }, cfg: cfg, window: 30)
        XCTAssertEqual(windowed.nValid, 30, "only the trailing window counts")
        XCTAssertEqual(windowed.baseline, 50.0, accuracy: 1e-9)
    }

    func testBothPathsAgreeOnTheFloor() throws {
        let cfg = Baselines.hrvCfg
        let flat = Array(repeating: 50.0, count: 50)
        let rolling = Baselines.rollingMeanSD(flat.map { Optional($0) }, cfg: cfg)
        let folded = fold(flat, cfg)
        XCTAssertEqual(rolling.spread, folded.spread, accuracy: 1e-12)
        XCTAssertEqual(rolling.spread, cfg.floorSpread, accuracy: 1e-12)
    }

    // MARK: - Shrinkage ramp

    func testConfidenceRamp() throws {
        XCTAssertEqual(Baselines.confidence(nValid: 0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: Baselines.minNightsSeed), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: 9), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: Baselines.minNightsTrust), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Baselines.confidence(nValid: 100), 1.0, accuracy: 1e-12)

        for n in 5...Baselines.minNightsTrust {
            XCTAssertGreaterThan(Baselines.confidence(nValid: n), Baselines.confidence(nValid: n - 1))
            XCTAssertLessThanOrEqual(Baselines.confidence(nValid: n), 1.0)
        }
    }

    // MARK: - Epoch cut

    func testEpochDropsEverythingBeforeIt() throws {
        let cfg = restingCfg
        let dated: [(day: String, value: Double?)] = [
            ("2026-06-01", 60), ("2026-06-05", 65), ("2026-06-10", 40), ("2026-06-11", 41),
        ]
        let cut = Baselines.foldHistory(dated, epoch: "2026-06-10", cfg: cfg)
        XCTAssertEqual(cut, fold([40, 41], cfg))
        XCTAssertEqual(cut.nValid, 2)

        let uncut = Baselines.foldHistory(dated, epoch: nil, cfg: cfg)
        XCTAssertEqual(uncut.baseline, fold([60, 65, 40, 41], cfg).baseline, accuracy: 1e-12)

        let beyond = Baselines.foldHistory(dated, epoch: "2027-01-01", cfg: cfg)
        XCTAssertEqual(beyond.nValid, 0)
        XCTAssertEqual(beyond.status, .calibrating)
    }

    // MARK: - Prefix invariant

    /// The whole point of the one-pass version: every element must equal the fold of its own strict
    /// prefix, for every prefix, on every shipped config — nulls and out-of-range nights included.
    func testPrefixStatesEqualTheFoldOfEveryStrictPrefix() throws {
        let series: [Double?] = [nil, 55, 300, 52, nil, 58, 51, 400, 54, 53, 57, nil, 50, 56, 54, 59, 52]
        for key in ["hrv", "resting_hr", "night_thirds_delta"] {
            let cfg = Baselines.metricCfg[key]!
            let prefixes = Baselines.prefixStates(series, cfg: cfg)
            XCTAssertEqual(prefixes.count, series.count, "\(key): one prior per night")
            for i in series.indices {
                XCTAssertEqual(prefixes[i], Baselines.foldHistory(Array(series[0..<i]), cfg: cfg),
                               "\(key): prefix \(i)")
            }
        }
    }

    // MARK: - Shipped configuration

    func testShippedConfigsAreExactlyTheSevenKeys() throws {
        XCTAssertEqual(Set(Baselines.metricCfg.keys),
                       ["hrv", "sdnn", "resting_hr", "resp", "skin_temp", "efficiency", "night_thirds_delta"])
        XCTAssertEqual(Baselines.metricCfg["sdnn"], Baselines.metricCfg["hrv"])
        XCTAssertEqual(Baselines.hrvCfg, Baselines.metricCfg["hrv"])
        XCTAssertEqual(Baselines.restingHRCfg, Baselines.metricCfg["resting_hr"])
        XCTAssertEqual(Baselines.respCfg, Baselines.metricCfg["resp"])

        XCTAssertTrue(Baselines.hrvCfg.logDomain)
        XCTAssertFalse(Baselines.restingHRCfg.logDomain)
        // The one metric that may be negative is never logarithmic.
        let thirds = Baselines.metricCfg["night_thirds_delta"]!
        XCTAssertLessThan(thirds.minVal, 0)
        XCTAssertFalse(thirds.logDomain)
        // Efficiency is a fraction, not a percentage.
        XCTAssertEqual(Baselines.metricCfg["efficiency"]!.maxVal, 1.0, accuracy: 1e-12)
    }
}
