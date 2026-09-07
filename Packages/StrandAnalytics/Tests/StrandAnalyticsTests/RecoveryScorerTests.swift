import XCTest
import BiometricStreams
@testable import StrandAnalytics

/// Nocturnal resting heart rate: the minimum of the five-minute window AVERAGES, not the lowest
/// single beat, and only over windows that clear both guards.
final class RecoveryScorerTests: XCTestCase {

    /// `n` readings a second apart at a fixed pulse, starting at `from`.
    private func run(_ n: Int, bpm: Int, from: Int) -> [HRSample] {
        (0..<n).map { HRSample(ts: from + $0, bpm: bpm) }
    }

    func testNoSamplesMeansNoAnswer() {
        XCTAssertNil(RecoveryScorer.restingHR([], start: 0, end: 1000))
    }

    /// Two clean windows: the lower average wins.
    func testTakesTheLowestQualifyingWindowAverage() {
        let hr = run(300, bpm: 60, from: 0) + run(300, bpm: 50, from: 300)
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: 0, end: 600), 50)
    }

    func testAnOrdinaryNightBehavesTheSameWay() {
        let hr = run(300, bpm: 62, from: 0) + run(300, bpm: 51, from: 300)
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: 0, end: 600), 51)
    }

    /// A handful of readings during a dropout must not win the minimum: without the count guard,
    /// three stray beats would decide the night.
    func testTooFewReadingsCannotWinTheWindow() {
        let hr = run(300, bpm: 55, from: 0) + run(3, bpm: 40, from: 300)
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: 0, end: 600), 55)
    }

    /// A window of artifacts averaging below the physiological floor is refused: without this guard
    /// it would fabricate a number no heart produced.
    func testAWindowBelowThePhysiologicalFloorIsRefused() {
        let hr = run(300, bpm: 58, from: 0) + run(300, bpm: 15, from: 300)
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: 0, end: 600), 58)
    }

    /// When nothing qualifies, the honest answer is no answer — this value feeds personal baselines,
    /// and one impossible night there bends weeks of comparisons.
    func testNoQualifyingWindowAnswersNothing() {
        XCTAssertNil(RecoveryScorer.restingHR(run(3, bpm: 42, from: 0), start: 0, end: 600))
    }

    /// The window bounds are inclusive, and readings outside them are not considered at all.
    func testOnlyReadingsInsideTheWindowCount() {
        let hr = run(300, bpm: 62, from: 0) + run(300, bpm: 51, from: 300)
        XCTAssertEqual(RecoveryScorer.restingHR(hr, start: 0, end: 299), 62,
                       "the second window is outside the requested span")
        XCTAssertNil(RecoveryScorer.restingHR(hr, start: 10_000, end: 20_000))
    }

    /// It is the minimum of AVERAGES, not the minimum beat: one low reading inside an otherwise
    /// ordinary window cannot pull the answer down to itself.
    func testOneLowBeatIsNotRest() {
        var hr = run(300, bpm: 60, from: 0)
        hr[100] = HRSample(ts: 100, bpm: 33)
        let answer = try? XCTUnwrap(RecoveryScorer.restingHR(hr, start: 0, end: 300))
        XCTAssertEqual(answer, 60, "one beat moves the average by 0.09 bpm, and rounds away")
    }

    /// The band cuts split 0–100 into three roughly equal parts.
    func testBandCutsAreTheThirdsOfTheScale() {
        XCTAssertEqual(RecoveryScorer.bandRedMax, 34.0, accuracy: 1e-12)
        XCTAssertEqual(RecoveryScorer.bandYellowMax, 67.0, accuracy: 1e-12)
        XCTAssertLessThan(RecoveryScorer.bandRedMax, RecoveryScorer.bandYellowMax)
    }
}
