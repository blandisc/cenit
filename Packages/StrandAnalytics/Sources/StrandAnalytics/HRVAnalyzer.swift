import Foundation
import BiometricStreams

// HRVAnalyzer.swift — time-domain heart-rate variability from beat-to-beat intervals.
//
// An independent implementation of the standard. Nothing here is ported from or calibrated against
// any third-party product.
//
// METHOD — Task Force of the European Society of Cardiology and the North American Society of Pacing
// and Electrophysiology (1996), «Heart rate variability: standards of measurement, physiological
// interpretation, and clinical use», Circulation 93(5):1043-1065:
//
//     RMSSD  = √( 1/(N−1) · Σ (NN_i − NN_i−1)² )      ms
//     SDNN   = sample standard deviation of the NN     ms   (ddof = 1)
//     pNN50  = 100 × #{ |NN_i − NN_i−1| > 50 ms } / (N−1)   %
//     meanNN = arithmetic mean of the NN                ms
//
// The 50 ms in pNN50 is part of the published definition, not a knob.
//
// ARTIFACT REJECTION, and an honest statement of what it is not. RMSSD and SDNN are L2 statistics:
// one impossible beat moves them more than a hundred real ones. So intervals pass two filters first —
// a plausibility range, then a local-median rule after Malik et al. (1989), Eur Heart J
// 10(12):1060-1074, which drops a beat that departs too far from its immediate neighbours.
//
// This is NOT a classifier in the sense of Lipponen & Tarvainen (2019). It is a deterministic
// heuristic with the same intent — remove beat-to-beat jumps that no heart makes, before computing
// statistics that would be wrecked by them — and it explicitly does NOT model missed or extra beats:
// it does not reconstruct a dropped beat, and it does not split a merged one. It removes; it never
// repairs. Read every index here as approximate.

/// A beat-to-beat interval carrying its own instant.
public struct TimedNN: Equatable, Sendable {
    /// Unix seconds, FRACTIONAL on purpose.
    ///
    /// Apple's beat reader hands out sub-second instants. Truncating to whole seconds would collapse
    /// two beats less than a second apart onto the same stamp, producing `Δt = 0` and silently
    /// discarding valid pairs — and it would do so more often the faster the heart is beating, which
    /// makes it a bias, not a rounding. Keep this a `Double`.
    public let ts: Double
    public let nnMs: Double

    public init(ts: Double, nnMs: Double) {
        self.ts = ts
        self.nnMs = nnMs
    }
}

public enum HRVAnalyzer {

    // MARK: - Constants

    /// Shortest plausible interval (ms) — about 200 bpm.
    public static let rrMinMs: Double = 300
    /// Longest plausible interval (ms) — about 30 bpm. Both bounds are physiological plausibility for
    /// one beat, derived straight from `60000 / bpm`, and both are inclusive.
    public static let rrMaxMs: Double = 2000
    /// Fewest clean intervals before any index is reported.
    ///
    /// RECALIBRATABLE, and a PRODUCT floor rather than a published one: Task Force (1996) standardises
    /// on 5-minute recordings, which says nothing about a beat count. Twenty is the point below which
    /// RMSSD and SDNN stop being stable enough to show. `NocturnalHRV` cites this by name.
    public static let minBeats: Int = 20
    /// How far a beat may sit from its local median before it is treated as an artifact (fraction).
    public static let ectopicThreshold: Double = 0.20
    /// Half-width of that local window: 2 → five beats, the beat and two neighbours each side.
    public static let ectopicWindowRadius: Int = 2
    /// Largest step between two beats that is still credible as physiology rather than an artifact,
    /// as a fraction of the shorter of the two.
    ///
    /// RECALIBRATABLE. It is RELATIVE, not an absolute millisecond cap, so that a slow night with
    /// genuinely large respiratory sinus arrhythmia is not punished for being healthy; it has to
    /// reject the step a missed or extra beat produces while letting breathing modulation through.
    public static let maxSuccessiveDeltaFraction: Double = 0.20

    /// The four indices, plus how much data survived to produce them.
    public struct HRVResult: Equatable, Sendable {
        public let rmssd: Double?
        public let sdnn: Double?
        public let meanNN: Double?
        public let pnn50: Double?
        /// Intervals handed in.
        public let nInput: Int
        /// Intervals that survived cleaning.
        public let nClean: Int

        public init(rmssd: Double?, sdnn: Double?, meanNN: Double?, pnn50: Double?,
                    nInput: Int, nClean: Int) {
            self.rmssd = rmssd
            self.sdnn = sdnn
            self.meanNN = meanNN
            self.pnn50 = pnn50
            self.nInput = nInput
            self.nClean = nClean
        }
    }

    // MARK: - Primitives (no cleaning)

    /// RMSSD over the values exactly as given. `nil` with fewer than two, which is when there is no
    /// successive pair to difference.
    public static func rmssdRaw(_ nn: [Double]) -> Double? {
        guard nn.count >= 2 else { return nil }
        var sum = 0.0
        for i in 1..<nn.count {
            let d = nn[i] - nn[i - 1]
            sum += d * d
        }
        return (sum / Double(nn.count - 1)).squareRoot()
    }

    /// Sample standard deviation over the values exactly as given. `nil` with fewer than two, which is
    /// when the `n − 1` denominator has nothing to divide by.
    public static func sdnnRaw(_ nn: [Double]) -> Double? {
        guard nn.count >= 2 else { return nil }
        let mean = nn.reduce(0, +) / Double(nn.count)
        var ss = 0.0
        for v in nn {
            let d = v - mean
            ss += d * d
        }
        return (ss / Double(nn.count - 1)).squareRoot()
    }

    /// Median of a set of values; `0` when empty. Odd counts take the middle value, even counts
    /// average the two middle ones.
    ///
    /// **Package contract.** Eight engines call this by name rather than each rolling their own, so a
    /// median means one thing across the package.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    // MARK: - Cleaning

    /// Keep only physiologically plausible intervals, in order. Both bounds inclusive.
    public static func rangeFilter(_ rr: [Double]) -> [Double] {
        rr.filter { $0 >= rrMinMs && $0 <= rrMaxMs }
    }

    /// Drop beats that sit too far from their own neighbours — Malik et al. (1989), local moving
    /// median.
    ///
    /// The window is centred on the beat and EXCLUDES it, so a single wild value cannot pull the
    /// reference it is being judged against. Too few neighbours, or a non-positive median, means there
    /// is nothing to judge against and the beat is KEPT: this filter removes only what it can prove is
    /// implausible.
    public static func ectopicFilter(_ rr: [Double]) -> [Double] {
        guard rr.count > 1 else { return rr }
        var out: [Double] = []
        out.reserveCapacity(rr.count)
        for i in rr.indices {
            let lo = max(0, i - ectopicWindowRadius)
            let hi = min(rr.count - 1, i + ectopicWindowRadius)
            var neighbours: [Double] = []
            for j in lo...hi where j != i { neighbours.append(rr[j]) }
            guard neighbours.count >= 2 else { out.append(rr[i]); continue }
            let med = median(neighbours)
            guard med > 0 else { out.append(rr[i]); continue }
            if abs(rr[i] - med) / med > ectopicThreshold { continue }
            out.append(rr[i])
        }
        return out
    }

    /// Both filters, in the order that matters: plausibility range first, so a wildly out-of-range
    /// value never enters a local median and drags its neighbours out with it.
    public static func cleanRR(_ rr: [Double]) -> [Double] {
        ectopicFilter(rangeFilter(rr))
    }

    // MARK: - Full analysis

    /// Clean the intervals and report the four indices, or an honest empty answer.
    ///
    /// When fewer than `minBeats` survive, every index is `nil` and `nClean` is `0` — but `nInput` is
    /// PRESERVED, so a caller can tell «nothing was recorded» from «what was recorded was unusable».
    public static func analyze(rawRR: [Double]) -> HRVResult {
        let nInput = rawRR.count
        let clean = cleanRR(rawRR)
        guard clean.count >= minBeats else {
            return HRVResult(rmssd: nil, sdnn: nil, meanNN: nil, pnn50: nil,
                             nInput: nInput, nClean: 0)
        }
        let mean = clean.reduce(0, +) / Double(clean.count)
        var over50 = 0
        for i in 1..<clean.count where abs(clean[i] - clean[i - 1]) > 50 { over50 += 1 }
        // Guarded even though `minBeats` already keeps this at 19 or more, so the formula stays safe
        // if someone recalibrates that floor downward.
        let pairs = clean.count - 1
        let pnn50 = pairs > 0 ? 100.0 * Double(over50) / Double(pairs) : nil
        return HRVResult(rmssd: rmssdRaw(clean), sdnn: sdnnRaw(clean), meanNN: mean,
                         pnn50: pnn50, nInput: nInput, nClean: clean.count)
    }

    /// The same analysis over stamped rows, restricted to a window. Bounds are inclusive; a `nil`
    /// bound means no limit on that side.
    public static func analyze(_ rr: [RRInterval], windowStart: Int? = nil,
                              windowEnd: Int? = nil) -> HRVResult {
        let inWindow = rr.filter { r in
            (windowStart.map { r.ts >= $0 } ?? true) && (windowEnd.map { r.ts <= $0 } ?? true)
        }
        return analyze(rawRR: inWindow.map { Double($0.rrMs) })
    }

    // MARK: - Segmented RMSSD

    /// RMSSD over a series that is NOT continuous — the shape a night of wrist-measured beats has.
    ///
    /// An adaptation of the Task Force (1996) definition to gapped data: a successive pair counts only
    /// when (1) the two beats are less than `gapSeconds` apart and strictly in order, (2) both are
    /// physiologically plausible, and (3) the step between them is no more than `deltaFraction` of the
    /// shorter one. The divisor is the number of VALID PAIRS, not `N − 1`.
    ///
    /// Two rules that cannot be relaxed:
    ///
    ///   • A pair that fails is DISCARDED, never BRIDGED. Removing the offending beat to pair its two
    ///     neighbours would manufacture pairs precisely on the dirtiest nights, and the density gate
    ///     built on this count would then trust its worst data most.
    ///   • Input is sorted by instant, ties broken by interval, so the answer never depends on the
    ///     order rows arrived in. A tie yields `Δt = 0` and is excluded by rule (1).
    ///
    /// Malik's local-median rule is deliberately NOT applied here: over sparse, non-contiguous beats a
    /// five-beat local median is not a trustworthy reference, and the paired step test in (3) is this
    /// path's artifact defence instead.
    public static func rmssdSegmented(_ nn: [TimedNN], gapSeconds: Int = 3,
                                      deltaFraction: Double = maxSuccessiveDeltaFraction)
        -> (rmssd: Double?, nPairs: Int) {
        guard nn.count >= 2 else { return (nil, 0) }
        let sorted = nn.sorted { $0.ts == $1.ts ? $0.nnMs < $1.nnMs : $0.ts < $1.ts }
        var sum = 0.0
        var pairs = 0
        for i in 1..<sorted.count {
            let a = sorted[i - 1], b = sorted[i]
            let dt = b.ts - a.ts
            guard dt > 0, dt < Double(gapSeconds) else { continue }
            guard a.nnMs >= rrMinMs, a.nnMs <= rrMaxMs,
                  b.nnMs >= rrMinMs, b.nnMs <= rrMaxMs else { continue }
            let d = b.nnMs - a.nnMs
            guard abs(d) <= deltaFraction * min(a.nnMs, b.nnMs) else { continue }
            sum += d * d
            pairs += 1
        }
        guard pairs > 0 else { return (nil, 0) }
        return ((sum / Double(pairs)).squareRoot(), pairs)
    }
}
