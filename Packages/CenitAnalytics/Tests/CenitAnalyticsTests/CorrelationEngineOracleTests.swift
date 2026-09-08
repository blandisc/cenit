import XCTest
@testable import CenitAnalytics

/// Correlation against the hand-derived oracle: Pearson and the least-squares line, the exact
/// Student-t tail (checked against the distribution, not against a magic number), the inner join by
/// day, the lagged pairing, and the UTC day shift.
final class CorrelationEngineOracleTests: XCTestCase {

    /// Two-sided tail of the standard normal, 2·(1 − Φ(t)) — the approximation this engine
    /// deliberately does NOT use, kept here only to show how far off it would be.
    private func gaussianTwoSidedTail(_ t: Double) -> Double { erfc(abs(t) / 2.0.squareRoot()) }

    // MARK: - Coefficient and line

    func testPearsonMatchesHandComputedValues() throws {
        let c = try XCTUnwrap(CorrelationEngine.pearson([(1, 2), (2, 4), (3, 5), (4, 4), (5, 5)]))
        XCTAssertEqual(c.r, 0.7745966692414834, accuracy: 1e-12)     // 6/√60
        XCTAssertEqual(c.slope, 0.6, accuracy: 1e-12)                // Sxy/Sxx = 6/10
        XCTAssertEqual(c.intercept, 2.2, accuracy: 1e-12)            // ȳ − slope·x̄
        XCTAssertEqual(c.n, 5)
        XCTAssertEqual(c.pApprox, 0.12402706265755416, accuracy: 1e-8)

        // …and the p really is the tail of that r's t statistic at df = n − 2.
        let t = c.r * (3 / (1 - c.r * c.r)).squareRoot()
        XCTAssertEqual(t, 2.121320343559643, accuracy: 1e-12)
        XCTAssertEqual(c.pApprox, CorrelationEngine.studentTTwoSided(t: t, df: 3), accuracy: 1e-12)
    }

    func testPerfectRelationshipsAreExact() throws {
        let up = try XCTUnwrap(CorrelationEngine.pearson((1...5).map { (Double($0), 2 * Double($0) + 1) }))
        XCTAssertEqual(up.r, 1.0, accuracy: 1e-12)
        XCTAssertEqual(up.slope, 2.0, accuracy: 1e-12)
        XCTAssertEqual(up.intercept, 1.0, accuracy: 1e-12)
        XCTAssertEqual(up.n, 5)
        XCTAssertEqual(up.pApprox, 0.0, accuracy: 1e-15, "no residual variance left")

        let down = try XCTUnwrap(CorrelationEngine.pearson((1...5).map { (Double($0), -3 * Double($0) + 20) }))
        XCTAssertEqual(down.r, -1.0, accuracy: 1e-12)
        XCTAssertEqual(down.slope, -3.0, accuracy: 1e-12)
        XCTAssertEqual(down.intercept, 20.0, accuracy: 1e-12)
    }

    func testSymmetricRelationshipHasNoLinearComponent() throws {
        let c = try XCTUnwrap(CorrelationEngine.pearson([(1, 10), (2, 8), (3, 6), (4, 6), (5, 8), (6, 10)]))
        XCTAssertEqual(c.r, 0.0, accuracy: 1e-12)
        XCTAssertEqual(c.slope, 0.0, accuracy: 1e-12)
        XCTAssertEqual(c.pApprox, 1.0, accuracy: 1e-9)
    }

    func testPearsonRefusesWhatItCannotEstimate() throws {
        XCTAssertNil(CorrelationEngine.pearson([(1, 1), (2, 2)]), "below the minimum pair floor")
        XCTAssertNil(CorrelationEngine.pearson([]))
        XCTAssertNil(CorrelationEngine.pearson([(5, 1), (5, 2), (5, 3)]), "x does not vary")
        XCTAssertNil(CorrelationEngine.pearson([(1, 7), (2, 7), (3, 7)]), "y does not vary")
        // The floor is the shared one, not a private copy.
        XCTAssertEqual(CorrelationStrength.minPairs, 3)
    }

    // MARK: - Student-t tail

    func testStudentTailMatchesTheDistribution() throws {
        // Both values are readable off any Student-t table (they agree with a reference
        // implementation's two-sided survival function to 1e-8): the distribution, not a constant.
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 2.0, df: 10),
                       0.07338803477074024, accuracy: 1e-8)
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 2.121320343559643, df: 3),
                       0.12402706265755416, accuracy: 1e-8)
    }

    func testStudentTailEdges() throws {
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 0, df: 3), 1.0, accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 5, df: 0), 1.0, accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 5, df: -2), 1.0, accuracy: 1e-15)
        // Symmetric in the sign of t, and always a probability.
        for df in [1.0, 3.0, 10.5, 40.0] {
            for t in [0.5, 2.2, 6.0] {
                let p = CorrelationEngine.studentTTwoSided(t: t, df: df)
                XCTAssertEqual(p, CorrelationEngine.studentTTwoSided(t: -t, df: df), accuracy: 1e-15)
                XCTAssertGreaterThanOrEqual(p, 0)
                XCTAssertLessThanOrEqual(p, 1)
            }
        }
        // Monotone: more evidence, smaller tail.
        XCTAssertGreaterThan(CorrelationEngine.studentTTwoSided(t: 1.0, df: 10),
                             CorrelationEngine.studentTTwoSided(t: 3.0, df: 10))
    }

    /// Why the exact tail is not optional: on small samples Student's tails are much heavier than
    /// the normal's, so a normal approximation would report a smaller p than the truth — it would
    /// invent significance exactly where the data is thinnest.
    func testStudentTailIsHeavierThanTheNormalOnSmallSamples() throws {
        for df in [3.0, 5.0, 10.0] {
            let student = CorrelationEngine.studentTTwoSided(t: 2.2, df: df)
            XCTAssertGreaterThan(student, gaussianTwoSidedTail(2.2), "df = \(df)")
        }
        // The factor is large where it hurts: at n = 5 (df = 3) it is several-fold.
        let df3 = CorrelationEngine.studentTTwoSided(t: 2.2, df: 3)
        XCTAssertGreaterThan(df3 / gaussianTwoSidedTail(2.2), 3.0)
    }

    /// Fractional degrees of freedom, which is what Welch-Satterthwaite hands it.
    func testStudentTailAcceptsFractionalDegreesOfFreedom() throws {
        let low = CorrelationEngine.studentTTwoSided(t: 2.0, df: 10.0)
        let mid = CorrelationEngine.studentTTwoSided(t: 2.0, df: 10.7)
        let high = CorrelationEngine.studentTTwoSided(t: 2.0, df: 11.0)
        XCTAssertGreaterThan(low, mid)
        XCTAssertGreaterThan(mid, high)
    }

    // MARK: - Joining two dated series

    func testAlignByDayKeepsOnlySharedDaysInDayOrder() throws {
        let a: [(day: String, value: Double)] = [
            ("2026-01-03", 30), ("2026-01-01", 10), ("2026-01-02", 20),
        ]
        let b: [(day: String, value: Double)] = [
            ("2026-01-02", 200), ("2026-01-01", 100), ("2026-01-09", 900),
        ]
        let pairs = CorrelationEngine.alignByDay(a, b)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 10, accuracy: 1e-12)
        XCTAssertEqual(pairs[0].1, 100, accuracy: 1e-12)
        XCTAssertEqual(pairs[1].0, 20, accuracy: 1e-12)
        XCTAssertEqual(pairs[1].1, 200, accuracy: 1e-12)
    }

    func testAlignByDayKeepsTheLastEntryForARepeatedDay() throws {
        let a: [(day: String, value: Double)] = [("2026-01-01", 1), ("2026-01-01", 7), ("2026-01-02", 2)]
        let b: [(day: String, value: Double)] = [("2026-01-01", 10), ("2026-01-02", 20)]
        let pairs = CorrelationEngine.alignByDay(a, b)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 7, accuracy: 1e-12)
    }

    // MARK: - Lagged correlation

    private func series(from start: Int, values: [Double]) -> [(day: String, value: Double)] {
        values.enumerated().map { (String(format: "2026-01-%02d", start + $0.offset), $0.element) }
    }

    func testLagLinesUpSeriesShiftedByThatManyDays() throws {
        let x = series(from: 1, values: [1, 2, 3, 4, 5])   // Jan 1…5
        let y = series(from: 2, values: [1, 2, 3, 4, 5])   // Jan 2…6

        let atOne = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 1))
        XCTAssertEqual(atOne.r, 1.0, accuracy: 1e-12)
        XCTAssertEqual(atOne.n, 5)

        let atTwo = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 2))
        XCTAssertEqual(atTwo.n, 4, "shifting further leaves fewer overlapping pairs")
    }

    func testLagFindsTheRealOffsetOfASawtooth() throws {
        let wave: [Double] = [1, 5, 2, 6, 3, 7, 4]
        let x = series(from: 1, values: wave)   // Jan 1…7
        let y = series(from: 3, values: wave)   // the same wave, two days later

        let atTwo = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 2))
        XCTAssertEqual(atTwo.r, 1.0, accuracy: 1e-12)

        let atOne = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 1))
        XCTAssertLessThan(abs(atOne.r), 0.999)
        XCTAssertLessThan(atOne.r, atTwo.r, "the wrong lag must read weaker than the right one")
    }

    func testZeroLagIsExactlyTheSameDayJoin() throws {
        let x = series(from: 1, values: [3, 9, 4, 8, 5, 7, 6])
        let y = series(from: 1, values: [10, 2, 9, 3, 8, 4, 7])
        let lagged = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 0))
        let joined = try XCTUnwrap(CorrelationEngine.pearson(CorrelationEngine.alignByDay(x, y)))
        XCTAssertEqual(lagged.r, joined.r, accuracy: 1e-12)
        XCTAssertEqual(lagged.slope, joined.slope, accuracy: 1e-12)
        XCTAssertEqual(lagged.n, joined.n)
    }

    // MARK: - Day shift

    func testShiftDayCrossesMonthYearAndLeapBoundaries() throws {
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-01-31", by: 1), "2026-02-01")
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-03-01", by: -1), "2026-02-28")
        XCTAssertEqual(CorrelationEngine.shiftDay("2025-12-31", by: 1), "2026-01-01")
        XCTAssertEqual(CorrelationEngine.shiftDay("2024-02-28", by: 1), "2024-02-29")
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-06-15", by: 0), "2026-06-15")
        // Padding is always four/two/two.
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-01-09", by: 1), "2026-01-10")
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-01-01", by: -1), "2025-12-31")
    }

    func testShiftDayRejectsMalformedKeys() throws {
        XCTAssertNil(CorrelationEngine.shiftDay("not-a-date", by: 1))
        XCTAssertNil(CorrelationEngine.shiftDay("2026-13-01", by: 1))
        XCTAssertNil(CorrelationEngine.shiftDay("2026-01-00", by: 1))
        XCTAssertNil(CorrelationEngine.shiftDay("2026-01", by: 1))
    }

    /// The two day arithmetics in this package must agree on what a day is worth.
    func testShiftDayAgreesWithTheEpochDayArithmetic() throws {
        let start = "2026-02-25"
        for delta in [-400, -31, -1, 1, 28, 365, 800] {
            let shifted = try XCTUnwrap(CorrelationEngine.shiftDay(start, by: delta))
            let a = try XCTUnwrap(ComparisonEngine.epochDay(of: start))
            let b = try XCTUnwrap(ComparisonEngine.epochDay(of: shifted))
            XCTAssertEqual(b - a, delta, "delta \(delta) via \(shifted)")
        }
    }
}
