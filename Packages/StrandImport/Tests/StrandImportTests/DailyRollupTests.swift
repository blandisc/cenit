import XCTest
@testable import StrandImport

/// FER-382 — the reduction rules: what a day's readings collapse to, and which civil day a
/// reading belongs to.
///
/// The day string is the de-facto primary key of nearly every table the user owns, so the
/// timezone cases below are not edge cases — getting one wrong moves history under data that
/// is already stored, without raising a single error.
final class DailyRollupTests: XCTestCase {

    private let tolerance = 1e-9
    private lazy var noon = utcInstant(2024, 3, 7, 12)

    // MARK: - Means

    func testAveragedMetricsAreTheMeanOfTheDay() throws {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("RestingHeartRate", 50, at: noon),
            quantityReading("RestingHeartRate", 60, at: noon),
            quantityReading("HeartRateVariabilitySDNN", 40, at: noon),
            quantityReading("HeartRateVariabilitySDNN", 60, at: noon),
            quantityReading("RespiratoryRate", 14, at: noon),
            quantityReading("RespiratoryRate", 16, at: noon),
            quantityReading("WalkingHeartRateAverage", 90, at: noon),
            quantityReading("WalkingHeartRateAverage", 110, at: noon),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(try XCTUnwrap(day.restingHr), 55, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.hrvSDNN), 50, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.respRate), 15, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.walkingHr), 100, accuracy: tolerance)
    }

    /// One stream of heart rates feeds two fields.
    func testHeartRateProducesBothTheMeanAndTheMaximum() throws {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("HeartRate", 60, at: noon),
            quantityReading("HeartRate", 80, at: noon),
            quantityReading("HeartRate", 130, at: noon),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(try XCTUnwrap(day.avgHr), 90, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.maxHr), 130, accuracy: tolerance)
    }

    // MARK: - Sums

    func testCountedMetricsAddUp() throws {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 1000, at: noon),
            quantityReading("StepCount", 2500, at: noon),
            quantityReading("ActiveEnergyBurned", 100, at: noon),
            quantityReading("ActiveEnergyBurned", 50, at: noon),
            quantityReading("BasalEnergyBurned", 700, at: noon),
            quantityReading("BasalEnergyBurned", 800, at: noon),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(try XCTUnwrap(day.steps), 3500, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.activeKcal), 150, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.basalKcal), 1500, accuracy: tolerance)
    }

    /// "Nothing" and "no data" are different answers: a day that logged zero steps must not
    /// read the same as a day the phone stayed on the table.
    func testAZeroSumIsNotTheSameAsNoData() throws {
        let logged = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 0, at: noon),
        ]))
        XCTAssertEqual(logged.steps, 0)
        XCTAssertNil(logged.activeKcal)
    }

    // MARK: - Last of the day

    func testLastReadingOfTheDayWins() throws {
        let morning = utcInstant(2024, 3, 7, 7)
        let evening = utcInstant(2024, 3, 7, 19)
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("VO2Max", 42.0, at: utcInstant(2024, 3, 7, 8)),
            quantityReading("VO2Max", 45.0, at: utcInstant(2024, 3, 7, 18)),
            quantityReading("BodyMass", 80.0, at: morning),
            quantityReading("BodyMass", 79.5, at: evening),
            quantityReading("LeanBodyMass", 60.0, at: morning),
            quantityReading("LeanBodyMass", 61.0, at: evening),
            quantityReading("BodyMassIndex", 24.0, at: morning),
            quantityReading("BodyMassIndex", 23.8, at: evening),
            quantityReading("BodyFatPercentage", 0.20, at: morning),
            quantityReading("BodyFatPercentage", 0.19, at: evening),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(try XCTUnwrap(day.vo2max), 45.0, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.weightKg), 79.5, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.leanMassKg), 61.0, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.bmi), 23.8, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.bodyFatPct), 19, accuracy: tolerance)
    }

    // MARK: - Normalisation

    /// Apple writes saturation and body fat as a 0–1 fraction; a value already above 1 is
    /// taken to be a percentage and left alone.
    func testFractionsBecomePercentagesAndPercentagesAreLeftAlone() throws {
        let asFraction = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("OxygenSaturation", 0.97, at: noon),
            quantityReading("OxygenSaturation", 0.95, at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(asFraction.spo2Pct), 96, accuracy: tolerance)

        let asPercent = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("OxygenSaturation", 97, at: noon),
            quantityReading("OxygenSaturation", 95, at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(asPercent.spo2Pct), 96, accuracy: tolerance)

        let fat = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("BodyFatPercentage", 0.18, at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(fat.bodyFatPct), 18, accuracy: tolerance)

        let fatAlready = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("BodyFatPercentage", 22.0, at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(fatAlready.bodyFatPct), 22, accuracy: tolerance)
    }

    func testPoundsConvertToKilogramsAndAMissingUnitIsMetric() throws {
        let noUnit = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("BodyMass", 75.0, at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(noUnit.weightKg), 75.0, accuracy: 1e-6)

        let kilograms = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("BodyMass", 90.0, unit: "kg", at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(kilograms.weightKg), 90.0, accuracy: 1e-6)

        let pounds = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("BodyMass", 200.0, unit: "lb", at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(pounds.weightKg), 90.7184, accuracy: 1e-6)

        let leanPounds = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("LeanBodyMass", 150.0, unit: "lbs", at: noon),
        ]))
        XCTAssertEqual(try XCTUnwrap(leanPounds.leanMassKg), 68.0388, accuracy: 1e-6)
    }

    /// The full HealthKit identifier and its bare suffix are the same metric.
    func testFullIdentifiersReduceLikeStrippedOnes() throws {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("HKQuantityTypeIdentifierRestingHeartRate", 55, at: noon),
            quantityReading("HKQuantityTypeIdentifierStepCount", 1234, at: noon),
            quantityReading("HKQuantityTypeIdentifierBodyMass", 82.0, unit: "kg", at: noon),
            quantityReading("HKQuantityTypeIdentifierBodyFatPercentage", 0.21, at: noon),
            quantityReading("HKQuantityTypeIdentifierLeanBodyMass", 64.0, unit: "kg", at: noon),
            quantityReading("HKQuantityTypeIdentifierBodyMassIndex", 25.1, at: noon),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(try XCTUnwrap(day.restingHr), 55, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.steps), 1234, accuracy: tolerance)
        XCTAssertEqual(try XCTUnwrap(day.weightKg), 82.0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(day.bodyFatPct), 21, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(day.leanMassKg), 64.0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(day.bmi), 25.1, accuracy: 1e-6)
    }

    // MARK: - Days without numbers

    /// A reading with no usable value is not evidence that the day happened.
    func testAValuelessReadingDoesNotCreateTheDay() {
        XCTAssertTrue(AppleHealthAggregator.daily(samples: [
            quantityReading("HeartRate", nil, at: noon),
        ]).isEmpty)
    }

    /// Body temperature IS imported — it just has nowhere to land yet. Its day still shows
    /// up, empty, and emits no metric point at all.
    func testARelevantTypeWithNoFieldStillProducesAnEmptyDay() throws {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("BodyTemperature", 36.6, unit: "degC", at: noon),
        ])
        let day = try onlyRow(rows)
        XCTAssertEqual(day.day, "2024-03-07")
        XCTAssertNil(day.restingHr)
        XCTAssertNil(day.steps)
        XCTAssertNil(day.weightKg)
        XCTAssertNil(day.asleepMin)
        XCTAssertTrue(AppleHealthAggregator.metricPoints(rows).isEmpty)
    }

    // MARK: - Civil day

    func testTheCivilDayFollowsTheOffsetTheReadingCarried() {
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 3, 7, 22, 30), tzOffsetMin: 60),
                       "2024-03-07")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 3, 7, 23, 30), tzOffsetMin: 60),
                       "2024-03-08")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 3, 8, 2), tzOffsetMin: -300),
                       "2024-03-07")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 12, 31, 23, 30), tzOffsetMin: 60),
                       "2025-01-01")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2025, 1, 1, 4, 30), tzOffsetMin: -300),
                       "2024-12-31")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 6, 30, 19), tzOffsetMin: 540),
                       "2024-07-01")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 1, 1, 0, 30), tzOffsetMin: -60),
                       "2023-12-31")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2024, 2, 29, 12), tzOffsetMin: 0),
                       "2024-02-29")
        XCTAssertEqual(AppleHealthAggregator.localDay(utcInstant(2025, 2, 28, 23), tzOffsetMin: 120),
                       "2025-03-01")
    }

    /// Either side of a daylight-saving change, each reading carrying its own offset, still
    /// the same day — the device's own time zone never enters into it.
    func testADaylightSavingChangeDoesNotSplitTheDay() {
        let before = AppleHealthAggregator.localDay(utcInstant(2024, 3, 10, 6), tzOffsetMin: -300)
        let after = AppleHealthAggregator.localDay(utcInstant(2024, 3, 10, 18), tzOffsetMin: -240)
        XCTAssertEqual(before, "2024-03-10")
        XCTAssertEqual(after, "2024-03-10")
    }

    /// The same instant filed under two offsets that land on the same civil day is one row.
    func testTwoOffsetsOnTheSameCivilDayCollapseToOneRow() {
        let instant = utcInstant(2024, 3, 7, 22, 30)
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 100, at: instant, tzOffsetMin: 60),
            quantityReading("StepCount", 200, at: instant, tzOffsetMin: 0),
        ])
        XCTAssertEqual(rows.map(\.day), ["2024-03-07"])
        XCTAssertEqual(rows[0].steps, 300)
    }

    /// Rows come out in ascending day order whatever order the records arrived in — the app
    /// consumes the array exactly as it is handed over.
    func testRowsComeOutInAscendingDayOrder() {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 200, at: utcInstant(2024, 3, 2, 10)),
            quantityReading("StepCount", 100, at: utcInstant(2024, 3, 1, 10)),
            quantityReading("StepCount", 300, at: utcInstant(2024, 3, 3, 10)),
        ])
        XCTAssertEqual(rows.map(\.day), ["2024-03-01", "2024-03-02", "2024-03-03"])
        XCTAssertEqual(rows.map(\.steps), [100, 200, 300])
    }

    // MARK: - Cross-source dedup (FER-411)

    /// The same day recorded by iPhone AND Apple Watch must not double-count cumulative types.
    /// We keep the largest single-source total (mirrors the live `HKStatisticsCollectionQuery`), never
    /// the sum across sources.
    func testCumulativeMetricsDoNotDoubleCountAcrossSources() throws {
        let day = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 3000, at: noon, sourceName: "iPhone"),
            quantityReading("StepCount", 3200, at: noon, sourceName: "Apple Watch"),
            quantityReading("ActiveEnergyBurned", 400, at: noon, sourceName: "iPhone"),
            quantityReading("ActiveEnergyBurned", 520, at: noon, sourceName: "Apple Watch"),
            quantityReading("BasalEnergyBurned", 1400, at: noon, sourceName: "iPhone"),
            quantityReading("BasalEnergyBurned", 1450, at: noon, sourceName: "Apple Watch"),
        ]))
        XCTAssertEqual(try XCTUnwrap(day.steps), 3200, accuracy: tolerance, "max source, not 6200")
        XCTAssertEqual(try XCTUnwrap(day.activeKcal), 520, accuracy: tolerance, "max source, not 920")
        XCTAssertEqual(try XCTUnwrap(day.basalKcal), 1450, accuracy: tolerance, "max source, not 2850")
    }

    /// Within ONE source, samples still add up (the dedup is across sources, not within one).
    func testSingleSourceDayStillSums() throws {
        let day = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 1000, at: noon, sourceName: "Apple Watch"),
            quantityReading("StepCount", 2500, at: noon, sourceName: "Apple Watch"),
        ]))
        XCTAssertEqual(try XCTUnwrap(day.steps), 3500, accuracy: tolerance)
    }

    /// Discrete metrics (heart rate) are NOT source-selected: they average across sources, exactly like
    /// the live path. Only cumulative sums were double-counting.
    func testDiscreteMetricsStillAverageAcrossSources() throws {
        let day = try onlyRow(AppleHealthAggregator.daily(samples: [
            quantityReading("HeartRate", 60, at: noon, sourceName: "iPhone"),
            quantityReading("HeartRate", 80, at: noon, sourceName: "Apple Watch"),
        ]))
        XCTAssertEqual(try XCTUnwrap(day.avgHr), 70, accuracy: tolerance)
    }
}
