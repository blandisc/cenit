import Foundation
import BiometricStreams

// RecoveryScorer.swift — resting heart rate over a night, and nothing else any more.
//
// WHAT THIS FILE IS NOW. It used to hold a composite 0–100 «recovery» score, and the three-way cuts
// that turned that score into a colour. Both are gone: the column the score was written to has been
// `nil` on every write path for a long time, nothing on screen read it, and the app's verdict comes
// from `Preparedness` instead — a per-axis consensus with no single number. With no score left to
// cut, the cuts had nothing to cut; two constants kept alive only by their own test are debt, not a
// definition. What survives is the one estimator that is defensible on its own.
//
// NO CALLER TODAY for that estimator either. It stays because this is where «resting heart rate at
// night» is written down once and tested. Before adding a caller, check `NocturnalRestingHR` first:
// that engine is the live one, and it estimates the nightly nadir with a more careful method.
//
// APPROXIMATE. Wrist optical heart rate over one night, not a clinical resting-heart-rate protocol.

public enum RecoveryScorer {

    // MARK: - Nocturnal resting heart rate

    /// Averaging window for the estimate below, in seconds. Five minutes is the conventional length
    /// for a sustained nocturnal average — long enough that a single quiet minute cannot win, short
    /// enough to sit inside one stretch of deep sleep.
    public static let restingHRWindowS: Int = 300

    /// Fewest samples a window must hold to be considered at all.
    ///
    /// RECALIBRATABLE. The criterion: enough readings to represent a SUSTAINED measurement rather than
    /// the leftovers of a sensor dropout. Without this guard, a window holding three stray beats
    /// during a gap in recording can win the minimum outright.
    public static let restingHRMinBinSamples: Int = 5

    /// Lowest average a window may have and still be believed (bpm).
    ///
    /// RECALIBRATABLE. The criterion: below the lowest resting bradycardia that is physiologically
    /// plausible, and above what is simply impossible. Without this guard, a window of artifacts
    /// manufactures a number no heart produced.
    public static let restingHRMinBpm: Double = 25.0

    /// Resting heart rate over a night, in bpm, or `nil` when the night cannot answer.
    ///
    /// The estimate is the MINIMUM OF THE WINDOW AVERAGES, over fixed non-overlapping windows walking
    /// `[start, end]` — not the lowest single beat. One low beat is noise; five minutes of low beats
    /// is rest. A window counts only if it clears both guards above.
    ///
    /// Returning `nil` is the honest answer, and deliberately preferred to a shaky one: this value
    /// feeds personal baselines downstream, and one impossible night there quietly bends weeks of
    /// comparisons. Both bounds of the window are inclusive.
    public static func restingHR(_ hr: [HRSample], start: Int, end: Int) -> Int? {
        guard end >= start else { return nil }
        let inWindow = hr.filter { $0.ts >= start && $0.ts <= end }
        guard !inWindow.isEmpty else { return nil }

        var sums: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for s in inWindow {
            let bin = (s.ts - start) / restingHRWindowS
            sums[bin, default: 0] += Double(s.bpm)
            counts[bin, default: 0] += 1
        }

        var best: Double?
        for (bin, n) in counts where n >= restingHRMinBinSamples {
            let mean = (sums[bin] ?? 0) / Double(n)
            guard mean >= restingHRMinBpm else { continue }
            if best == nil || mean < best! { best = mean }
        }
        return best.map { Int($0.rounded()) }
    }
}
