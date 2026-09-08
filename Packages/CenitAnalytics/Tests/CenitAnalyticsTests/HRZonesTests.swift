import XCTest
import BiometricStreams
@testable import CenitAnalytics

/// Zones and time in zone, checked against the published method rather than against a previous run:
/// Tanaka, Monahan & Seals (2001) for the maximum, and the conventional 50/60/70/80/90/100 %HRmax
/// cut-points the app publishes on its own method sheet.
final class HRZonesTests: XCTestCase {

    // MARK: - Maximum heart rate

    func testTanakaMaxHR() {
        XCTAssertEqual(HRZones.tanakaMaxHR(age: 30), 187.0, accuracy: 1e-9)   // 208 − 21
        XCTAssertEqual(HRZones.tanakaMaxHR(age: 40), 180.0, accuracy: 1e-9)   // 208 − 28
    }

    /// Deliberately NOT rounded: a fractional maximum moves every zone edge by a fraction of a beat,
    /// and rounding here would quietly shift all five.
    func testTanakaMaxHRKeepsItsFraction() {
        XCTAssertEqual(HRZones.tanakaMaxHR(age: 33), 184.9, accuracy: 1e-9)   // 208 − 23.1
    }

    // MARK: - Building the zones

    func testZonesFromAgeAreLabelledAsEstimated() {
        let z = HRZones.zones(age: 30)
        XCTAssertEqual(z.source, "tanaka")
        XCTAssertEqual(z.maxHR, 187.0, accuracy: 1e-9)
        XCTAssertEqual(z.zones.count, 5)
        XCTAssertEqual(z.zones[0].lower, 93.5, accuracy: 1e-9)    // 0.50 × 187
        XCTAssertEqual(z.zones[4].upper, 187.0, accuracy: 1e-9)   // 1.00 × 187
    }

    /// A measured maximum always beats a population regression, and the age is then ignored.
    func testMeasuredMaximumOverridesAge() {
        let z = HRZones.zones(age: 30, maxHROverride: 200)
        XCTAssertEqual(z.source, "manual")
        XCTAssertEqual(z.maxHR, 200.0, accuracy: 1e-9)
        XCTAssertEqual(z.zones[0].lower, 100.0, accuracy: 1e-9)
    }

    /// The five zones tile their range with no gap and no overlap: each zone's top IS the next
    /// zone's bottom, so no beat can be counted twice or fall between two zones.
    func testZonesArePartitionedContiguously() {
        let z = HRZones.zones(maxHR: 200)
        XCTAssertEqual(z.zones.map(\.lower), [100, 120, 140, 160, 180])
        XCTAssertEqual(z.zones.map(\.upper), [120, 140, 160, 180, 200])
        for i in 0..<4 {
            XCTAssertEqual(z.zones[i].upper, z.zones[i + 1].lower, accuracy: 1e-12)
        }
    }

    /// Zones 1–4 are half-open, so a reading exactly on a boundary belongs to the higher zone.
    /// Zone 5 is open ABOVE — the estimated maximum itself, and anything past it, is zone 5. A real
    /// maximal effort beats an age estimate routinely, and answering «no zone» there would be a lie.
    func testZoneMembershipIsHalfOpenAndZoneFiveIsOpenAbove() {
        let z = HRZones.zones(maxHR: 200)
        let probes: [(Double, Int)] = [(90, 0), (100, 1), (119, 1), (120, 2),
                                       (150, 3), (170, 4), (185, 5), (200, 5), (250, 5)]
        for (bpm, expected) in probes {
            XCTAssertEqual(z.zoneNumber(forBPM: bpm), expected, "bpm \(bpm)")
        }
    }

    // MARK: - Median spacing

    /// An even count averages the two middle gaps — the true median, not the upper of the pair.
    func testMedianIntervalAveragesTheTwoMiddleGaps() {
        let hr = [0, 2, 6, 12, 22].map { HRSample(ts: $0, bpm: 100) }
        XCTAssertEqual(HRZones.medianInterval(hr), 5.0, accuracy: 1e-9)   // gaps 2,4,6,10 → (4+6)/2
    }

    func testMedianIntervalOddCountTakesTheMiddleGap() {
        let hr = [0, 2, 6, 12].map { HRSample(ts: $0, bpm: 100) }
        XCTAssertEqual(HRZones.medianInterval(hr), 4.0, accuracy: 1e-9)   // gaps 2,4,6
    }

    func testMedianIntervalFallsBackToOneSecond() {
        XCTAssertEqual(HRZones.medianInterval([]), 1.0, accuracy: 1e-9)
        XCTAssertEqual(HRZones.medianInterval([HRSample(ts: 0, bpm: 100)]), 1.0, accuracy: 1e-9)
        // Only out-of-window gaps: nothing usable, so the fallback stands.
        let far = [0, 1000, 2000].map { HRSample(ts: $0, bpm: 100) }
        XCTAssertEqual(HRZones.medianInterval(far), 1.0, accuracy: 1e-9)
    }

    // MARK: - Time in zone

    /// «Hold until the next reading»: every sample is credited with the time until the next, and the
    /// last with the median spacing, so the whole series is accounted for.
    func testTimeInZoneCreditsEverySampleIncludingTheLast() {
        let z = HRZones.zones(maxHR: 200)
        let hr = [HRSample(ts: 0, bpm: 110), HRSample(ts: 1, bpm: 110), HRSample(ts: 2, bpm: 110),
                  HRSample(ts: 3, bpm: 150), HRSample(ts: 4, bpm: 150),
                  HRSample(ts: 5, bpm: 90)]
        let tiz = HRZones.timeInZone(hr, zoneSet: z)
        XCTAssertEqual(tiz.seconds(inZone: 1), 3.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: 2), 0.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: 3), 2.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.belowZone1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.total, 6.0, accuracy: 1e-9)
    }

    /// Out-of-order input gives the same answer as ordered input.
    func testTimeInZoneSortsDefensively() {
        let z = HRZones.zones(maxHR: 200)
        let ordered = [HRSample(ts: 0, bpm: 110), HRSample(ts: 1, bpm: 110), HRSample(ts: 2, bpm: 110),
                       HRSample(ts: 3, bpm: 150), HRSample(ts: 4, bpm: 150), HRSample(ts: 5, bpm: 90)]
        let shuffled = [ordered[2], ordered[0], ordered[1]] + Array(ordered[3...])
        XCTAssertEqual(HRZones.timeInZone(shuffled, zoneSet: z),
                       HRZones.timeInZone(ordered, zoneSet: z))
    }

    func testEmptySeriesAccountsForNothing() {
        let tiz = HRZones.timeInZone([], zoneSet: HRZones.zones(maxHR: 200))
        XCTAssertEqual(tiz.total, 0.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds, [0, 0, 0, 0, 0])
    }

    /// Asking for a zone that does not exist answers zero, never an index crash.
    func testZoneLookupOutsideOneToFiveIsZero() {
        let tiz = HRZones.timeInZone([HRSample(ts: 0, bpm: 110)], zoneSet: HRZones.zones(maxHR: 200))
        XCTAssertEqual(tiz.seconds(inZone: 0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: 6), 0.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: -1), 0.0, accuracy: 1e-9)
    }
}
