import XCTest
@testable import CenitImport

/// FER-382 — the package's version marker and the identity of a raw record.
final class PackageMarkerTests: XCTestCase {

    func testTheVersionMarkerIsPinned() {
        XCTAssertEqual(CenitImport.version, "0.1.0")
    }

    func testTheRelevantTypeListIsTheOneTheImporterFilters() {
        XCTAssertEqual(AppleHealthImporter.relevantTypes.count, 17)
        XCTAssertTrue(AppleHealthImporter.relevantTypes.contains("SleepAnalysis"))
        XCTAssertTrue(AppleHealthImporter.relevantTypes.contains("BodyTemperature"))
        XCTAssertTrue(AppleHealthImporter.relevantTypes.contains("AppleSleepingWristTemperature"))
        XCTAssertFalse(AppleHealthImporter.relevantTypes.contains("DietaryWater"))
        // The list holds prefix-free names; the raw identifier is stripped before the lookup.
        XCTAssertFalse(AppleHealthImporter.relevantTypes.contains("HKQuantityTypeIdentifierHeartRate"))
    }

    /// `dedupeKey` is published API with an observable shape.
    func testTheDedupeKeyShape() {
        let instant = Date(timeIntervalSince1970: 100)
        let quantity = HealthSample(type: "HeartRate", value: 70, valueString: nil, unit: "count/min",
                                    start: instant, end: instant, tzOffsetMin: 0, sourceName: "Reloj")
        XCTAssertEqual(quantity.dedupeKey, "HeartRate|100.0|100.0|Reloj|70.0")

        let category = HealthSample(type: "SleepAnalysis", value: nil, valueString: "AsleepDeep",
                                    unit: nil, start: instant, end: instant,
                                    tzOffsetMin: 0, sourceName: nil)
        XCTAssertEqual(category.dedupeKey, "SleepAnalysis|100.0|100.0||AsleepDeep")

        let bare = HealthSample(type: "BodyMass", value: nil, valueString: nil, unit: nil,
                                start: instant, end: instant, tzOffsetMin: 0, sourceName: nil)
        XCTAssertEqual(bare.dedupeKey, "BodyMass|100.0|100.0||")
    }

    /// `skippedSpans` has to keep its default: there are call sites that never pass it.
    func testTheSummaryInitDefaultsItsSpanCount() {
        let summary = ImportSummary(sourceKind: .appleHealth, recordCount: 3,
                                    earliest: nil, latest: nil, countsByCategory: [:])
        XCTAssertEqual(summary.skippedSpans, 0)
    }

    /// Same for the daily row: callers build one with just the fields they have.
    func testTheDailyRowInitDefaultsEverythingButTheDay() {
        let row = AppleDailyAggregate(day: "2024-01-02", steps: 100)
        XCTAssertEqual(row.day, "2024-01-02")
        XCTAssertEqual(row.steps, 100)
        XCTAssertNil(row.restingHr)
        XCTAssertNil(row.inBedMin)
    }
}
