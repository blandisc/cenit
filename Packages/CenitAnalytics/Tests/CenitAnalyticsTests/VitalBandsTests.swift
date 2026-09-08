import XCTest
@testable import CenitAnalytics

/// «In range» for THIS person: which comparison the engine picks, and in what order.
///
/// The exact z depends on the winsorised EWMA in `Baselines`, so the personal cases here are
/// RELATIONAL — they assert which basis was used and that the band agrees with the σ criterion,
/// rather than re-deriving the baseline arithmetic a second time.
final class VitalBandsTests: XCTestCase {

    private var hrvCfg: MetricCfg { Baselines.hrvCfg }
    /// The population reference range for HRV that this engine exists to override.
    private let hrvPopulation: ClosedRange<Double> = 40...120

    private func nights(_ v: Double, _ n: Int) -> [Double?] {
        Array(repeating: v, count: n)
    }

    // MARK: - The order of the checks

    func testNoValueIsNoData() {
        let r = VitalBands.band(value: nil, history: nights(35, 30),
                                populationRange: hrvPopulation, cfg: hrvCfg)
        XCTAssertEqual(r.band, .noData)
        XCTAssertEqual(r.basis, .population)
        XCTAssertEqual(r.nights, 0)
    }

    /// With no baseline configuration the population range decides, permanently — the right answer
    /// for a metric where an absolute floor is meaningful whatever the person's history.
    func testWithoutAConfigurationThePopulationRangeDecides() {
        let r = VitalBands.band(value: 93, history: [], populationRange: 95...100, cfg: nil)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .population)
        XCTAssertEqual(r.nights, 0)
    }

    /// THE CASE THE ENGINE EXISTS FOR. A person whose HRV has sat at 35 ms every night is in range
    /// for themselves, even though a textbook band starts at 40.
    func testASteadyPersonalNormalIsInRangeEvenOutsideThePopulationBand() {
        let r = VitalBands.band(value: 35, history: nights(35, 14),
                                populationRange: hrvPopulation, cfg: hrvCfg)
        XCTAssertEqual(r.basis, .personal)
        XCTAssertEqual(r.band, .inRange)
        XCTAssertEqual(r.nights, 14)
    }

    /// Before the baseline is trustworthy the population range still decides, and the answer says so.
    func testTooFewNightsFallsBackToThePopulationRange() {
        let r = VitalBands.band(value: 35, history: nights(35, 10),
                                populationRange: hrvPopulation, cfg: hrvCfg)
        XCTAssertEqual(r.basis, .population)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.nights, 10)
    }

    func testThinBaselineFallsBackEvenWithGapsPadded() {
        let history: [Double?] = Array(repeating: nil, count: 10) + nights(35, 13)
        XCTAssertEqual(VitalBands.band(value: 35, history: history,
                                       populationRange: hrvPopulation, cfg: hrvCfg).basis,
                       .population, "13 valid nights is under the trust floor")
    }

    /// A baseline that has not been fed for weeks is stale, and stale is not trusted. The `nil` nights
    /// are what make that visible.
    func testStaleBaselineFallsBackToThePopulationRange() {
        let history: [Double?] = nights(35, 20) + Array(repeating: nil, count: 20)
        XCTAssertEqual(VitalBands.band(value: 35, history: history,
                                       populationRange: hrvPopulation, cfg: hrvCfg).basis,
                       .population)
    }

    func testAValueFarFromThePersonalNormalIsOutOfRange() {
        let r = VitalBands.band(value: 70, history: nights(35, 30),
                                populationRange: hrvPopulation, cfg: hrvCfg)
        XCTAssertEqual(r.basis, .personal)
        XCTAssertEqual(r.band, .outOfRange)
    }

    /// Absolute implausibility outranks any amount of personal dispersion: this check cannot move
    /// below the personal branch, or a wide baseline would end up excusing an impossible reading.
    func testImplausibleValuesAreOutOfRangeWhateverTheBaselineSays() {
        let r = VitalBands.band(value: 300, history: nights(35, 30),
                                populationRange: hrvPopulation, cfg: hrvCfg)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .population, "a plausibility rejection is not a personal judgement")
    }

    /// On the personal branch the band is exactly the σ criterion — nothing else decides it.
    func testThePersonalBandIsExactlyTheSigmaCriterion() {
        let history = (0..<30).map { Double?(35.0 + ($0 % 2 == 0 ? 1.5 : -1.5)) }
        let state = Baselines.foldHistory(history, cfg: hrvCfg)
        XCTAssertTrue(state.trusted)
        for value in stride(from: 20.0, through: 70.0, by: 0.5) {
            let r = VitalBands.band(value: value, history: history,
                                    populationRange: hrvPopulation, cfg: hrvCfg)
            guard r.basis == .personal else { continue }
            let z = Baselines.deviation(value, state: state).z
            XCTAssertEqual(r.band == .inRange, abs(z) <= VitalBands.sigmaK,
                           "value \(value) has |z| = \(abs(z))")
        }
    }

    func testSigmaKIsTwo() {
        XCTAssertEqual(VitalBands.sigmaK, 2.0, accuracy: 1e-12)
    }

    // MARK: - Skin temperature's two semantics

    func testAbsoluteAndDeviationReadingsAreSeparableWithoutAmbiguity() {
        XCTAssertTrue(VitalBands.isAbsoluteSkinTemp(34.1))
        XCTAssertTrue(VitalBands.isAbsoluteSkinTemp(20.0))
        XCTAssertFalse(VitalBands.isAbsoluteSkinTemp(0.3))
        XCTAssertFalse(VitalBands.isAbsoluteSkinTemp(-0.4))
        XCTAssertFalse(VitalBands.isAbsoluteSkinTemp(19.9))
    }

    /// The history is filtered to the semantics of the value being shown, positions preserved.
    func testHistoryIsFilteredToMatchTheShownReading() {
        let history: [Double?] = [34.1, 0.2, nil, 33.8, -0.1]
        XCTAssertEqual(VitalBands.skinTempHistory(matching: 0.3, in: history),
                       [nil, 0.2, nil, nil, -0.1])
        XCTAssertEqual(VitalBands.skinTempHistory(matching: 34.0, in: history),
                       [34.1, nil, nil, 33.8, nil])
    }

    // MARK: - Padding the calendar

    /// Missing days become `nil`, which is what lets a baseline notice it has gone stale.
    func testCalendarSeriesPadsTheDaysWithNoReading() {
        XCTAssertEqual(VitalBands.calendarSeries([("2026-06-01", 50), ("2026-06-04", 52)]),
                       [50, nil, nil, 52])
    }

    func testCalendarSeriesOfNothingIsNothing() {
        XCTAssertTrue(VitalBands.calendarSeries([]).isEmpty)
    }

    func testCalendarSeriesDropsMalformedKeys() {
        XCTAssertEqual(VitalBands.calendarSeries([("not-a-date", 1), ("2026-06-01", 50)]), [50])
    }

    func testCalendarSeriesKeepsTheLastValueForARepeatedDay() {
        XCTAssertEqual(VitalBands.calendarSeries([("2026-06-01", 50), ("2026-06-01", 51)]), [51])
    }

    /// A month boundary is ordinary calendar arithmetic, fixed to UTC over the key strings.
    func testCalendarSeriesSpansAMonthBoundary() {
        XCTAssertEqual(VitalBands.calendarSeries([("2026-05-30", 1), ("2026-06-02", 2)]),
                       [1, nil, nil, 2])
    }
}
