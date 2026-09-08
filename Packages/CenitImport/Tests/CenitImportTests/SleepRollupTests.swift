import XCTest
@testable import CenitImport

/// FER-382 — a night belongs to the day it WOKE UP on, and only three of the six buckets are
/// actually sleep. Both rules are what keeps "you slept 7 h" from quietly counting the time
/// the user lay awake in bed.
final class SleepRollupTests: XCTestCase {

    private let tolerance = 1e-9

    // MARK: - Buckets

    func testAsleepIsCorePlusDeepPlusRemAndExcludesAwakeAndInBed() throws {
        let wakeUpDay = utcInstant(2024, 3, 10, 6)
        let nights = AppleHealthAggregator.sleepDaily([
            sleepSegment(.asleepCore, from: wakeUpDay, to: wakeUpDay.addingTimeInterval(60 * 60)),
            sleepSegment(.asleepDeep, from: wakeUpDay, to: wakeUpDay.addingTimeInterval(30 * 60)),
            sleepSegment(.asleepREM, from: wakeUpDay, to: wakeUpDay.addingTimeInterval(45 * 60)),
            sleepSegment(.awake, from: wakeUpDay, to: wakeUpDay.addingTimeInterval(5 * 60)),
            sleepSegment(.inBed, from: wakeUpDay, to: wakeUpDay.addingTimeInterval(10 * 60)),
        ])
        let night = try XCTUnwrap(nights["2024-03-10"])
        XCTAssertEqual(night.core, 60, accuracy: tolerance)
        XCTAssertEqual(night.deep, 30, accuracy: tolerance)
        XCTAssertEqual(night.rem, 45, accuracy: tolerance)
        XCTAssertEqual(night.awake, 5, accuracy: tolerance)
        XCTAssertEqual(night.inBed, 10, accuracy: tolerance)
        XCTAssertEqual(night.asleep, 135, accuracy: tolerance)
    }

    /// The pre-watchOS-9 "Asleep" value: sleep, but attributable to no stage.
    func testLegacyAsleepCountsAsSleepButNotAsAStage() throws {
        let wakeUp = utcInstant(2024, 3, 10, 6)
        let nights = AppleHealthAggregator.sleepDaily([
            sleepSegment(.asleepUnspecified, from: wakeUp, to: wakeUp.addingTimeInterval(30 * 60)),
        ])
        let night = try XCTUnwrap(nights["2024-03-10"])
        XCTAssertEqual(night.asleep, 30, accuracy: tolerance)
        XCTAssertEqual(night.core, 0, accuracy: tolerance)
        XCTAssertEqual(night.deep, 0, accuracy: tolerance)
        XCTAssertEqual(night.rem, 0, accuracy: tolerance)
    }

    /// An unrecognised category value adds no minutes, but the night still happened.
    func testAnUnknownStageStillCreatesTheNight() throws {
        let wakeUp = utcInstant(2024, 3, 10, 6)
        let nights = AppleHealthAggregator.sleepDaily([
            sleepSegment(.unknown, from: wakeUp, to: wakeUp.addingTimeInterval(60 * 60)),
        ])
        let night = try XCTUnwrap(nights["2024-03-10"])
        XCTAssertEqual(night.asleep, 0, accuracy: tolerance)
        XCTAssertEqual(night.awake, 0, accuracy: tolerance)
        XCTAssertEqual(night.inBed, 0, accuracy: tolerance)
    }

    // MARK: - Which day a night belongs to

    func testASegmentAcrossMidnightBelongsToTheMorningItEndedOn() {
        let nights = AppleHealthAggregator.sleepDaily([
            sleepSegment(.asleepCore,
                         from: utcInstant(2024, 3, 11, 23, 30),
                         to: utcInstant(2024, 3, 12, 0, 30)),
        ])
        XCTAssertNil(nights["2024-03-11"])
        XCTAssertEqual(nights["2024-03-12"]?.core, 60)
    }

    /// An inverted segment contributes nothing but is still evidence the night existed.
    func testAnInvertedSegmentContributesZeroAndStillCreatesTheNight() throws {
        let nights = AppleHealthAggregator.sleepDaily([
            sleepSegment(.asleepDeep,
                         from: utcInstant(2024, 3, 10, 7),
                         to: utcInstant(2024, 3, 10, 6)),
        ])
        let night = try XCTUnwrap(nights["2024-03-10"])
        XCTAssertEqual(night.deep, 0, accuracy: tolerance)
        XCTAssertEqual(night.asleep, 0, accuracy: tolerance)
    }

    // MARK: - Combined rows

    func testACombinedDayCarriesBothItsReadingsAndItsNight() throws {
        let day = utcInstant(2024, 3, 10, 9)
        let rows = AppleHealthAggregator.aggregate(
            samples: [
                quantityReading("RestingHeartRate", 52, at: day),
                quantityReading("StepCount", 8000, at: day),
            ],
            sleepIntervals: [
                sleepSegment(.asleepDeep,
                             from: utcInstant(2024, 3, 10, 5),
                             to: utcInstant(2024, 3, 10, 6)),
            ])
        let row = try onlyRow(rows)
        XCTAssertEqual(row.restingHr, 52)
        XCTAssertEqual(row.steps, 8000)
        XCTAssertEqual(row.deepMin, 60)
        XCTAssertEqual(row.asleepMin, 60)
    }

    /// A night with no daytime readings still yields a row — with every reading field `nil`
    /// and every sleep field present.
    func testANightOnlyDayStillProducesARow() throws {
        let rows = AppleHealthAggregator.aggregate(
            samples: [],
            sleepIntervals: [
                sleepSegment(.asleepREM,
                             from: utcInstant(2024, 3, 10, 5),
                             to: utcInstant(2024, 3, 10, 6)),
            ])
        let row = try onlyRow(rows)
        XCTAssertNil(row.restingHr)
        XCTAssertNil(row.steps)
        XCTAssertEqual(row.remMin, 60)
        XCTAssertEqual(row.asleepMin, 60)
        XCTAssertEqual(row.coreMin, 0)
        XCTAssertEqual(row.deepMin, 0)
        XCTAssertEqual(row.awakeMin, 0)
        XCTAssertEqual(row.inBedMin, 0)
    }

    /// A day with readings and no night leaves all six sleep fields nil — not zero.
    func testAReadingOnlyDayHasNoSleepFieldsAtAll() throws {
        let rows = AppleHealthAggregator.aggregate(
            samples: [quantityReading("BodyMass", 77.0, unit: "kg", at: utcInstant(2024, 3, 10, 8))],
            sleepIntervals: [])
        let row = try onlyRow(rows)
        XCTAssertEqual(row.weightKg, 77.0)
        XCTAssertNil(row.restingHr)
        XCTAssertNil(row.asleepMin)
        XCTAssertNil(row.awakeMin)
        XCTAssertNil(row.inBedMin)
    }

    // MARK: - Stage names

    func testEveryWayAnExportSpellsAStage() {
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisInBed"), .inBed)
        XCTAssertEqual(SleepStage.from(rawValue: "InBed"), .inBed)
        XCTAssertEqual(SleepStage.from(rawValue: "0"), .inBed)

        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleep"), .asleepUnspecified)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepUnspecified"), .asleepUnspecified)
        XCTAssertEqual(SleepStage.from(rawValue: "Asleep"), .asleepUnspecified)
        XCTAssertEqual(SleepStage.from(rawValue: "1"), .asleepUnspecified)

        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAwake"), .awake)
        XCTAssertEqual(SleepStage.from(rawValue: "Awake"), .awake)
        XCTAssertEqual(SleepStage.from(rawValue: "2"), .awake)

        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepCore"), .asleepCore)
        XCTAssertEqual(SleepStage.from(rawValue: "AsleepCore"), .asleepCore)
        XCTAssertEqual(SleepStage.from(rawValue: "3"), .asleepCore)

        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepDeep"), .asleepDeep)
        XCTAssertEqual(SleepStage.from(rawValue: "AsleepDeep"), .asleepDeep)
        XCTAssertEqual(SleepStage.from(rawValue: "4"), .asleepDeep)

        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisAsleepREM"), .asleepREM)
        XCTAssertEqual(SleepStage.from(rawValue: "AsleepREM"), .asleepREM)
        XCTAssertEqual(SleepStage.from(rawValue: "5"), .asleepREM)

        XCTAssertEqual(SleepStage.from(rawValue: ""), .unknown)
        XCTAssertEqual(SleepStage.from(rawValue: "HKCategoryValueSleepAnalysisSomethingNew"), .unknown)
        XCTAssertEqual(SleepStage.from(rawValue: "9"), .unknown)
    }
}
