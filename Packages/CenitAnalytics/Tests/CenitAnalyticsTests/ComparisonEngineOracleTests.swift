import XCTest
@testable import CenitAnalytics

/// Period comparison against the hand-derived oracle: descriptive statistics, the OLS slope, the
/// two-period contrast and its degenerate cases, the rolling-window partition, and the civil-day
/// arithmetic.
final class ComparisonEngineOracleTests: XCTestCase {

    // MARK: - Descriptive summary

    func testStatMatchesHandComputedValues() throws {
        let rising = ComparisonEngine.stat([10, 12, 14, 16, 18])
        XCTAssertEqual(rising.mean, 14.0, accuracy: 1e-12)
        XCTAssertEqual(rising.median, 14.0, accuracy: 1e-12)
        XCTAssertEqual(rising.min, 10.0, accuracy: 1e-12)
        XCTAssertEqual(rising.max, 18.0, accuracy: 1e-12)
        XCTAssertEqual(rising.stdev, 3.1622776601683795, accuracy: 1e-12)   // √10
        XCTAssertEqual(rising.n, 5)
        XCTAssertEqual(rising.slopePerDay, 2.0, accuracy: 1e-12)

        let evenCount = ComparisonEngine.stat([1, 2, 3, 4])
        XCTAssertEqual(evenCount.mean, 2.5, accuracy: 1e-12)
        XCTAssertEqual(evenCount.median, 2.5, accuracy: 1e-12, "even n averages the two middles")
        XCTAssertEqual(evenCount.stdev, 1.2909944487358056, accuracy: 1e-12)   // √(5/3)
        XCTAssertEqual(evenCount.slopePerDay, 1.0, accuracy: 1e-12)

        let falling = ComparisonEngine.stat([20, 15, 10, 5])
        XCTAssertEqual(falling.mean, 12.5, accuracy: 1e-12)
        XCTAssertEqual(falling.median, 12.5, accuracy: 1e-12)
        XCTAssertEqual(falling.min, 5.0, accuracy: 1e-12)
        XCTAssertEqual(falling.max, 20.0, accuracy: 1e-12)
        XCTAssertEqual(falling.stdev, 6.454972243679028, accuracy: 1e-12)     // √(125/3)
        XCTAssertEqual(falling.slopePerDay, -5.0, accuracy: 1e-12)
    }

    func testStatDegenerateSlices() throws {
        let single = ComparisonEngine.stat([42])
        XCTAssertEqual(single.mean, 42.0, accuracy: 1e-12)
        XCTAssertEqual(single.median, 42.0, accuracy: 1e-12)
        XCTAssertEqual(single.min, 42.0, accuracy: 1e-12)
        XCTAssertEqual(single.max, 42.0, accuracy: 1e-12)
        XCTAssertEqual(single.stdev, 0.0, accuracy: 1e-12, "no dispersion to estimate from one point")
        XCTAssertEqual(single.slopePerDay, 0.0, accuracy: 1e-12)
        XCTAssertEqual(single.n, 1)

        XCTAssertEqual(ComparisonEngine.stat([]), SeriesStat.empty)
        XCTAssertEqual(SeriesStat.empty.n, 0)
    }

    // MARK: - Two-period contrast

    func testCompareMatchesHandComputedContrast() throws {
        let c = ComparisonEngine.compare(current: [62, 64, 66, 60, 68, 70],
                                         previous: [58, 60, 56, 62, 59, 61])

        XCTAssertEqual(c.current.mean, 65.0, accuracy: 1e-12)
        XCTAssertEqual(c.current.median, 65.0, accuracy: 1e-12)
        XCTAssertEqual(c.current.stdev, 3.7416573867739413, accuracy: 1e-12)
        XCTAssertEqual(c.current.slopePerDay, 1.3142857142857143, accuracy: 1e-12)

        XCTAssertEqual(c.previous.mean, 59.333333333333336, accuracy: 1e-12)
        XCTAssertEqual(c.previous.median, 59.5, accuracy: 1e-12)
        XCTAssertEqual(c.previous.stdev, 2.1602468994692865, accuracy: 1e-12)
        XCTAssertEqual(c.previous.slopePerDay, 0.5142857142857142, accuracy: 1e-12)

        XCTAssertEqual(c.delta, 5.666666666666664, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(c.pctChange), 9.550561797752804, accuracy: 1e-12)
        XCTAssertEqual(c.direction, 1)
    }

    func testCompareDegenerates() throws {
        // No previous period at all: no percentage, and no direction to claim.
        let noPrevious = ComparisonEngine.compare(current: [10, 12], previous: [])
        XCTAssertNil(noPrevious.pctChange)
        XCTAssertEqual(noPrevious.direction, 0)

        // A previous period that exists but averages zero: the percentage is undefined, yet the
        // direction is not — the chip hides the number, not the arrow.
        let zeroBase = ComparisonEngine.compare(current: [5, 5], previous: [0, 0])
        XCTAssertNil(zeroBase.pctChange)
        XCTAssertEqual(zeroBase.direction, 1)

        let flat = ComparisonEngine.compare(current: [10, 10], previous: [10, 10])
        XCTAssertEqual(try XCTUnwrap(flat.pctChange), 0.0, accuracy: 1e-12)
        XCTAssertEqual(flat.direction, 0)

        let down = ComparisonEngine.compare(current: [8, 8, 8], previous: [10, 10, 10])
        XCTAssertEqual(try XCTUnwrap(down.pctChange), -20.0, accuracy: 1e-12)
        XCTAssertEqual(down.direction, -1)
    }

    /// The percentage divides by the ABSOLUTE previous mean, so on a metric that can go negative the
    /// sign of the percentage still follows the sign of the change.
    func testPercentageSignFollowsTheDeltaOnNegativeMetrics() throws {
        let c = ComparisonEngine.compare(current: [-2, -2], previous: [-4, -4])
        XCTAssertEqual(c.delta, 2.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(c.pctChange), 50.0, accuracy: 1e-12)
        XCTAssertEqual(c.direction, 1)
    }

    // MARK: - Rolling-window partition

    func testRollingWindowSplitsTheTwoPeriodsAndIgnoresTheRest() throws {
        var rows: [(day: String, value: Double)] = []
        for d in 1...7 { rows.append((String(format: "2026-03-%02d", d), 10)) }
        for d in 8...14 { rows.append((String(format: "2026-03-%02d", d), 20)) }
        rows.append(("2026-02-01", 99))   // outside both windows

        let c = ComparisonEngine.periodOverPeriod(byDay: rows, windowDays: 7, referenceDay: "2026-03-14")
        XCTAssertEqual(c.current.n, 7)
        XCTAssertEqual(c.previous.n, 7)
        XCTAssertEqual(c.current.mean, 20.0, accuracy: 1e-12)
        XCTAssertEqual(c.previous.mean, 10.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(c.pctChange), 100.0, accuracy: 1e-12)
        XCTAssertEqual(c.direction, 1)
    }

    func testRollingWindowDropsDaysBeyondTwoWindows() throws {
        let rows: [(day: String, value: Double)] = [
            ("2026-02-09", 4), ("2026-03-10", 8), ("2026-01-20", 2), ("2026-01-01", 99),
        ]
        let c = ComparisonEngine.periodOverPeriod(byDay: rows, windowDays: 30, referenceDay: "2026-03-10")
        XCTAssertEqual(c.current.n, 2)
        XCTAssertEqual(c.current.mean, 6.0, accuracy: 1e-12)
        XCTAssertEqual(c.previous.n, 1)
        XCTAssertEqual(c.previous.mean, 2.0, accuracy: 1e-12)
    }

    func testRollingWindowSortsChronologicallyBeforeSummarising() throws {
        // The same three ascending days, handed over shuffled: the slope must still read +2/day.
        let shuffled: [(day: String, value: Double)] = [
            ("2026-03-20", 64), ("2026-03-18", 60), ("2026-03-19", 62),
        ]
        let c = ComparisonEngine.periodOverPeriod(byDay: shuffled, windowDays: 7, referenceDay: "2026-03-20")
        XCTAssertEqual(c.current.n, 3)
        XCTAssertEqual(c.current.slopePerDay, 2.0, accuracy: 1e-12)
    }

    func testRollingWindowRefusesBadInput() throws {
        let rows: [(day: String, value: Double)] = [("2026-03-01", 10), ("2026-03-02", 12)]

        let unparseable = ComparisonEngine.periodOverPeriod(byDay: rows, windowDays: 7,
                                                            referenceDay: "not-a-date")
        XCTAssertEqual(unparseable.current.n, 0)
        XCTAssertEqual(unparseable.previous.n, 0)

        let zeroWindow = ComparisonEngine.periodOverPeriod(byDay: rows, windowDays: 0,
                                                           referenceDay: "2026-03-02")
        XCTAssertEqual(zeroWindow.current.n, 0)
        XCTAssertEqual(zeroWindow.previous.n, 0)

        // Only a current period: no previous to compare against, so no percentage and no direction.
        let lonely = ComparisonEngine.periodOverPeriod(byDay: rows, windowDays: 7,
                                                       referenceDay: "2026-03-02")
        XCTAssertEqual(lonely.current.n, 2)
        XCTAssertEqual(lonely.previous.n, 0)
        XCTAssertNil(lonely.pctChange)
        XCTAssertEqual(lonely.direction, 0)
    }

    // MARK: - Civil day arithmetic

    func testEpochDayIsTheCanonicalInverseOfTheDayKey() throws {
        XCTAssertEqual(ComparisonEngine.epochDay(of: "1970-01-01"), 0)

        let mar = try XCTUnwrap(ComparisonEngine.epochDay(of: "2026-03-01"))
        let feb = try XCTUnwrap(ComparisonEngine.epochDay(of: "2026-02-28"))
        XCTAssertEqual(mar - feb, 1, "2026 is not a leap year")

        let leapMar = try XCTUnwrap(ComparisonEngine.epochDay(of: "2024-03-01"))
        let leapFeb = try XCTUnwrap(ComparisonEngine.epochDay(of: "2024-02-29"))
        XCTAssertEqual(leapMar - leapFeb, 1, "2024 is a leap year")

        // A whole common year and a whole leap year.
        let start2026 = try XCTUnwrap(ComparisonEngine.epochDay(of: "2026-01-01"))
        let start2027 = try XCTUnwrap(ComparisonEngine.epochDay(of: "2027-01-01"))
        XCTAssertEqual(start2027 - start2026, 365)
        let start2024 = try XCTUnwrap(ComparisonEngine.epochDay(of: "2024-01-01"))
        let start2025 = try XCTUnwrap(ComparisonEngine.epochDay(of: "2025-01-01"))
        XCTAssertEqual(start2025 - start2024, 366)
    }

    func testEpochDayRejectsMalformedKeys() throws {
        XCTAssertNil(ComparisonEngine.epochDay(of: "not-a-date"))
        XCTAssertNil(ComparisonEngine.epochDay(of: "2026-13-01"), "month out of range")
        XCTAssertNil(ComparisonEngine.epochDay(of: "2026-00-01"))
        XCTAssertNil(ComparisonEngine.epochDay(of: "2026-01-32"), "day out of range")
        XCTAssertNil(ComparisonEngine.epochDay(of: "2026-01-00"))
        XCTAssertNil(ComparisonEngine.epochDay(of: "2026-01"))
        XCTAssertNil(ComparisonEngine.epochDay(of: ""))
        // Documented laxity: it validates RANGE, not calendar, so day 31 of a 30-day month parses.
        XCTAssertNotNil(ComparisonEngine.epochDay(of: "2026-04-31"))
    }

    // MARK: - Non-finite hardening (FER-465)

    /// A period whose mean is non-finite (a stored NaN/±Inf slipped past the origin guards) must yield
    /// `pctChange == nil`, never a NaN percentage — downstream a NaN pct makes `Int(pct.rounded())` a
    /// fatal trap in the bespoke formatters. `prev.mean != 0` alone let it through (`NaN != 0` is true).
    func testNonFinitePreviousMeanYieldsNilPercentAndDoesNotCrash() {
        let nanPrev = ComparisonEngine.compare(current: [10, 12], previous: [Double.nan, 5])
        XCTAssertNil(nanPrev.pctChange, "a NaN previous mean must not produce a percentage")

        let infPrev = ComparisonEngine.compare(current: [10, 12], previous: [Double.infinity])
        XCTAssertNil(infPrev.pctChange, "an infinite previous mean must not produce a percentage")

        let nanCur = ComparisonEngine.compare(current: [Double.nan, 3], previous: [4, 6])
        XCTAssertNil(nanCur.pctChange, "a NaN current mean (→ NaN delta) must not produce a percentage")

        // The finite baseline still computes a percentage as before (no regression).
        let ok = ComparisonEngine.compare(current: [12, 12], previous: [10, 10])
        XCTAssertEqual(try XCTUnwrap(ok.pctChange), 20.0, accuracy: 1e-9)
    }
}
