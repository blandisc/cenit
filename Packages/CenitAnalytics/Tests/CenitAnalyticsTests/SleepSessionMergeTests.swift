import XCTest
import CenitModels
@testable import CenitAnalytics

/// Pins the FER-486 sleep merge: the on-device night (imported wins over computed on the same startTs) is the base,
/// and an Apple Health session is included only when no on-device session overlaps its night — the on-device night
/// wins per night. With no Apple sessions the merge is the prior on-device-only behavior (regression zero).
final class SleepSessionMergeTests: XCTestCase {

    private func ses(_ start: Int, _ end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: "[]")
    }

    /// Regression zero: with no Apple sessions, imported wins over computed on the same startTs, sorted.
    func testStrapOnlyUnchangedWhenNoApple() {
        let r = SourceFusion.mergeSleepSessions(imported: [ses(100, 200)],
                                              computed: [ses(100, 999), ses(300, 400)],
                                              apple: [])
        XCTAssertEqual(r.map(\.startTs), [100, 300])
        XCTAssertEqual(r.first(where: { $0.startTs == 100 })?.endTs, 200)   // imported beat computed
    }

    /// The on-device night wins: an Apple session overlapping it (different startTs) is dropped.
    func testAppleDroppedWhenOverlapsStrap() {
        let r = SourceFusion.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(1100, 4900)])   // same night, later start
        XCTAssertEqual(r.map(\.startTs), [1000])                          // only the on-device session survives
    }

    /// Apple fills a night with no on-device coverage.
    func testAppleKeptWhenNoStrapOverlap() {
        let r = SourceFusion.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(90_000, 95_000)])
        XCTAssertEqual(r.map(\.startTs), [1000, 90_000])                  // on-device night + Apple-only night
    }

    /// appleHealthOnly path (on-device arrays empty by the mode gate) → only Apple sessions surface.
    func testAppleOnlyWhenStrapEmpty() {
        let r = SourceFusion.mergeSleepSessions(imported: [], computed: [], apple: [ses(90_000, 95_000)])
        XCTAssertEqual(r.map(\.startTs), [90_000])
    }

    /// Boundary: an on-device night ending exactly when the Apple session starts counts as overlap
    /// (inclusive `<=`/`>=`), so Apple is dropped — conservative, the band wins ties.
    func testTouchingBoundaryCountsAsOverlap() {
        let r = SourceFusion.mergeSleepSessions(imported: [ses(1000, 5000)],
                                              computed: [],
                                              apple: [ses(5000, 9000)])   // shares the instant 5000
        XCTAssertEqual(r.map(\.startTs), [1000])                          // tie at the boundary → Apple dropped
    }
}
