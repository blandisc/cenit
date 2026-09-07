import Foundation
import BiometricStreams

// HRZones.swift — the five heart-rate zones the app DISPLAYS, and how long you spent in each.
//
// METHOD. Two published pieces, nothing else:
//
//   • Maximum heart rate by age — Tanaka, Monahan & Seals (2001), «Age-predicted maximal heart rate
//     revisited», J Am Coll Cardiol 37(1):153-156:  HRmax = 208 − 0.7 × age.  Their regression is
//     independent of sex, and it replaces the older `220 − age` rule, which overestimates in the
//     young and underestimates in the old.
//   • Five zones as fixed percentages of that maximum (50/60/70/80/90/100 %), the conventional
//     %HRmax model. These cut-points are not a private choice: the app PUBLISHES them in its own
//     method sheet («zone 1 = 50–60 %, zone 5 = 90–100 %»), so the numbers here and the numbers on
//     that screen are one contract.
//
// WHY THIS IS NOT THE LOAD MODEL. `StrainScorer` also splits heart rate into five levels, but over
// heart-rate RESERVE (Karvonen: how far you are between rest and maximum), not over percentage of
// maximum. The two disagree on purpose. Reserve answers «how hard is this for YOUR body today»,
// which is what a load score needs; percentage-of-maximum answers «which band am I training in»,
// which is what a person reads on a screen and compares with everyone else's. Unifying them would
// silently change either the published zones or every stored load number. Keep them apart.
//
// APPROXIMATE. An age formula is a population regression with real spread between individuals; a
// measured maximum beats it every time, and `zones(maxHR:)` exists for exactly that.

/// One heart-rate zone: a bpm interval, and the fraction of maximum heart rate it came from.
public struct HRZone: Equatable, Sendable {
    /// 1…5, ascending intensity.
    public let number: Int
    /// Lower bpm bound, inclusive.
    public let lower: Double
    /// Upper bpm bound, exclusive — except in zone 5, which is open above (see `zoneNumber`).
    public let upper: Double
    /// Fraction of maximum heart rate the bounds came from.
    public let lowerPct: Double
    public let upperPct: Double

    public init(number: Int, lower: Double, upper: Double, lowerPct: Double, upperPct: Double) {
        self.number = number
        self.lower = lower
        self.upper = upper
        self.lowerPct = lowerPct
        self.upperPct = upperPct
    }
}

/// The five zones of one person, plus the maximum they were derived from.
public struct HRZoneSet: Equatable, Sendable {
    /// Exactly five, ascending, contiguous.
    public let zones: [HRZone]
    public let maxHR: Double
    /// Where `maxHR` came from: `"tanaka"` (estimated from age) or `"manual"` (given).
    public let source: String

    public init(zones: [HRZone], maxHR: Double, source: String) {
        self.zones = zones
        self.maxHR = maxHR
        self.source = source
    }

    /// The zone a pulse falls in, or `0` for «below zone 1» — which is not a zone but the absence of
    /// aerobic effort.
    ///
    /// Zones 1–4 are half-open `[lower, upper)`, so a reading sitting exactly on a boundary belongs to
    /// the higher zone and no beat is counted twice. Zone 5 is open ABOVE: anything at or over its
    /// floor is zone 5, including the estimated maximum itself and anything past it. A real maximal
    /// effort routinely beats an age estimate, and answering «no zone» to the hardest minute of
    /// someone's week would be a lie.
    public func zoneNumber(forBPM bpm: Double) -> Int {
        guard let top = zones.last else { return 0 }
        if bpm >= top.lower { return top.number }
        for z in zones where bpm >= z.lower && bpm < z.upper { return z.number }
        return 0
    }
}

/// Seconds spent in each zone over one series.
public struct TimeInZone: Equatable, Sendable {
    /// Five entries; index 0 is zone 1.
    public let seconds: [Double]
    /// Seconds under zone 1 — kept apart so the accounted time adds up to the series' span.
    public let belowZone1: Double

    public init(seconds: [Double], belowZone1: Double) {
        self.seconds = seconds
        self.belowZone1 = belowZone1
    }

    /// All accounted seconds, zones plus the time below zone 1.
    public var total: Double { seconds.reduce(0, +) + belowZone1 }

    /// Seconds in one zone; `0` for anything outside 1…5, never an index crash.
    public func seconds(inZone zone: Int) -> Double {
        guard zone >= 1, zone <= seconds.count else { return 0 }
        return seconds[zone - 1]
    }
}

public enum HRZones {

    /// Zone boundaries as fractions of maximum heart rate: six edges make five zones that tile
    /// `[0.50 × HRmax, HRmax]` with no gap and no overlap — each zone's `upper` IS the next one's
    /// `lower`. Published on the app's method sheet, so these are contract, not calibration.
    public static let zoneEdges: [Double] = [0.50, 0.60, 0.70, 0.80, 0.90, 1.00]

    /// Longest plausible spacing between two consecutive readings, in seconds. Past this, the gap is
    /// not a sampling cadence: it is an interruption in recording, and letting it into the median
    /// would drag the estimate upward and stretch every duration derived from it.
    private static let maxPlausibleGapSeconds: Double = 300

    /// Maximum heart rate predicted from age — Tanaka, Monahan & Seals (2001). Deliberately NOT
    /// rounded: the fractional bpm propagates into every zone edge, and rounding here would move the
    /// boundaries by up to half a beat.
    public static func tanakaMaxHR(age: Double) -> Double { 208.0 - 0.7 * age }

    /// Zones for someone of this age. `maxHROverride` wins outright when given — a measured maximum
    /// always beats a population regression — and the age is then ignored entirely.
    public static func zones(age: Double, maxHROverride: Double? = nil) -> HRZoneSet {
        if let m = maxHROverride { return zones(maxHR: m, source: "manual") }
        return zones(maxHR: tanakaMaxHR(age: age), source: "tanaka")
    }

    /// Zones for a known maximum heart rate.
    public static func zones(maxHR: Double, source: String = "manual") -> HRZoneSet {
        var out: [HRZone] = []
        for i in 1...5 {
            let lo = zoneEdges[i - 1], hi = zoneEdges[i]
            out.append(HRZone(number: i, lower: lo * maxHR, upper: hi * maxHR,
                              lowerPct: lo, upperPct: hi))
        }
        return HRZoneSet(zones: out, maxHR: maxHR, source: source)
    }

    /// Median spacing between consecutive readings, in seconds — the package's one answer to «how
    /// often was this series sampled».
    ///
    /// Only differences strictly inside `(0, maxPlausibleGapSeconds)` count. A zero or negative
    /// difference is a duplicate or an out-of-order row, and anything longer is a recording
    /// interruption rather than a cadence. With an even count the two middle values are AVERAGED —
    /// the true median, not the upper of the pair.
    ///
    /// Falls back to `1.0` with fewer than two readings or no usable difference, and never returns
    /// less than one second.
    ///
    /// **Package contract.** `StrainScorer` derives every sample's duration from this, and
    /// `StrainScorerIncremental` reproduces this exact order statistic from a bounded histogram in
    /// order to fold a live day without re-reading it. Change the definition and that file keeps
    /// compiling while quietly disagreeing with the batch curve, which is the worst kind of drift.
    static func medianInterval(_ sorted: [HRSample]) -> Double {
        guard sorted.count >= 2 else { return 1.0 }
        var gaps: [Double] = []
        gaps.reserveCapacity(sorted.count - 1)
        for i in 1..<sorted.count {
            let d = Double(sorted[i].ts - sorted[i - 1].ts)
            if d > 0 && d < maxPlausibleGapSeconds { gaps.append(d) }
        }
        guard !gaps.isEmpty else { return 1.0 }
        gaps.sort()
        let n = gaps.count
        let med = n % 2 == 1 ? gaps[n / 2] : (gaps[n / 2 - 1] + gaps[n / 2]) / 2.0
        return max(1.0, med)
    }

    /// How many seconds the series spent in each zone.
    ///
    /// Each reading is credited with the time until the NEXT reading — «hold until the next sample» —
    /// and the last reading is credited with the median spacing, so the series is accounted for
    /// end to end rather than losing its tail.
    ///
    /// The part that is easy to drop and must not be: every credit is CAPPED at the median spacing.
    /// Without the cap, a one-hour interruption in recording would hand a full hour to whatever zone
    /// the reading before it happened to be in.
    ///
    /// The input is sorted defensively, so an out-of-order stream gives the same answer as an ordered
    /// one. An empty series gives all zeros.
    public static func timeInZone(_ hr: [HRSample], zoneSet: HRZoneSet) -> TimeInZone {
        guard !hr.isEmpty else { return TimeInZone(seconds: [0, 0, 0, 0, 0], belowZone1: 0) }
        let sorted = hr.sorted { $0.ts < $1.ts }
        let median = medianInterval(sorted)
        var perZone = [Double](repeating: 0, count: 5)
        var below = 0.0
        for (i, s) in sorted.enumerated() {
            let dur: Double
            if i + 1 < sorted.count {
                let gap = Double(sorted[i + 1].ts - s.ts)
                dur = gap > 0 ? min(gap, median) : median
            } else {
                dur = median
            }
            let z = zoneSet.zoneNumber(forBPM: Double(s.bpm))
            if z >= 1 && z <= 5 { perZone[z - 1] += dur } else { below += dur }
        }
        return TimeInZone(seconds: perZone, belowZone1: below)
    }
}
