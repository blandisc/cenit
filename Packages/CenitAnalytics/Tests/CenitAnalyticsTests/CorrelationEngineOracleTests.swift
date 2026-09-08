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

    func testPairsAreThePairingBehindLagged() throws {
        let x = series(from: 1, values: [3, 9, 4, 8, 5, 7, 6])
        let y = series(from: 1, values: [10, 2, 9, 3, 8, 4, 7])
        let atZero = CorrelationEngine.pairs(x: x, y: y, lagDays: 0)
        let aligned = CorrelationEngine.alignByDay(x, y)
        XCTAssertEqual(atZero.map { $0.0 }, aligned.map { $0.0 })
        XCTAssertEqual(atZero.map { $0.1 }, aligned.map { $0.1 })
        let atOne = CorrelationEngine.pairs(x: x, y: y, lagDays: 1)
        XCTAssertEqual(atOne.count, 6)
        XCTAssertEqual(atOne.map { $0.0 }, [3, 9, 4, 8, 5, 7])
        XCTAssertEqual(atOne.map { $0.1 }, [2, 9, 3, 8, 4, 7])
        let lagged = try XCTUnwrap(CorrelationEngine.lagged(x: x, y: y, lagDays: 1))
        XCTAssertEqual(lagged.r, try XCTUnwrap(CorrelationEngine.pearson(atOne)).r, accuracy: 1e-12)
    }

    // MARK: - Spearman (FER-438)

    func testMidranksShareTiedPositions() throws {
        XCTAssertEqual(CorrelationEngine.midranks([10, 20, 20, 30]), [1, 2.5, 2.5, 4])
        XCTAssertEqual(CorrelationEngine.midranks([5, 1, 3]), [3, 1, 2])
        XCTAssertEqual(CorrelationEngine.midranks([7, 7, 7]), [2, 2, 2])
        XCTAssertEqual(CorrelationEngine.midranks([0, 0, 0, 4, 0, 9]), [2.5, 2.5, 2.5, 5, 2.5, 6])
        XCTAssertEqual(CorrelationEngine.midranks([]), [])
    }

    func testSpearmanMatchesHandComputedRanks() throws {
        // y ranks with one tie: [1, 2, 3.5, 5, 3.5] against x ranks [1…5] → ρ = 8/√95.
        let c = try XCTUnwrap(CorrelationEngine.spearman([(1, 5), (2, 6), (3, 7), (4, 8), (5, 7)]))
        XCTAssertEqual(c.r, 8 / 95.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(c.n, 5)
        // …and its p is the t-approximation on df = n − 2, the same tail `pearson` reads.
        let t = c.r * (3 / (1 - c.r * c.r)).squareRoot()
        XCTAssertEqual(c.pApprox, CorrelationEngine.studentTTwoSided(t: t, df: 3), accuracy: 1e-12)
    }

    func testSpearmanIsOneOnAnyMonotoneRelationship() throws {
        // y = x³ is far from linear (Pearson < 1) but perfectly monotone (ρ = 1).
        let cubic = (1...8).map { (Double($0), pow(Double($0), 3)) }
        XCTAssertEqual(try XCTUnwrap(CorrelationEngine.spearman(cubic)).r, 1.0, accuracy: 1e-12)
        XCTAssertLessThan(try XCTUnwrap(CorrelationEngine.pearson(cubic)).r, 0.99)
        let decreasing = (1...8).map { (Double($0), exp(-Double($0))) }
        XCTAssertEqual(try XCTUnwrap(CorrelationEngine.spearman(decreasing)).r, -1.0, accuracy: 1e-12)
    }

    func testSpearmanRefusesAnAllTiedVariable() throws {
        XCTAssertNil(CorrelationEngine.spearman([(5, 1), (5, 2), (5, 3)]), "every x rank is 2")
        XCTAssertNil(CorrelationEngine.spearman([(1, 1), (2, 2)]), "below the pair floor")
    }

    // MARK: - Partial Spearman (FER-438)

    func testPartialSpearmanMatchesHandComputedRanks() throws {
        // Distinct integers, so the ranks are the values and ρ = 1 − 6Σd²/(n(n² − 1)), n(n² − 1) = 120:
        // x·y Σd² = 4 → 0.8; x·z Σd² = 4 → 0.8; y·z Σd² = 14 → 0.3.
        // r_xy·z = (0.8 − 0.8·0.3) / √((1 − 0.64)(1 − 0.09)) = 0.56 / √0.3276.
        let xyz: [(Double, Double, Double)] = [(1, 2, 1), (2, 1, 3), (3, 4, 2), (4, 3, 5), (5, 5, 4)]
        let c = try XCTUnwrap(CorrelationEngine.spearmanPartial(xyz))
        XCTAssertEqual(c.r, 0.56 / 0.3276.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(c.n, 5)
        XCTAssertEqual(try XCTUnwrap(CorrelationEngine.partial(rxy: 0.8, rxz: 0.8, ryz: 0.3)),
                       0.56 / 0.3276.squareRoot(), accuracy: 1e-12)
        // …and its p is the t tail on df = n − 3 = 2: one degree of freedom paid for the control.
        let t = c.r * (2 / (1 - c.r * c.r)).squareRoot()
        XCTAssertEqual(c.pApprox, CorrelationEngine.studentTTwoSided(t: t, df: 2), accuracy: 1e-12)
        XCTAssertEqual(c.pApprox, 0.021600819060, accuracy: 1e-9)
    }

    func testPartialSpearmanRemovesWhatTheControlExplains() throws {
        // The calendar artefact in miniature: z runs against x (ρ_xz = −0.8), y tracks z (ρ_yz = +0.5), so x
        // and y read ρ_xy = −0.4 without ever touching each other — x = strain[D], z = strain[D+1], y = a
        // night that follows its OWN day's strain. Holding z fixed leaves exactly nothing.
        let xyz: [(Double, Double, Double)] = [(1, 5, 4), (2, 3, 5), (3, 2, 3), (4, 1, 1), (5, 4, 2)]
        let plain = try XCTUnwrap(CorrelationEngine.spearman(xyz.map { ($0.0, $0.1) }))
        XCTAssertEqual(plain.r, -0.4, accuracy: 1e-12)
        let c = try XCTUnwrap(CorrelationEngine.spearmanPartial(xyz))
        XCTAssertEqual(c.r, 0, accuracy: 1e-12)
        XCTAssertEqual(c.pApprox, 1.0, accuracy: 1e-12)
        // Ranks, not values: a monotone transform of any variable (even a reversal of z) changes nothing.
        let warped = xyz.map { (exp($0.0), $0.1 * $0.1, -$0.2) }
        XCTAssertEqual(try XCTUnwrap(CorrelationEngine.spearmanPartial(warped)).r, 0, accuracy: 1e-12)
    }

    func testPartialSpearmanRefusesWhatItCannotEstimate() throws {
        XCTAssertNil(CorrelationEngine.spearmanPartial([(1, 2, 1), (2, 1, 3), (3, 4, 2)]), "below the triple floor")
        XCTAssertEqual(CorrelationStrength.minPairs + 1, 4, "one more than pearson's: the control costs a df")
        // z identical to x: |r_xz| = 1 leaves nothing to correlate.
        XCTAssertNil(CorrelationEngine.spearmanPartial([(1, 2, 1), (2, 1, 2), (3, 4, 3), (4, 3, 4), (5, 5, 5)]))
        XCTAssertNil(CorrelationEngine.partial(rxy: 0.5, rxz: 1, ryz: 0.2))
        // A variable that does not vary.
        XCTAssertNil(CorrelationEngine.spearmanPartial([(1, 7, 1), (2, 7, 3), (3, 7, 2), (4, 7, 5)]))
    }

    func testPartialPValueIsTheTailOnOneFewerDegreeOfFreedom() throws {
        // df = n − 3: the partial at n reads exactly the plain tail at n − 1, and less evidence → a larger p.
        XCTAssertEqual(CorrelationEngine.partialPValue(r: 0.5, n: 10), CorrelationEngine.pValue(r: 0.5, n: 9),
                       accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.partialPValue(r: 0.5, n: 10), 0.1704706607870542, accuracy: 1e-9)
        XCTAssertGreaterThan(CorrelationEngine.partialPValue(r: 0.5, n: 10), CorrelationEngine.pValue(r: 0.5, n: 10))
        // A fractional n (an effective n) is the same tail; n ≤ 3 has no evidence; a perfect fit no residual.
        XCTAssertEqual(CorrelationEngine.partialPValue(r: 0.5, n: 10.5), CorrelationEngine.pValue(r: 0.5, n: 9.5),
                       accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.partialPValue(r: 0.9, n: 3), 1.0)
        XCTAssertEqual(CorrelationEngine.partialPValue(r: 1.0, n: 30), 0.0)
        // The plain tail did not move.
        XCTAssertEqual(CorrelationEngine.pValue(r: 0.9, n: 2), 1.0)
    }

    // MARK: - Second-order partial Spearman (FER-480)

    func testQuadruplesDropsDaysMissingAnySideAndKeepsTheLastEntry() throws {
        let x: [(day: String, value: Double)] = [("2026-01-01", 1), ("2026-01-02", 2), ("2026-01-03", 3)]
        let y: [(day: String, value: Double)] = [("2026-01-02", 10), ("2026-01-03", 20), ("2026-01-04", 30)]
        let z1: [(day: String, value: Double)] = [("2026-01-01", 100), ("2026-01-02", 200)]
        let z2: [(day: String, value: Double)] = [("2026-01-02", -1), ("2026-01-02", -2), ("2026-01-03", -3)]
        // Days 01-01 and 01-02 have x, y[shifted], z1[D] AND z2[shifted] all present; 01-03 does not
        // (z1 has no entry for it), so it is dropped. A repeated day (z2's 01-02) keeps its LAST
        // entry, −2 — the control read on 01-01's shifted day.
        let q = CorrelationEngine.quadruples(x: x, y: y, z1: z1, z2: z2, lagDays: 1)
        XCTAssertEqual(q.count, 2)
        XCTAssertTrue(q[0] == (1, 10, 100, -2))
        XCTAssertTrue(q[1] == (2, 20, 200, -3))
    }

    func testSpearmanPartial2MatchesHandComputedRanks() throws {
        // Distinct integers 1…6, so ranks are the values and ρ = 1 − 6Σd²/(n(n² − 1)), n(n² − 1) = 210:
        // xy Σd² = 26 → 9/35; xz1 Σd² = 28 → 1/5; yz1 Σd² = 42 → −1/5;
        // xz2 Σd² = 18 → 17/35; yz2 Σd² = 32 → 3/35; z1z2 Σd² = 34 → 1/35.
        let quads: [(Double, Double, Double, Double)] = [
            (1, 4, 4, 4), (2, 2, 1, 2), (3, 3, 3, 3), (4, 5, 5, 1), (5, 1, 6, 5), (6, 6, 2, 6),
        ]
        let c = try XCTUnwrap(CorrelationEngine.spearmanPartial2(quads))
        XCTAssertEqual(c.n, 6)

        // The recursion: hold z1 fixed on x, y and z2 first (three first-order partials, already
        // tested independently), then hold the RESIDUAL z2 fixed on the two survivors.
        let rxy: Double = 9.0 / 35, rxz1: Double = 1.0 / 5, ryz1: Double = -1.0 / 5
        let rxz2: Double = 17.0 / 35, ryz2: Double = 3.0 / 35, rz1z2: Double = 1.0 / 35
        let xyGivenZ1 = try XCTUnwrap(CorrelationEngine.partial(rxy: rxy, rxz: rxz1, ryz: ryz1))
        let xz2GivenZ1 = try XCTUnwrap(CorrelationEngine.partial(rxy: rxz2, rxz: rxz1, ryz: rz1z2))
        let yz2GivenZ1 = try XCTUnwrap(CorrelationEngine.partial(rxy: ryz2, rxz: ryz1, ryz: rz1z2))
        XCTAssertEqual(xyGivenZ1, 13.0 / 42, accuracy: 1e-12, "the middle step is exactly 13/42")
        let expected = try XCTUnwrap(CorrelationEngine.partial(rxy: xyGivenZ1, rxz: xz2GivenZ1, ryz: yz2GivenZ1))
        XCTAssertEqual(c.r, expected, accuracy: 1e-12)
        XCTAssertEqual(c.r, 0.3039337023168104, accuracy: 1e-9)

        // …and its p is the t tail on df = n − 4 = 2: two degrees of freedom paid for the two controls.
        let t = c.r * (2 / (1 - c.r * c.r)).squareRoot()
        XCTAssertEqual(c.pApprox, CorrelationEngine.studentTTwoSided(t: t, df: 2), accuracy: 1e-12)
        XCTAssertEqual(c.pApprox, 0.696066, accuracy: 1e-6)
    }

    func testSpearmanPartial2AgreesWithLeastSquaresResidualRegression() throws {
        // An independent second path to the SAME coefficient (documented in CorrelationEngine.swift as
        // the reason the recursion is valid): regress x's and y's midranks on {z1, z2} with an
        // intercept by ordinary least squares, and correlate the residuals. On the fixture above the
        // two paths must agree to double precision.
        let quads: [(Double, Double, Double, Double)] = [
            (1, 4, 4, 4), (2, 2, 1, 2), (3, 3, 3, 3), (4, 5, 5, 1), (5, 1, 6, 5), (6, 6, 2, 6),
        ]
        let recursive = try XCTUnwrap(CorrelationEngine.spearmanPartial2(quads))
        let byResiduals = try XCTUnwrap(residualPartial(quads))
        XCTAssertEqual(recursive.r, byResiduals, accuracy: 1e-9)
    }

    func testSpearmanPartial2RemovesWhatASingleControlAlreadyExplained() throws {
        // The FER-438 order-1 fixture (`testPartialSpearmanRemovesWhatTheControlExplains`), with a
        // SECOND control added: x and y read ρ_xy = −0.4 purely through z1 (x tracks z1, y tracks z1),
        // and z2 is IDENTICAL to z1 — a control perfectly collinear with the other control. The first
        // recursion step (holding z1 fixed) already leaves nothing between x and y; z2 buys nothing
        // more, and being collinear with z1 (|r_z1z2| = 1) it collapses the second step's denominator
        // to zero — `nil`, not a wrong number.
        let xyz1: [(Double, Double, Double)] = [(1, 5, 4), (2, 3, 5), (3, 2, 3), (4, 1, 1), (5, 4, 2)]
        let plain = try XCTUnwrap(CorrelationEngine.spearman(xyz1.map { ($0.0, $0.1) }))
        XCTAssertEqual(plain.r, -0.4, accuracy: 1e-12)
        let orderOne = try XCTUnwrap(CorrelationEngine.spearmanPartial(xyz1))
        XCTAssertEqual(orderOne.r, 0, accuracy: 1e-12, "z1 alone already explains it")
        let quads = xyz1.map { (x: Double, y: Double, z1: Double) in (x, y, z1, z1) }
        XCTAssertNil(CorrelationEngine.spearmanPartial2(quads), "z2 collinear with z1")
    }

    func testSpearmanPartial2RefusesWhatItCannotEstimate() throws {
        XCTAssertEqual(CorrelationStrength.minPairs + 2, 5, "two more than pearson's: two controls cost two df")
        XCTAssertNil(CorrelationEngine.spearmanPartial2([(1, 2, 1, 3), (2, 1, 3, 1), (3, 4, 2, 4), (4, 3, 4, 2)]),
                     "four quadruples, below the floor of five")
        // z1 identical to x: |r_xz1| = 1 collapses the FIRST recursion step (x, y given z1) to nothing.
        let z1IsX: [(Double, Double, Double, Double)] = [
            (1, 2, 1, 5), (2, 1, 2, 3), (3, 5, 3, 1), (4, 3, 4, 4), (5, 4, 5, 2),
        ]
        XCTAssertNil(CorrelationEngine.spearmanPartial2(z1IsX))
        // A control that does not vary at all.
        let constantZ2: [(Double, Double, Double, Double)] = [
            (1, 2, 5, 7), (2, 1, 3, 7), (3, 5, 4, 7), (4, 3, 1, 7), (5, 4, 2, 7),
        ]
        XCTAssertNil(CorrelationEngine.spearmanPartial2(constantZ2))
        // x itself does not vary.
        let constantX: [(Double, Double, Double, Double)] = [
            (7, 2, 5, 1), (7, 1, 3, 2), (7, 5, 4, 3), (7, 3, 1, 4), (7, 4, 2, 5),
        ]
        XCTAssertNil(CorrelationEngine.spearmanPartial2(constantX))
    }

    func testPartialPValue2IsTheTailOnTwoFewerDegreesOfFreedom() throws {
        // df = n − 4: the order-2 partial at n reads exactly the plain tail at n − 2 — two degrees of
        // freedom paid for the two controls (Fisher 1924), one more than `partialPValue`'s n − 3.
        XCTAssertEqual(CorrelationEngine.partialPValue2(r: 0.5, n: 12), CorrelationEngine.pValue(r: 0.5, n: 10),
                       accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.partialPValue2(r: 0.5, n: 12), CorrelationEngine.partialPValue(r: 0.5, n: 11),
                       accuracy: 1e-15, "one fewer df than the first-order partial at the same n")
        XCTAssertGreaterThan(CorrelationEngine.partialPValue2(r: 0.5, n: 12), CorrelationEngine.partialPValue(r: 0.5, n: 12))
        // A fractional n (an effective n) is the same tail; n ≤ 4 has no evidence; a perfect fit no residual.
        XCTAssertEqual(CorrelationEngine.partialPValue2(r: 0.5, n: 12.5), CorrelationEngine.pValue(r: 0.5, n: 10.5),
                       accuracy: 1e-15)
        XCTAssertEqual(CorrelationEngine.partialPValue2(r: 0.9, n: 4), 1.0)
        XCTAssertEqual(CorrelationEngine.partialPValue2(r: 1.0, n: 30), 0.0)
    }

    /// Second path to `spearmanPartial2`'s coefficient, for `testSpearmanPartial2AgreesWithLeastSquaresResidualRegression`
    /// ONLY — never used by production, which recurses `partial(rxy:rxz:ryz:)` instead (see
    /// CorrelationEngine.swift). Regresses x's and y's midranks on {1, z1, z2} by ordinary least
    /// squares (a 3×3 normal-equations solve by Cramer's rule) and returns the Pearson r of the two
    /// residual series; `nil` on a singular system or a residual series with no variance.
    private func residualPartial(_ quads: [(Double, Double, Double, Double)]) -> Double? {
        let n = quads.count
        let rx = CorrelationEngine.midranks(quads.map { $0.0 })
        let ry = CorrelationEngine.midranks(quads.map { $0.1 })
        let rz1 = CorrelationEngine.midranks(quads.map { $0.2 })
        let rz2 = CorrelationEngine.midranks(quads.map { $0.3 })
        let design = (0..<n).map { [1.0, rz1[$0], rz2[$0]] }

        func det3(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        func solve(_ target: [Double]) -> [Double]? {
            var xtx = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
            var xty = [Double](repeating: 0, count: 3)
            for a in 0..<3 {
                for b in 0..<3 { xtx[a][b] = (0..<n).reduce(0) { $0 + design[$1][a] * design[$1][b] } }
                xty[a] = (0..<n).reduce(0) { $0 + design[$1][a] * target[$1] }
            }
            let d = det3(xtx)
            guard abs(d) > 1e-12 else { return nil }
            return (0..<3).map { col -> Double in
                var m = xtx
                for r in 0..<3 { m[r][col] = xty[r] }
                return det3(m) / d
            }
        }
        guard let bx = solve(rx), let by = solve(ry) else { return nil }
        let residX = (0..<n).map { rx[$0] - (bx[0] + bx[1] * rz1[$0] + bx[2] * rz2[$0]) }
        let residY = (0..<n).map { ry[$0] - (by[0] + by[1] * rz1[$0] + by[2] * rz2[$0]) }
        let mx = residX.reduce(0, +) / Double(n), my = residY.reduce(0, +) / Double(n)
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for i in 0..<n {
            let dx = residX[i] - mx, dy = residY[i] - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        guard sxx > 1e-9, syy > 1e-9 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    // MARK: - Effective sample size (FER-438)

    func testLag1AutocorrelationMatchesHandComputedValues() throws {
        // Mean 3, deviations [−2, −1, 0, 1, 2]: numerator 2 + 0 + 0 + 2 = 4, denominator 10.
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation([1, 2, 3, 4, 5]), 0.4, accuracy: 1e-12)
        // A ±1 alternation: every consecutive product is −1 over n − 1 of n → −(n−1)/n.
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation([1, -1, 1, -1, 1, -1]), -5.0 / 6, accuracy: 1e-12)
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation([4, 4, 4, 4]), 0, "constant")
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation([1, 2]), 0, "too short")
    }

    func testEffectiveNShrinksOnlyForPositivelyAutocorrelatedSeries() throws {
        // Bartlett with ρ₁ₓ = ρ₁ᵧ = 0.4: n · 0.84 / 1.16.
        let ramp: [Double] = [1, 2, 3, 4, 5]
        XCTAssertEqual(CorrelationEngine.effectiveN(x: ramp, y: ramp), 5 * 0.84 / 1.16, accuracy: 1e-12)
        // A negative autocorrelation is truncated at 0: it never buys evidence, so n_eff = n.
        let zigzag: [Double] = [1, -1, 1, -1, 1]
        XCTAssertEqual(CorrelationEngine.effectiveN(x: zigzag, y: ramp), 5, accuracy: 1e-12)
        XCTAssertEqual(CorrelationEngine.effectiveN(x: zigzag, y: zigzag), 5, accuracy: 1e-12)
        // Two smooth sines: the CDO fixture — n_eff collapses from 42 to ≈ 5.5.
        // Explícito por pasos: el type-checker de Swift en Linux no resuelve la expresión mixta
        // Int/Double en tiempo razonable si va en una sola línea (FER-438).
        let x: [Double] = (0..<42).map { i in
            let wave: Double = 10 * sin(2 * Double.pi * Double(i) / 28)
            let jitter: Double = 1.5 * (Double(i % 3) - 1)
            return wave + jitter
        }
        let y: [Double] = (0..<42).map { i in
            let wave: Double = 10 * sin(2 * Double.pi * Double(i + 5) / 28)
            let jitter: Double = 1.5 * (Double((7 * i) % 5) - 2)
            return wave + jitter
        }
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation(x), 0.925, accuracy: 0.01)
        XCTAssertEqual(CorrelationEngine.lag1Autocorrelation(y), 0.830, accuracy: 0.01)
        XCTAssertEqual(CorrelationEngine.effectiveN(x: x, y: y), 5.52, accuracy: 0.05)
    }

    func testPValueOnFractionalNIsTheSameTail() throws {
        let c = try XCTUnwrap(CorrelationEngine.pearson([(1, 2), (2, 4), (3, 5), (4, 4), (5, 5)]))
        XCTAssertEqual(CorrelationEngine.pValue(r: c.r, n: 5), c.pApprox, accuracy: 1e-15, "integer n ≡ pApprox")
        // Fewer effective observations → less evidence → a larger p, monotonically.
        XCTAssertGreaterThan(CorrelationEngine.pValue(r: 0.5, n: 4.5), CorrelationEngine.pValue(r: 0.5, n: 20))
        XCTAssertGreaterThan(CorrelationEngine.pValue(r: 0.5, n: 2.5), CorrelationEngine.pValue(r: 0.5, n: 4.5))
        // No evidence at or below two, and no residual on a perfect fit.
        XCTAssertEqual(CorrelationEngine.pValue(r: 0.9, n: 2), 1.0)
        XCTAssertEqual(CorrelationEngine.pValue(r: 0.9, n: 1.5), 1.0)
        XCTAssertEqual(CorrelationEngine.pValue(r: 1.0, n: 30), 0.0)
        // The CDO flip: r = 0.381 passes on 42 raw pairs and fails on their ≈ 5.5 effective ones.
        XCTAssertLessThan(CorrelationEngine.pValue(r: 0.381, n: 42), 0.05)
        XCTAssertGreaterThan(CorrelationEngine.pValue(r: 0.381, n: 5.52), 0.3)
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
