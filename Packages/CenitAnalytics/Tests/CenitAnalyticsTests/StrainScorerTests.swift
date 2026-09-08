import XCTest
import Foundation
import BiometricStreams
@testable import CenitAnalytics

/// Cardiovascular load, checked against the published chain rather than against a previous run:
/// Karvonen (1957) reserve → Edwards (1993) or Banister (1991) TRIMP → logarithmic compression to
/// the published 0–21 scale.
///
/// Every expected number below is derived from those formulas by hand, with the derivation written
/// next to it. `ln(7201) = 8.8819752…`, so `ln(7201)/21 = 0.4229512…`.
final class StrainScorerTests: XCTestCase {

    /// `n` samples one second apart at a fixed pulse.
    private func series(_ n: Int, bpm: Int, every: Int = 1, from: Int = 0) -> [HRSample] {
        (0..<n).map { HRSample(ts: from + $0 * every, bpm: bpm) }
    }

    // MARK: - Maximum heart rate

    func testTanakaAndTheLastResortEstimator() {
        XCTAssertEqual(StrainScorer.tanakaHRmax(age: 30), 187.0, accuracy: 1e-9)  // 208 − 0.7×30
        XCTAssertEqual(StrainScorer.defaultMaxHR(age: 30), 190)                   // 220 − 30
    }

    // MARK: - The 0–21 scale

    /// Edwards' ceiling is the top weight held for a whole day: 5 × 1440 = 7200. With the `+1` the
    /// formula carries, that lands exactly on 21.
    func testTheCeilingOfTheScaleIsEdwardsAllDayMaximum() {
        XCTAssertEqual(StrainScorer.trimpToStrain(7200), 21.0, accuracy: 1e-9)
    }

    func testNonPositiveWorkIsZeroNotANegativeLogarithm() {
        XCTAssertEqual(StrainScorer.trimpToStrain(0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.trimpToStrain(-5), 0.0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.strainToTrimp(0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.strainToTrimp(-1), 0.0, accuracy: 1e-12)
    }

    func testCompressionMatchesTheFormulaToTwoDecimals() {
        // 21·ln(101)/ln(7201) = 21 × 4.6151205 / 8.8819752 = 10.9117 → 10.91
        XCTAssertEqual(StrainScorer.trimpToStrain(100), 10.91, accuracy: 1e-9)
        // 21·ln(51)/ln(7201) = 21 × 3.9318256 / 8.8819752 =  9.2962 →  9.30
        XCTAssertEqual(StrainScorer.trimpToStrain(50), 9.30, accuracy: 1e-9)
    }

    /// The inverse is analytically exact; the round trip is not, because the forward direction rounds
    /// to the two decimals the app shows. Compare it RELATIVELY, never at ±1e-6.
    func testRoundTripIsFaithfulOnlyToTheDisplayedPrecision() {
        let back = StrainScorer.strainToTrimp(StrainScorer.trimpToStrain(100))
        XCTAssertEqual(back / 100.0, 1.0, accuracy: 0.003, "within ~0.3 % relative")
        XCTAssertNotEqual(back, 100.0, accuracy: 1e-6, "the rounding is real, not noise")
    }

    /// Least squares through the origin in log space recovers the base exactly from exact data.
    func testDenominatorFitRecoversTheBaseItGenerated() throws {
        let d = 5000.0
        let pairs = [10.0, 50, 120, 400, 1500].map {
            (trimp: $0, strain: StrainScorer.maxStrain * log($0 + 1) / log(d))
        }
        XCTAssertEqual(try StrainScorer.fitStrainDenominator(pairs), d, accuracy: 1.0)
    }

    func testDenominatorFitRefusesTooLittleData() {
        XCTAssertThrowsError(try StrainScorer.fitStrainDenominator([(100, 10)])) {
            XCTAssertEqual($0 as? StrainScorer.StrainError, .tooFewPairs)
        }
        // Pairs that carry no information (non-positive on either axis) are dropped first.
        XCTAssertThrowsError(try StrainScorer.fitStrainDenominator([(100, 10), (0, 5), (50, 0)])) {
            XCTAssertEqual($0 as? StrainScorer.StrainError, .tooFewPairs)
        }
    }

    // MARK: - Sufficiency

    func testDenseSeriesPassesOnCountAlone() {
        XCTAssertTrue(StrainScorer.hasEnoughData(series(600, bpm: 120)))
        XCTAssertFalse(StrainScorer.hasEnoughData(series(599, bpm: 120)),
                       "one reading short, with no span to fall back on")
    }

    /// The sparse branch exists so a low-cadence source is not left unscored for hours. It needs both
    /// a minimum of readings AND a minimum span, and the boundary is exact.
    func testSparseBranchNeedsBothReadingsAndSpan() {
        XCTAssertFalse(StrainScorer.hasEnoughData(series(19, bpm: 150, every: 60)),
                       "19 readings is under the sparse minimum however long the span")
        XCTAssertFalse(StrainScorer.hasEnoughData(series(20, bpm: 150, every: 20)),
                       "20 readings spanning 380 s is under the span minimum")
        var justShort = series(20, bpm: 150, every: 30)          // spans 570 s
        XCTAssertFalse(StrainScorer.hasEnoughData(justShort))
        justShort[19] = HRSample(ts: 600, bpm: 150)              // spans exactly 600 s
        XCTAssertTrue(StrainScorer.hasEnoughData(justShort), "the span boundary is inclusive")
    }

    // MARK: - Scoring

    /// 600 s at 96 %HRR is Edwards weight 5 throughout: TRIMP = 600 × 5 / 60 = 50 → 9.30.
    func testEdwardsLoadMatchesTheHandDerivedTRIMP() {
        let s = StrainScorer.strain(series(600, bpm: 185), maxHR: 190, restingHR: 60)
        XCTAssertEqual(try XCTUnwrap(s), 9.30, accuracy: 0.01)
    }

    /// 21 readings 30 s apart: the median spacing is 30 s = 0.5 min, so TRIMP = 21 × 5 × 0.5 = 52.5,
    /// and 21·ln(53.5)/ln(7201) = 9.4093.
    func testMedianSpacingSetsTheDurationEachReadingStandsFor() {
        let s = StrainScorer.strain(series(21, bpm: 185, every: 30), maxHR: 190, restingHR: 60)
        XCTAssertEqual(try XCTUnwrap(s), 9.41, accuracy: 0.01)
    }

    /// Using the MEDIAN rather than the first gap is what stops one anomalous separation at the start
    /// of a series from rescaling the load of the whole day.
    func testOneAnomalousLeadingGapDoesNotRescaleTheDay() throws {
        var hr = series(600, bpm: 185)
        let baseline = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, restingHR: 60))
        hr[0] = HRSample(ts: -60, bpm: 185)
        let withGap = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, restingHR: 60))
        XCTAssertEqual(withGap / baseline, 1.0, accuracy: 0.01)
        XCTAssertLessThan(withGap, 10.0)
    }

    func testUnmeasurableIsNilAndNeverZero() {
        XCTAssertNil(StrainScorer.strain(series(599, bpm: 185), maxHR: 190),
                     "not enough data is «not measured», which is not the same as «no effort»")
        XCTAssertNil(StrainScorer.strain(series(600, bpm: 185), maxHR: 60, restingHR: 60),
                     "no reserve between rest and maximum")
        XCTAssertNil(StrainScorer.strain(series(600, bpm: 185), maxHR: 50, restingHR: 60))
    }

    func testMoreTimeAndMoreIntensityBothRaiseTheLoad() throws {
        let short = try XCTUnwrap(StrainScorer.strain(series(600, bpm: 185), maxHR: 190, restingHR: 60))
        let long = try XCTUnwrap(StrainScorer.strain(series(1200, bpm: 185), maxHR: 190, restingHR: 60))
        XCTAssertGreaterThan(long, short)

        let easy = try XCTUnwrap(StrainScorer.strain(series(600, bpm: 155), maxHR: 190, restingHR: 60))
        let hard = try XCTUnwrap(StrainScorer.strain(series(600, bpm: 185), maxHR: 190, restingHR: 60))
        XCTAssertGreaterThan(hard, easy)   // 73 %HRR → weight 3 vs 96 %HRR → weight 5
    }

    func testBanisterStaysOnTheScale() throws {
        let s = try XCTUnwrap(StrainScorer.strain(series(600, bpm: 185), maxHR: 190,
                                                  restingHR: 60, method: .banister))
        XCTAssertGreaterThan(s, 0)
        XCTAssertLessThanOrEqual(s, StrainScorer.maxStrain)
    }

    /// Edwards weights by zone and knows nothing about sex; Banister's exponent does.
    func testOnlyBanisterDependsOnSex() throws {
        let hr = series(600, bpm: 185)
        XCTAssertEqual(StrainScorer.strain(hr, maxHR: 190, sex: "male"),
                       StrainScorer.strain(hr, maxHR: 190, sex: "female"))
        let m = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, method: .banister, sex: "male"))
        let f = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, method: .banister, sex: "female"))
        XCTAssertNotEqual(m, f, accuracy: 1e-9)
    }

    // MARK: - The primitives the incremental fold reproduces

    func testPercentileIsHyndmanAndFanTypeSeven() {
        let v = [10.0, 20, 30, 40]
        XCTAssertEqual(StrainScorer.percentile(v, 50), 25.0, accuracy: 1e-9)   // pos 1.5 → 20 + 0.5×10
        XCTAssertEqual(StrainScorer.percentile(v, 0), 10.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.percentile(v, 100), 40.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.percentile([], 50), 0.0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.percentile([7.0], 99), 7.0, accuracy: 1e-12)
    }

    func testReserveGuardsAnswerZeroRatherThanDividingByZero() {
        XCTAssertEqual(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: -10), 0, accuracy: 1e-12)
        XCTAssertEqual(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: 0), 0)
        XCTAssertEqual(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: -10), 0)
    }

    func testEdwardsWeightsCutOnTheReservePercentage() {
        // Reserve 100 makes the percentage equal the bpm above rest, so the cut-points are readable.
        let w = { StrainScorer.zoneWeight($0, restingHR: 0, hrReserve: 100) }
        XCTAssertEqual([w(49), w(50), w(59), w(60), w(70), w(80), w(90), w(120)],
                       [0, 1, 1, 2, 3, 4, 5, 5])
    }

    // MARK: - Estimating a maximum from history

    func testShortHistoryFallsBackToAgeThenToNothing() {
        let short = StrainScorer.estimateHRmax([150, 160, 170], age: 30)
        XCTAssertEqual(short.0, 187.0, accuracy: 1e-9)
        XCTAssertEqual(short.1, "tanaka")

        let bare = StrainScorer.estimateHRmax([150], age: nil)
        XCTAssertEqual(bare.0, 0.0, accuracy: 1e-12)
        XCTAssertEqual(bare.1, "unknown")
    }

    /// With enough history the observed high percentile wins, and says so.
    func testLongHistoryPrefersWhatWasActuallyObserved() {
        let history = Array(repeating: 120.0, count: 690) + Array(repeating: 195.0, count: 10)
        let est = StrainScorer.estimateHRmax(history, age: 30)
        XCTAssertEqual(est.0, 195.0, accuracy: 1e-9)   // pos = 0.995 × 699 = 695.5, both neighbours 195
        XCTAssertEqual(est.1, "observed")
    }

    // MARK: - The cumulative curve
    //
    // Its whole reason for existing is that the chart and the headline number cannot contradict each
    // other on screen.

    /// Two phases: an hour easy, then an hour hard.
    private func twoPhases() -> [HRSample] {
        series(3600, bpm: 120) + series(3600, bpm: 185, from: 3600)
    }

    func testCurveEndsExactlyWhereTheNumberDoes() throws {
        let hr = twoPhases()
        for method in [StrainScorer.Method.edwards, .banister] {
            let curve = StrainScorer.cumulativeStrain(hr, maxHR: 190, restingHR: 60, method: method)
            let number = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, restingHR: 60, method: method))
            XCTAssertEqual(try XCTUnwrap(curve.last).strain, number, accuracy: 1e-9)
        }
    }

    /// A fractional maximum must survive the whole way through the curve, unrounded.
    func testCurveHoldsForAFractionalMaximum() throws {
        let hr = twoPhases()
        let maxHR = StrainScorer.tanakaHRmax(age: 33)   // 184.9
        let curve = StrainScorer.cumulativeStrain(hr, maxHR: maxHR, restingHR: 58)
        let number = try XCTUnwrap(StrainScorer.strain(hr, maxHR: maxHR, restingHR: 58))
        XCTAssertEqual(try XCTUnwrap(curve.last).strain, number, accuracy: 1e-9)
    }

    func testCurveIsNonDecreasingAndOnScale() {
        let curve = StrainScorer.cumulativeStrain(twoPhases(), bucketSeconds: 600,
                                                  maxHR: 190, restingHR: 60)
        XCTAssertFalse(curve.isEmpty)
        for i in 1..<curve.count {
            XCTAssertGreaterThan(curve[i].date, curve[i - 1].date)
            XCTAssertGreaterThanOrEqual(curve[i].strain, curve[i - 1].strain)
        }
        for p in curve {
            XCTAssertGreaterThanOrEqual(p.strain, 0)
            XCTAssertLessThanOrEqual(p.strain, StrainScorer.maxStrain)
        }
    }

    /// The bucket size changes how many points come back and nothing else.
    func testBucketSizeChangesDensityNotTheDestination() throws {
        let hr = twoPhases()
        let fine = StrainScorer.cumulativeStrain(hr, bucketSeconds: 300, maxHR: 190, restingHR: 60)
        let coarse = StrainScorer.cumulativeStrain(hr, bucketSeconds: 1800, maxHR: 190, restingHR: 60)
        XCTAssertGreaterThan(fine.count, coarse.count)
        XCTAssertEqual(try XCTUnwrap(fine.last).strain, try XCTUnwrap(coarse.last).strain, accuracy: 1e-9)
    }

    func testCurveIsEmptyWhenTheNumberWouldBeNil() {
        XCTAssertTrue(StrainScorer.cumulativeStrain(series(599, bpm: 185), maxHR: 190).isEmpty)
        XCTAssertTrue(StrainScorer.cumulativeStrain(twoPhases(), bucketSeconds: 0, maxHR: 190).isEmpty)
        XCTAssertTrue(StrainScorer.cumulativeStrain(twoPhases(), bucketSeconds: -900, maxHR: 190).isEmpty)
    }

    /// The sparse sufficiency branch honours the same end-point invariant.
    func testSparseSeriesCurveAlsoEndsWhereItsNumberDoes() throws {
        let hr = series(40, bpm: 140, every: 30)
        let curve = StrainScorer.cumulativeStrain(hr, maxHR: 190, restingHR: 60)
        XCTAssertFalse(curve.isEmpty)
        let number = try XCTUnwrap(StrainScorer.strain(hr, maxHR: 190, restingHR: 60))
        XCTAssertEqual(try XCTUnwrap(curve.last).strain, number, accuracy: 1e-9)
    }
}
