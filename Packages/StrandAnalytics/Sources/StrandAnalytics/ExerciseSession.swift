import Foundation

// ExerciseSession.swift — the shape one bout of effort takes inside this package.
//
// NO DETECTOR TODAY, on purpose. Apple Health already hands the app real workouts from the watch, and
// `AppleLoadEstimator` already turns them into the day's load. The retired on-device detector required
// an accelerometer series whose table was dropped by migration v37, so it could only ever return
// nothing. Rather than reimplement a detector that cannot run, this type stays as the agreed shape,
// and a future gap-filling detector — one that finds sustained heart-rate elevation NOT already
// covered by a workout Apple knows about — fills it in.
//
// The type survives its detector because two engines are written against it: `SessionRecoveryCost`
// prices a session from `strain` and `avgHRRPct`, and `HeartRateRecovery` measures from `end`. Those
// four fields are the live contract; the rest are carried so the shape does not have to change again
// when something does populate it.
//
// Every intensity figure here is APPROXIMATE.

/// A bout of effort: when it ran, how hard, and what it cost.
public struct ExerciseSession: Equatable, Sendable {
    /// Unix seconds.
    public let start: Int
    /// Unix seconds. `HeartRateRecovery` measures the pulse decay from here.
    public let end: Int
    /// Mean pulse over the bout (bpm).
    public let avgHR: Double
    /// Highest pulse seen (bpm).
    public let peakHR: Int
    /// The bout's 0–21 cardiovascular load, or `nil` when it could not be measured.
    ///
    /// `nil` is «not measurable», not «no effort». A bout too short or too thinly sampled to score
    /// reports `nil` here, and the consumer falls back to `avgHRRPct`; writing `0` instead would
    /// quietly enter a real zero into every load average downstream.
    public let strain: Double?
    /// Length in seconds.
    public let durationS: Double
    /// Share of the bout's readings in each Edwards zone (0–5), in percent; sums to 100.
    public let zoneTimePct: [Int: Double]
    /// Mean Karvonen reserve percentage over the bout, clamped to `[0, 100]`, or `nil`.
    public let avgHRRPct: Double?
    /// The maximum heart rate the zone arithmetic used (bpm), or `nil`.
    public let hrmax: Double?
    /// Where that maximum came from: `"caller"` | `"observed"` | `"tanaka"` | `"unknown"`.
    public let hrmaxSource: String
    public let caloriesKcal: Double?
    public let caloriesKJ: Double?

    public init(start: Int, end: Int, avgHR: Double, peakHR: Int, strain: Double?,
                durationS: Double, zoneTimePct: [Int: Double], avgHRRPct: Double?,
                hrmax: Double?, hrmaxSource: String,
                caloriesKcal: Double?, caloriesKJ: Double?) {
        self.start = start
        self.end = end
        self.avgHR = avgHR
        self.peakHR = peakHR
        self.strain = strain
        self.durationS = durationS
        self.zoneTimePct = zoneTimePct
        self.avgHRRPct = avgHRRPct
        self.hrmax = hrmax
        self.hrmaxSource = hrmaxSource
        self.caloriesKcal = caloriesKcal
        self.caloriesKJ = caloriesKJ
    }
}
