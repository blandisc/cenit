import XCTest
import BiometricStreams
@testable import CenitAnalytics

/// Time-domain HRV against the Task Force (1996) definitions, plus the artifact rules that run
/// before them (range, then Malik 1989 local median). Every expected value below is derived from the
/// formula by hand, with the derivation written next to it.
final class HRVAnalyzerTests: XCTestCase {

    // MARK: - The primitives, with no cleaning at all

    /// Differences 10, −10, 10 → √(300/3) = 10.
    func testRMSSDOverSuccessiveDifferences() {
        XCTAssertEqual(try XCTUnwrap(HRVAnalyzer.rmssdRaw([800, 810, 800, 810])), 10.0, accuracy: 1e-9)
    }

    /// Mean 805, sum of squares 4 × 25 = 100, over 3 degrees of freedom → √(100/3).
    func testSDNNIsTheSampleStandardDeviation() {
        XCTAssertEqual(try XCTUnwrap(HRVAnalyzer.sdnnRaw([800, 810, 800, 810])),
                       5.773502691896258, accuracy: 1e-12)
    }

    func testPrimitivesRefuseWhatTheyCannotCompute() {
        XCTAssertNil(HRVAnalyzer.rmssdRaw([800]), "no successive pair to difference")
        XCTAssertNil(HRVAnalyzer.rmssdRaw([]))
        XCTAssertNil(HRVAnalyzer.sdnnRaw([800]), "nothing for the n−1 denominator")
        XCTAssertNil(HRVAnalyzer.sdnnRaw([]))
    }

    func testMedianOverEvenAndOddCounts() {
        XCTAssertEqual(HRVAnalyzer.median([3, 1, 2]), 2.0, accuracy: 1e-12)
        XCTAssertEqual(HRVAnalyzer.median([4, 1, 3, 2]), 2.5, accuracy: 1e-12)
        XCTAssertEqual(HRVAnalyzer.median([]), 0.0, accuracy: 1e-12)
    }

    // MARK: - Cleaning

    /// Plausibility bounds are inclusive on both sides (≈200 and ≈30 bpm).
    func testRangeFilterKeepsItsBoundsAndTheOrder() {
        XCTAssertEqual(HRVAnalyzer.rangeFilter([250, 300, 800, 2000, 2100, 1500]),
                       [300, 800, 2000, 1500])
    }

    /// A single wild beat departs from its neighbours' median by 75 %, far past the 20 % rule. Its
    /// neighbours keep a median of 800 and survive — the window excludes the beat being judged, so
    /// one artifact cannot drag its neighbours out with it.
    func testEctopicBeatIsDroppedWithoutTakingItsNeighbours() throws {
        var rr = Array(repeating: 800.0, count: 30)
        rr[15] = 1400
        let clean = HRVAnalyzer.cleanRR(rr)
        XCTAssertEqual(clean.count, 29)
        XCTAssertFalse(clean.contains(1400))
        XCTAssertEqual(try XCTUnwrap(HRVAnalyzer.rmssdRaw(clean)), 0.0, accuracy: 1e-12)
    }

    /// A large but ORDINARY respiratory swing must survive: 900 against a local median of 800 is
    /// 12.5 %, inside the 20 % rule. Rejecting it would flatten exactly the variability being measured.
    func testRespiratorySwingIsNotMistakenForAnArtifact() {
        let rr: [Double] = [800, 900, 800, 900, 800, 900, 800, 900]
        XCTAssertEqual(HRVAnalyzer.ectopicFilter(rr).count, 8)
        XCTAssertEqual(HRVAnalyzer.cleanRR(rr).count, 8)
    }

    // MARK: - Full analysis

    /// 19 clean beats is under the floor: no index is reported, and `nInput` is preserved so a caller
    /// can tell «nothing recorded» from «what was recorded is unusable».
    func testBelowTheBeatFloorEveryIndexIsNilButTheInputCountSurvives() {
        let r = HRVAnalyzer.analyze(rawRR: Array(repeating: 800.0, count: 19))
        XCTAssertNil(r.rmssd)
        XCTAssertNil(r.sdnn)
        XCTAssertNil(r.meanNN)
        XCTAssertNil(r.pnn50)
        XCTAssertEqual(r.nInput, 19)
        XCTAssertEqual(r.nClean, 0)
    }

    /// A perfectly constant series has no successive difference over 50 ms: pNN50 is 0, and finite.
    func testConstantSeriesReportsZeroNotNaN() throws {
        let r = HRVAnalyzer.analyze(rawRR: Array(repeating: 800.0, count: 22))
        XCTAssertEqual(try XCTUnwrap(r.pnn50), 0.0, accuracy: 1e-12)
        XCTAssertTrue(try XCTUnwrap(r.rmssd).isFinite)
        XCTAssertEqual(r.nClean, 22)
    }

    /// Hand-derived over 22 clean beats: Σ(ΔNN)² = 2850 over 21 pairs → √135.714286 = 11.6496…;
    /// mean 17790/22 = 808.63636…, sum of squares 1059.0909… over 21 → √50.43290… = 7.1016…
    func testTheFourIndicesOverAHandDerivedSeries() throws {
        let rr: [Double] = [800, 810, 805, 815, 800, 820, 810, 800, 815, 805, 810,
                            800, 820, 815, 805, 810, 800, 815, 810, 805, 800, 820]
        let r = HRVAnalyzer.analyze(rawRR: rr)
        XCTAssertEqual(r.nClean, 22)
        XCTAssertEqual(try XCTUnwrap(r.rmssd), (2850.0 / 21.0).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rmssd), 11.649647450214351, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.sdnn), 7.101612523427368, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.meanNN), 17790.0 / 22.0, accuracy: 1e-9)
    }

    /// The windowed entry point filters by instant first, inclusive on both sides.
    func testWindowExcludesWhatFallsOutsideIt() throws {
        let a = (0..<31).map { RRInterval(ts: 1000 + $0, rrMs: 800) }
        let b = (0..<31).map { RRInterval(ts: 5000 + $0, rrMs: 600) }
        let r = HRVAnalyzer.analyze(a + b, windowStart: 1000, windowEnd: 1030)
        XCTAssertEqual(r.nInput, 31)
        XCTAssertEqual(r.nClean, 31)
        XCTAssertEqual(try XCTUnwrap(r.rmssd), 0.0, accuracy: 1e-12)
    }

    // MARK: - Segmented RMSSD (the nightly value)

    func testSegmentedNeedsAtLeastOnePair() {
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented([]).nPairs, 0)
        XCTAssertNil(HRVAnalyzer.rmssdSegmented([]).rmssd)
        let one = [TimedNN(ts: 0, nnMs: 1000)]
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(one).nPairs, 0)
        XCTAssertNil(HRVAnalyzer.rmssdSegmented(one).rmssd)
    }

    /// Two consecutive beats, both plausible, both steps inside the relative limit: √(200/2) = 10.
    func testContiguousBeatsPair() throws {
        let nn = [TimedNN(ts: 0, nnMs: 1000), TimedNN(ts: 1, nnMs: 1010), TimedNN(ts: 2, nnMs: 1000)]
        let r = HRVAnalyzer.rmssdSegmented(nn)
        XCTAssertEqual(r.nPairs, 2)
        XCTAssertEqual(try XCTUnwrap(r.rmssd), 10.0, accuracy: 1e-9)
    }

    /// A recording gap breaks the pair across it — and the DIVISOR is the number of valid pairs, not
    /// `N − 1`, so dropping one does not deflate the result.
    func testGapBreaksThePairAcrossIt() throws {
        let nn = [TimedNN(ts: 0, nnMs: 1000), TimedNN(ts: 5, nnMs: 1010), TimedNN(ts: 6, nnMs: 1000)]
        let r = HRVAnalyzer.rmssdSegmented(nn)
        XCTAssertEqual(r.nPairs, 1)
        XCTAssertEqual(try XCTUnwrap(r.rmssd), 10.0, accuracy: 1e-9)
    }

    /// An artifact is DISCARDED, never BRIDGED. Removing the bad beat to pair its two neighbours
    /// would manufacture pairs on exactly the dirtiest nights, and the density gate built on this
    /// count would then trust its worst data the most.
    func testArtifactIsDiscardedRatherThanBridged() {
        let nn = [TimedNN(ts: 0, nnMs: 1000), TimedNN(ts: 1, nnMs: 1400), TimedNN(ts: 2, nnMs: 1000)]
        let r = HRVAnalyzer.rmssdSegmented(nn)
        XCTAssertEqual(r.nPairs, 0, "both steps exceed 20 % of the shorter beat")
        XCTAssertNil(r.rmssd)
    }

    func testImplausibleBeatsNeverPair() {
        let nn = [TimedNN(ts: 0, nnMs: 250), TimedNN(ts: 1, nnMs: 260)]
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn).nPairs, 0)
        XCTAssertNil(HRVAnalyzer.rmssdSegmented(nn).rmssd)
    }

    /// Order of arrival must not change the answer; a tie yields Δt = 0 and is excluded.
    func testSegmentedIsOrderIndependentAndExcludesTies() {
        let nn = [TimedNN(ts: 0, nnMs: 1000), TimedNN(ts: 1, nnMs: 1010), TimedNN(ts: 2, nnMs: 1000)]
        let shuffled = [nn[2], nn[0], nn[1]]
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(shuffled).nPairs,
                       HRVAnalyzer.rmssdSegmented(nn).nPairs)
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(shuffled).rmssd,
                       HRVAnalyzer.rmssdSegmented(nn).rmssd)

        let tied = [TimedNN(ts: 0, nnMs: 1000), TimedNN(ts: 0, nnMs: 1005)]
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(tied).nPairs, 0)
    }

    /// Sub-second instants are the reason `ts` is fractional: truncating to whole seconds would
    /// collapse fast beats onto one stamp and silently drop valid pairs, more often the faster the
    /// heart beats — a bias, not a rounding.
    func testSubSecondBeatsStillPair() {
        let nn = [TimedNN(ts: 0, nnMs: 500), TimedNN(ts: 0.5, nnMs: 505),
                  TimedNN(ts: 1.0, nnMs: 500)]
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn).nPairs, 2)
    }
}
