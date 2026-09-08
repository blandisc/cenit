import XCTest
@testable import CenitImport

/// FER-382 — reading Apple's timestamps.
///
/// The fast path runs twice per record over tens of millions of records, so it is allowed to
/// recognise ONLY Apple's exact fixed-width spelling; everything it declines has to be caught
/// by the tolerant path, and neither is allowed to invent an answer.
final class HealthTimestampTests: XCTestCase {

    private let reader = HealthTimestampReader()

    // MARK: - Fixed-width

    func testTheCanonicalSpellingsResolveToInstantAndOffset() throws {
        let cases: [(String, Date, Int)] = [
            ("2024-01-02 03:04:05 +0000", utcInstant(2024, 1, 2, 3, 4, 5), 0),
            ("2024-06-01 14:30:00 -0500", utcInstant(2024, 6, 1, 19, 30), -300),
            ("2024-12-31 23:30:00 +0100", utcInstant(2024, 12, 31, 22, 30), 60),
            ("2024-02-29 12:00:00 +0530", utcInstant(2024, 2, 29, 6, 30), 330),
            ("2024-06-01 14:30:00 Z", utcInstant(2024, 6, 1, 14, 30), 0),
            ("2024-06-01 14:30:00 +01:30", utcInstant(2024, 6, 1, 13, 0), 90),
        ]
        for (text, expected, offset) in cases {
            let parsed = try XCTUnwrap(HealthTimestampReader.parseFixedWidth(text), text)
            XCTAssertEqual(parsed.utc, expected, text)
            XCTAssertEqual(parsed.offsetMinutes, offset, text)
        }
    }

    /// No offset token at all means UTC.
    func testATimestampWithNoZoneIsRead() throws {
        let parsed = try XCTUnwrap(HealthTimestampReader.parseFixedWidth("2024-06-01 14:30:00"))
        XCTAssertEqual(parsed.utc, utcInstant(2024, 6, 1, 14, 30))
        XCTAssertEqual(parsed.offsetMinutes, 0)
    }

    func testTheFastPathDeclinesAnythingItDoesNotRecognise() {
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024/06/01 14:30:00 +0000"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("not a date"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024-13-01 14:30:00 +0000"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024-06-32 14:30:00 +0000"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024-06-01 24:30:00 +0000"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024-06-01 14:60:00 +0000"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth("2024-06-01T14:30:00Z"))
        XCTAssertNil(HealthTimestampReader.parseFixedWidth(""))
    }

    /// A leap second is a real timestamp, not corruption.
    func testALeapSecondIsAccepted() {
        XCTAssertNotNil(HealthTimestampReader.parseFixedWidth("2016-12-31 23:59:60 +0000"))
    }

    // MARK: - Tolerant path

    func testISO8601FallsThroughToTheTolerantPath() throws {
        let parsed = try XCTUnwrap(reader.parse("2024-06-01T14:30:00Z"))
        XCTAssertEqual(parsed.utc, utcInstant(2024, 6, 1, 14, 30))
        XCTAssertEqual(parsed.offsetMinutes, 0)
    }

    func testISO8601WithAnOffsetKeepsThatOffset() throws {
        let parsed = try XCTUnwrap(reader.parse("2024-06-01T14:30:00-05:00"))
        XCTAssertEqual(parsed.utc, utcInstant(2024, 6, 1, 19, 30))
        XCTAssertEqual(parsed.offsetMinutes, -300)
    }

    func testUnparseableTextIsRejectedByBothPaths() {
        XCTAssertNil(reader.parse("not a date"))
        XCTAssertNil(reader.parse(""))
        XCTAssertNil(reader.parse("2024-06-01 lunch time"))
    }

    /// The offset search is confined to the tail, so the hyphens of the date itself are never
    /// mistaken for a sign.
    func testTheOffsetIsRecoveredFromTheTailOnly() {
        XCTAssertEqual(HealthTimestampReader.trailingOffsetMinutes("2024-06-01T14:30:00Z"), 0)
        XCTAssertEqual(HealthTimestampReader.trailingOffsetMinutes("2024-06-01 14:30:00 -0500"), -300)
        XCTAssertEqual(HealthTimestampReader.trailingOffsetMinutes("2024-06-01 14:30:00 +05:45"), 345)
        XCTAssertEqual(HealthTimestampReader.trailingOffsetMinutes("2024-06-01 14:30:00 +07"), 420)
        XCTAssertEqual(HealthTimestampReader.trailingOffsetMinutes("2024-06-01 14:30:00"), 0)
    }

    // MARK: - Civil arithmetic

    /// The integer calendar and Foundation's have to agree, or the whole day key drifts.
    func testTheIntegerCalendarAgreesWithFoundation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        for offsetDays in stride(from: -20_000, through: 20_000, by: 137) {
            let instant = Date(timeIntervalSince1970: TimeInterval(offsetDays * 86_400))
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            let ours = CivilTime.civilFromDays(offsetDays)
            XCTAssertEqual(ours.year, parts.year, "day \(offsetDays)")
            XCTAssertEqual(ours.month, parts.month, "day \(offsetDays)")
            XCTAssertEqual(ours.day, parts.day, "day \(offsetDays)")
            XCTAssertEqual(CivilTime.daysFromCivil(year: ours.year, month: ours.month, day: ours.day),
                           offsetDays)
        }
    }

    /// Before the epoch a day must round DOWN, not toward zero.
    func testDaysBeforeTheEpochRoundDown() {
        XCTAssertEqual(AppleHealthAggregator.localDay(Date(timeIntervalSince1970: -1), tzOffsetMin: 0),
                       "1969-12-31")
        XCTAssertEqual(AppleHealthAggregator.localDay(Date(timeIntervalSince1970: 0), tzOffsetMin: 0),
                       "1970-01-01")
    }
}
