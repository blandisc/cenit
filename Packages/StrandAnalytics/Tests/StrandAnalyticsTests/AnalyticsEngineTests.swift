import XCTest
import Foundation
@testable import StrandAnalytics

/// The two conversions the whole database agrees on: the civil-day key and the stage codec.
///
/// The day-key cases matter more than they look. Every daily row is ADDRESSED by that string, so a
/// formatter configured with the wrong locale or zone would quietly rename every row already stored.
final class AnalyticsEngineTests: XCTestCase {

    private let f: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    func testPackageVersion() {
        XCTAssertEqual(StrandAnalytics.version, "0.1.0")
    }

    // MARK: - Day keys

    func testDayStringAtUTCMidnight() {
        // 1 609 459 200 is midnight UTC on new year's day 2021 — the reference point for the key.
        XCTAssertEqual(AnalyticsEngine.dayString(1_609_459_200), "2021-01-01")
    }

    func testDayKeysSortChronologically() {
        // Fixed width and zero padding are what make a plain string comparison a date comparison.
        let a = AnalyticsEngine.dayString(utcTimestamp("2026-09-09 12:00:00"))
        let b = AnalyticsEngine.dayString(utcTimestamp("2026-09-10 12:00:00"))
        XCTAssertLessThan(a, b)
    }

    // MARK: - Local civil-day attribution (FER-226)

    func testDayStringLocalNegativeOffsetCrossesMidnight() {
        // 2026-06-18 01:30:00 UTC is still 2026-06-17 19:30 in México (UTC−6) — the exact incident.
        let ts = utcTimestamp("2026-06-18 01:30:00")
        XCTAssertEqual(AnalyticsEngine.dayString(ts), "2026-06-18")                          // default = UTC
        XCTAssertEqual(AnalyticsEngine.dayString(ts, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        // A positive offset (e.g. UTC+10) rolls an early-UTC instant forward into the next civil day.
        XCTAssertEqual(AnalyticsEngine.dayString(utcTimestamp("2026-06-17 16:00:00"),
                                                 tzOffsetSeconds: 10 * 3600), "2026-06-18")
    }

    func testLocalMidnightNegativeOffset() {
        // Local midnight of 2026-06-17 in México (UTC−6) is 2026-06-17 06:00:00 UTC.
        let ts = utcTimestamp("2026-06-18 01:30:00")   // evening of the 17th, local MX
        let mid = AnalyticsEngine.localMidnight(ts, tzOffsetSeconds: -6 * 3600)
        XCTAssertEqual(mid, utcTimestamp("2026-06-17 06:00:00"))
        // It floors to local midnight: the instant maps to the 17th, one second earlier to the 16th.
        XCTAssertEqual(AnalyticsEngine.dayString(mid, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        XCTAssertEqual(AnalyticsEngine.dayString(mid - 1, tzOffsetSeconds: -6 * 3600), "2026-06-16")
        // Default offset 0 floors to UTC midnight — unchanged behaviour for pure callers.
        XCTAssertEqual(AnalyticsEngine.localMidnight(ts), utcTimestamp("2026-06-18 00:00:00"))
    }

    func testFutureLocalDaysToPruneSelectsOnlyFutureUnwrittenRows() {
        let today = "2026-06-17"
        let written: Set<String> = ["2026-06-15", "2026-06-16", "2026-06-17"]   // re-grouped local days
        // (a) The future-in-local phantom row (the 18th) IS selected for prune…
        let stored = ["2026-06-15", "2026-06-16", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: stored, today: today, written: written),
                       ["2026-06-18"])
        // (b) …a today/past row is never selected — even a PAST day NOT in `written` (raw pruned, not
        // recomputable) is kept: no data loss. Only the future row is pruned.
        let withUnrecomputedPast = ["2026-04-01", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: withUnrecomputedPast, today: today,
                                                              written: written), ["2026-06-18"])
        // (c) A future row that WAS written this run is not pruned (defensive belt-and-suspenders).
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: ["2026-06-18"], today: today,
                                                              written: ["2026-06-18"]), [])
    }

    // MARK: - The stage codec

    func testStagesRoundTrip() {
        let stages = [StageSegment(start: 100, end: 200, stage: "light"),
                      StageSegment(start: 200, end: 260, stage: "deep"),
                      StageSegment(start: 260, end: 300, stage: "rem"),
                      StageSegment(start: 300, end: 320, stage: "wake")]
        let json = AnalyticsEngine.encodeStages(stages)
        XCTAssertNotNil(json)
        XCTAssertEqual(AnalyticsEngine.decodeStages(json), stages)
    }

    /// The stored shape is an ARRAY of three-key objects. This is what every independent reader —
    /// the importer, which re-declares the type by hand, and the screen, which parses the text
    /// without the type at all — is written against.
    func testEncodedShapeIsAnArrayOfThreeKeyedSegments() throws {
        let json = try XCTUnwrap(AnalyticsEngine.encodeStages(
            [StageSegment(start: 0, end: 30, stage: "deep")]))
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let array = try XCTUnwrap(parsed as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(Set(array[0].keys), ["start", "end", "stage"])
        XCTAssertEqual(array[0]["start"] as? Int, 0)
        XCTAssertEqual(array[0]["end"] as? Int, 30)
        XCTAssertEqual(array[0]["stage"] as? String, "deep")
    }

    /// The other shape living in the same column is an imported dictionary of totals with no
    /// timeline. Decoding must REFUSE it — callers depend on the `nil` to fall back to one coarse
    /// interval instead of drawing a hypnogram that does not exist.
    func testDecodeRejectsEmptyAndTheImportedDictShape() {
        XCTAssertNil(AnalyticsEngine.decodeStages(nil))
        XCTAssertNil(AnalyticsEngine.decodeStages(""))
        XCTAssertNil(AnalyticsEngine.decodeStages("{\"deep\":30}"))
        XCTAssertNil(AnalyticsEngine.decodeStages("[]"))
    }

    /// Unix-seconds for a `yyyy-MM-dd HH:mm:ss` wall-clock string interpreted in UTC.
    private func utcTimestamp(_ s: String) -> Int {
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return Int(f.date(from: s)!.timeIntervalSince1970)
    }
}
