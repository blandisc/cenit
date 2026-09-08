import XCTest
import CenitModels
@testable import CenitAnalytics

/// FER-339 — the single source of truth for sleep need + debt, shared by the coach (InsightEngine)
/// and the Sleep Detail screen so they never disagree.
final class SleepMathTests: XCTestCase {

    private func day(_ i: Int) -> String { String(format: "2026-06-%02d", i + 1) }

    private func metric(_ i: Int, sleep: Double?) -> DailyMetric {
        DailyMetric(day: day(i), totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    private func days(_ sleeps: [Double?]) -> [DailyMetric] {
        sleeps.enumerated().map { metric($0.offset, sleep: $0.element) }
    }

    // MARK: needMinutes

    // FER-409: need is a FIXED target (7.5 h), no longer the personal mean.
    func testNeedIsFixedTargetRegardlessOfData() {
        XCTAssertEqual(SleepMath.needMinutes([]), 450)                       // no data → target
        XCTAssertEqual(SleepMath.needMinutes(days([360, 360, 360])), 450)    // chronic short → target, not 360
        XCTAssertEqual(SleepMath.needMinutes(days([520, 540, 560])), 450)    // long sleeper → still 450, NOT the mean
    }

    // MARK: debtMinutes

    func testNoDebtWhenAllAtOrAboveTarget() {
        // Every night meets the 450 target → zero debt.
        XCTAssertEqual(SleepMath.debtMinutes(days([540, 540, 540])), 0, accuracy: 0.001)
    }

    // The whole point of FER-409: a good sleeper with normal variance owes NOTHING. Under the old
    // personal-mean need this vector had need=mean=540 and reported 120 min of "debt" despite a 9-h
    // average; against the fixed 450 target every night is a surplus → 0.
    func testHighAverageSleeperWithVarianceHasNoDebt() {
        XCTAssertEqual(SleepMath.debtMinutes(days([600, 480, 600, 480])), 0, accuracy: 0.001)
    }

    func testDebtSumsPerNightShortfallVsTarget() {
        // Fixed need = 450. debt = (450-480→0) + (450-420→30) = 30.
        XCTAssertEqual(SleepMath.debtMinutes(days([480, 420])), 30, accuracy: 0.001)
    }

    func testLongNightDoesNotPayOffShortNight() {
        // Fixed need = 450. Per-night floored: 0 + 150 = 150 (surplus ignored).
        XCTAssertEqual(SleepMath.debtMinutes(days([600, 300])), 150, accuracy: 0.001)
    }

    func testOnlyTrailingWindowCounts() {
        // 10 nights: a huge deficit 8 nights ago must NOT count; only the last 7 do.
        var s: [Double?] = Array(repeating: 450, count: 10)
        s[0] = 0           // night 1 (off-window) — would add 450 of debt if counted
        XCTAssertEqual(SleepMath.debtMinutes(days(s)), 0, accuracy: 0.001)
    }

    // MARK: the whole point — engine and SleepMath agree

    func testEngineDebtEqualsSleepMath() {
        let d = days([300, 600, 420, 480, 510, 360, 450, 400])
        XCTAssertEqual(InsightEngine.sleepDebtMinutes(d), SleepMath.debtMinutes(d), accuracy: 0.001)
    }
}
