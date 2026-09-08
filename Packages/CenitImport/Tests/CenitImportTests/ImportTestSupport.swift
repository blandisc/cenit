import XCTest
@testable import CenitImport

// MARK: - Shared test utilities (FER-382)
//
// Two things the import tests all need: an exact UTC instant built from calendar fields, and
// a fixture file out of the module bundle. The instant is built with `Calendar`/`TimeZone` on
// purpose — production does the same arithmetic with integers, so building the expectation
// with Foundation anchors that arithmetic against a second, independent implementation.

/// The UTC instant of a wall-clock date, to the second.
func utcInstant(_ year: Int, _ month: Int, _ day: Int,
                _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
                file: StaticString = #filePath, line: UInt = #line) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.year = year; components.month = month; components.day = day
    components.hour = hour; components.minute = minute; components.second = second
    guard let date = calendar.date(from: components) else {
        XCTFail("Could not build \(year)-\(month)-\(day) \(hour):\(minute):\(second) UTC",
                file: file, line: line)
        return Date(timeIntervalSince1970: 0)
    }
    return date
}

/// A fixture from the test bundle's copied `Resources` folder.
func bundledResource(_ name: String, _ extension: String) throws -> URL {
    if let url = Bundle.module.url(forResource: name, withExtension: `extension`,
                                  subdirectory: "Resources") {
        return url
    }
    return try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: `extension`))
}

// MARK: - Building readings

/// A quantity reading. `end` defaults to `start`, which is what an instantaneous sample looks
/// like in a real export.
func quantityReading(_ type: String, _ value: Double?, unit: String? = nil,
                     at start: Date, end: Date? = nil,
                     tzOffsetMin: Int = 0, sourceName: String? = nil) -> HealthSample {
    HealthSample(type: type, value: value, valueString: nil, unit: unit,
                 start: start, end: end ?? start, tzOffsetMin: tzOffsetMin,
                 sourceName: sourceName)
}

/// A stretch of one sleep stage.
func sleepSegment(_ stage: SleepStage, from start: Date, to end: Date,
                  tzOffsetMin: Int = 0) -> SleepStageInterval {
    SleepStageInterval(stage: stage, start: start, end: end,
                       tzOffsetMin: tzOffsetMin, sourceName: nil)
}

/// The single row a one-day reduction is expected to produce.
func onlyRow(_ rows: [AppleDailyAggregate],
             file: StaticString = #filePath, line: UInt = #line) throws -> AppleDailyAggregate {
    XCTAssertEqual(rows.count, 1, "expected exactly one day", file: file, line: line)
    return try XCTUnwrap(rows.first, file: file, line: line)
}
