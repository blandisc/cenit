import XCTest
@testable import CenitImport

/// FER-382 — flattening a day into `(day, key, value)` triples.
///
/// THE KEYS ARE PERSISTED IN THE USER'S DATABASE. Renaming one orphans that metric's entire
/// history without raising a single error, so the names and the emission order are pinned
/// here rather than left to whatever the code happens to do.
final class MetricPointTests: XCTestCase {

    func testEveryPresentFieldEmitsItsKeyInOrder() throws {
        let morning = utcInstant(2024, 3, 10, 9)
        let rows = AppleHealthAggregator.aggregate(
            samples: [
                quantityReading("RestingHeartRate", 50, at: morning),
                quantityReading("HeartRateVariabilitySDNN", 60, at: morning),
                quantityReading("OxygenSaturation", 0.97, at: morning),
                quantityReading("RespiratoryRate", 15, at: morning),
                quantityReading("HeartRate", 70, at: morning),
                quantityReading("HeartRate", 120, at: morning),
                quantityReading("StepCount", 5000, at: morning),
                quantityReading("ActiveEnergyBurned", 300, at: morning),
                quantityReading("BasalEnergyBurned", 1500, at: morning),
                quantityReading("WalkingHeartRateAverage", 95, at: morning),
                quantityReading("VO2Max", 44, at: morning),
            ],
            sleepIntervals: [
                sleepSegment(.asleepCore, from: utcInstant(2024, 3, 10, 4),
                             to: utcInstant(2024, 3, 10, 5)),
                sleepSegment(.asleepDeep, from: utcInstant(2024, 3, 10, 5),
                             to: utcInstant(2024, 3, 10, 5, 30)),
                sleepSegment(.asleepREM, from: utcInstant(2024, 3, 10, 5, 30),
                             to: utcInstant(2024, 3, 10, 6)),
            ])

        let points = AppleHealthAggregator.metricPoints(rows)
        var byKey: [String: Double] = [:]
        for point in points {
            XCTAssertEqual(point.day, "2024-03-10")
            byKey[point.key] = point.value
        }
        XCTAssertEqual(byKey["resting_hr"], 50)
        XCTAssertEqual(byKey["hrv"], 60)
        XCTAssertEqual(byKey["spo2"], 97)
        XCTAssertEqual(byKey["resp_rate"], 15)
        XCTAssertEqual(byKey["avg_hr"], 95)
        XCTAssertEqual(byKey["max_hr"], 120)
        XCTAssertEqual(byKey["walking_hr"], 95)
        XCTAssertEqual(byKey["steps"], 5000)
        XCTAssertEqual(byKey["active_kcal"], 300)
        XCTAssertEqual(byKey["basal_kcal"], 1500)
        XCTAssertEqual(byKey["vo2max"], 44)
        XCTAssertEqual(byKey["asleep_min"], 120)
        XCTAssertEqual(byKey["core_min"], 60)
        XCTAssertEqual(byKey["deep_min"], 30)
        XCTAssertEqual(byKey["rem_min"], 30)

        // The order the store reads them back in.
        XCTAssertEqual(points.map(\.key), [
            "resting_hr", "hrv", "spo2", "resp_rate", "avg_hr", "max_hr", "walking_hr",
            "steps", "active_kcal", "basal_kcal", "vo2max",
            "asleep_min", "deep_min", "rem_min", "core_min", "awake_min", "in_bed_min",
        ])
    }

    func testBodyCompositionKeys() throws {
        let noon = utcInstant(2024, 3, 10, 12)
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("BodyMass", 78.0, unit: "kg", at: noon),
            quantityReading("BodyFatPercentage", 0.20, at: noon),
            quantityReading("LeanBodyMass", 62.0, unit: "kg", at: noon),
            quantityReading("BodyMassIndex", 24.5, at: noon),
        ])
        let byKey = Dictionary(uniqueKeysWithValues:
            AppleHealthAggregator.metricPoints(rows).map { ($0.key, $0.value) })
        XCTAssertEqual(byKey["weight"], 78.0)
        XCTAssertEqual(byKey["body_fat"], 20)
        XCTAssertEqual(byKey["lean_mass"], 62.0)
        XCTAssertEqual(byKey["bmi"], 24.5)
    }

    /// A `nil` field emits nothing at all — an absent metric must not be stored as a zero.
    func testOnlyPresentValuesAreEmitted() {
        let noon = utcInstant(2024, 3, 10, 12)

        let stepsOnly = AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 100, at: noon),
        ])
        XCTAssertEqual(Set(AppleHealthAggregator.metricPoints(stepsOnly).map(\.key)), ["steps"])

        let weightOnly = AppleHealthAggregator.daily(samples: [
            quantityReading("BodyMass", 80.0, unit: "kg", at: noon),
        ])
        XCTAssertEqual(Set(AppleHealthAggregator.metricPoints(weightOnly).map(\.key)), ["weight"])
    }

    func testDaysAreEmittedInTheOrderTheyWereGiven() {
        let rows = AppleHealthAggregator.daily(samples: [
            quantityReading("StepCount", 100, at: utcInstant(2024, 3, 1, 10)),
            quantityReading("StepCount", 200, at: utcInstant(2024, 3, 2, 10)),
        ])
        XCTAssertEqual(AppleHealthAggregator.metricPoints(rows).map(\.day),
                       ["2024-03-01", "2024-03-02"])
    }
}
