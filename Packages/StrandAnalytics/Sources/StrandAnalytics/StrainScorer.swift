import Foundation
import BiometricStreams

// StrainScorer.swift — how much cardiovascular work a stretch of heart rate represents, on a 0–21 scale.
//
// An independent implementation of published methods. Nothing here is copied from, tuned against, or
// meant to match any third-party product's score.
//
// THE CHAIN, and the citation behind each link:
//
//   1. HEART-RATE RESERVE — Karvonen, Kentala & Mustala (1957), Ann Med Exp Biol Fenn 35(3):307-315.
//      Intensity is measured as the fraction of the distance between rest and maximum that a beat
//      sits at, `%HRR = (HR − rest) / (max − rest)`, not as raw bpm. This is what makes one person's
//      «hard» comparable to another's.
//
//   2. TRIMP (training impulse) — the time-weighted sum of that intensity, by either of two published
//      methods:
//      • Edwards (1993), «The Heart Rate Monitor Book» — five reserve bands, weights 1…5, summed.
//        The DEFAULT, and the only one any caller uses today.
//      • Banister (1991), in Green & Hughson (eds.), «Modeling elite athletic performance» — a
//        continuous exponential weighting, with a coefficient that differs by sex.
//
//   3. LOGARITHMIC COMPRESSION to 0–21. TRIMP grows without bound and linearly with time, which makes
//      a long easy day look like a hard one. `21 · ln(TRIMP + 1) / ln(D)` compresses it so that
//      intensity, not duration, dominates the top of the scale.
//
// WHERE THE SCALE COMES FROM. `D` is DERIVED, not chosen: Edwards' ceiling is the top weight held all
// day, `5 × 1440 min = 7200`, and because the formula takes `TRIMP + 1`, `D = 7201` makes that
// ceiling land exactly on 21. The 0–21 range is published in the app's own method sheet and printed
// next to the number on screen («N of 21»), so both constants are contract, not calibration.
//
// APPROXIMATE. TRIMP is a model of internal load from heart rate alone. It knows nothing about what
// you lifted, how hot it was, or how you slept; it is not calorimetry and not a clinical measure.

public enum StrainScorer {

    // MARK: - Constants
    //
    // The three sufficiency thresholds are RECALIBRATABLE but COUPLED — see `hasEnoughData`. The two
    // max-HR estimation knobs are recalibratable with the criteria stated at `estimateHRmax`. The
    // rest are either published method or on-screen contract, and are transcribed as such.

    /// Readings that make a dense series scoreable on their own (~10 min at 1 Hz).
    public static let minReadings: Int = 600
    /// Readings that make a series scoreable when it also spans `minSpanSeconds`.
    public static let minSparseReadings: Int = 20
    /// Clock span a sparse series must cover to be scoreable.
    public static let minSpanSeconds: Int = 600
    /// Top of the published scale.
    public static let maxStrain: Double = 21.0
    /// Compression base: Edwards' all-day ceiling, `5 × 1440`, plus the 1 the formula adds.
    public static let strainDenominator: Double = 7201.0
    /// Age assumed when nothing better is known, for the last-resort maximum only.
    public static let defaultAge: Int = 30
    /// Resting heart rate assumed when the person's own is unknown (bpm). A population floor, not a
    /// measurement — ten call sites take it as their default.
    public static let defaultRestingHR: Double = 60.0
    /// Readings required before an OBSERVED maximum is trusted over the age estimate.
    public static let hrmaxMinSamples: Int = 600
    /// Percentile of the observed history taken as that maximum.
    public static let hrmaxPercentile: Double = 99.5
    /// Banister's scale factor.
    public static let banisterScale: Double = 0.64
    /// Banister's exponential coefficient, men.
    public static let banisterBMen: Double = 1.92
    /// Banister's exponential coefficient, women.
    public static let banisterBWomen: Double = 1.67

    /// Which published TRIMP formulation to integrate with.
    public enum Method: Sendable { case edwards, banister }

    /// Why a denominator fit could not be made.
    public enum StrainError: Error, Equatable, Sendable {
        /// Fewer than two pairs survived the usability filter.
        case tooFewPairs
        /// The least-squares sums are not positive, so no positive base exists.
        case degenerate
    }

    /// One point of the running strain curve.
    public struct CumulativeStrainPoint: Equatable, Sendable {
        public let date: Date
        public let strain: Double
        public init(date: Date, strain: Double) {
            self.date = date
            self.strain = strain
        }
    }

    // MARK: - Maximum heart rate

    /// Maximum heart rate predicted from age — Tanaka, Monahan & Seals (2001), J Am Coll Cardiol
    /// 37(1):153-156. Sex-independent. This is the estimator to prefer.
    public static func tanakaHRmax(age: Double) -> Double { 208.0 - 0.7 * age }

    /// The LAST-RESORT maximum, `220 − age`, used only when the caller supplied nothing at all.
    ///
    /// It is deliberately the worst estimator available: `220 − age` overestimates in the young and
    /// underestimates in the old, which is precisely why Tanaka (2001) replaced it. It survives here
    /// as an explicit floor so a scoring path can never silently divide by an undefined reserve — not
    /// because it is a good answer.
    public static func defaultMaxHR(age: Int = defaultAge) -> Int { 220 - age }

    /// Best available maximum heart rate, and the word for where it came from.
    ///
    /// With enough history, take a very high percentile of the observed beats and keep whichever is
    /// larger, that or the age estimate, labelled by the winner (`"observed"` / `"tanaka"`). Without
    /// enough history, fall back to age; without age either, answer `(0, "unknown")` and let the
    /// caller decide.
    ///
    /// Both knobs are RECALIBRATABLE. The percentile must be extreme enough to represent a near-maximal
    /// effort rather than a stray artifact (≥ 99 %), and the sample minimum must be large enough for
    /// that percentile to have support — on a short history the 99.5th percentile is just the sample
    /// maximum, which is noise wearing a statistic's clothes.
    public static func estimateHRmax(_ hrHistory: [Double], age: Double?) -> (Double, String) {
        if hrHistory.count >= hrmaxMinSamples {
            let observed = percentile(hrHistory.sorted(), hrmaxPercentile)
            let byAge = age.map { tanakaHRmax(age: $0) } ?? 0
            return observed >= byAge ? (observed, "observed") : (byAge, "tanaka")
        }
        if let age { return (tanakaHRmax(age: age), "tanaka") }
        return (0, "unknown")
    }

    // MARK: - The 0–21 scale and its inverse

    /// Compress a TRIMP into the 0–21 scale, rounded to two decimals (the precision the app shows).
    /// Non-positive work is zero, never a negative logarithm.
    ///
    /// NOT clamped at the top: a TRIMP beyond Edwards' all-day ceiling reports above 21 rather than
    /// pretending it stopped there. Callers that need a ceiling apply their own.
    public static func trimpToStrain(_ trimp: Double, denominator: Double = strainDenominator) -> Double {
        guard trimp > 0, denominator > 1 else { return 0 }
        let s = maxStrain * log(trimp + 1) / log(denominator)
        return (s * 100).rounded() / 100
    }

    /// The exact inverse: back from the 0–21 scale to TRIMP.
    ///
    /// Public on purpose, and the ONE copy of this arithmetic in the package. Two surfaces need to add
    /// loads together, and loads may only be added on the linear TRIMP axis — summing compressed
    /// scores would be adding logarithms, which multiplies rather than adds.
    ///
    /// Note the round trip is not exact in the other direction: `trimpToStrain` rounds to two
    /// decimals, so `strain → TRIMP → strain` is faithful only to about 0.2 % relative. Compare these
    /// with a RELATIVE tolerance, never `±1e-6`.
    public static func strainToTrimp(_ strain: Double, denominator: Double = strainDenominator) -> Double {
        guard strain > 0, denominator > 1 else { return 0 }
        return max(0, exp(strain * log(denominator) / maxStrain) - 1)
    }

    /// Fit the compression base from observed (TRIMP, strain) pairs: least squares through the origin
    /// in log space, `ln D = 21 · Σx² / Σ(x · strain)` with `x = ln(TRIMP + 1)`.
    ///
    /// Pairs with non-positive TRIMP or strain carry no information and are dropped. Fewer than two
    /// usable pairs throws `.tooFewPairs`; non-positive sums throw `.degenerate`.
    public static func fitStrainDenominator(_ pairs: [(trimp: Double, strain: Double)]) throws -> Double {
        let usable = pairs.filter { $0.trimp > 0 && $0.strain > 0 }
        guard usable.count >= 2 else { throw StrainError.tooFewPairs }
        var sxx = 0.0, sxy = 0.0
        for p in usable {
            let x = log(p.trimp + 1)
            sxx += x * x
            sxy += x * p.strain
        }
        guard sxx > 0, sxy > 0 else { throw StrainError.degenerate }
        return exp(maxStrain * sxx / sxy)
    }

    // MARK: - Sufficiency

    /// Whether a series carries enough heart rate to be scored at all — the SINGLE gate, shared by
    /// `strain` and `cumulativeStrain` so the curve exists exactly when the number does, and reused
    /// by the coverage and confidence engines as their absolute floor.
    ///
    /// Two ways to pass: enough readings outright, or fewer readings spread over enough clock. The
    /// second branch exists because a low-cadence source takes hours to accumulate `minReadings` and
    /// would leave a genuinely covered day unscored. It cannot manufacture load — the TRIMP still
    /// integrates only what is actually there, and a quiet day scores near zero through either branch.
    ///
    /// The three thresholds are RECALIBRATABLE TOGETHER: both branches must trust the same «amount of
    /// data», and at 1 Hz `minReadings` samples is exactly `minSpanSeconds` of clock. Move one, move
    /// the other.
    public static func hasEnoughData(_ hr: [HRSample]) -> Bool {
        if hr.count >= minReadings { return true }
        guard hr.count >= minSparseReadings else { return false }
        var lo = Int.max, hi = Int.min
        for s in hr { lo = min(lo, s.ts); hi = max(hi, s.ts) }
        return hi - lo >= minSpanSeconds
    }

    // MARK: - Scoring

    /// Cardiovascular load for a series, 0–21, or `nil` when it cannot honestly be measured — too
    /// little data, or a maximum that is not above the resting rate (no reserve to speak of).
    ///
    /// `nil` and `0` mean different things and must not be conflated: `nil` is «not measured», `0` is
    /// «no effort». A caller that turns one into the other poisons every moving average downstream.
    public static func strain(_ hr: [HRSample], maxHR: Double? = nil,
                              restingHR: Double = defaultRestingHR, method: Method = .edwards,
                              sex: String = "male",
                              denominator: Double = strainDenominator) -> Double? {
        guard let t = trimp(hr, maxHR: maxHR, restingHR: restingHR, method: method, sex: sex) else {
            return nil
        }
        return trimpToStrain(t, denominator: denominator)
    }

    /// The strain curve as it built up through the series: one point at the last reading of every
    /// `bucketSeconds` window (aligned to the epoch), plus always the last reading of the series.
    ///
    /// Four properties are the whole point of this function, and a change that breaks any of them is a
    /// defect: the running total is accumulated in ONE pass; the values never decrease and stay on the
    /// 0–21 scale; the final point equals `strain(...)` with the same arguments to the last bit — the
    /// chart and the headline number can never contradict each other on screen; and `bucketSeconds`
    /// changes only how many points come back, never where the curve ends.
    ///
    /// Empty when the same gate `strain` uses is not met, or when the bucket is not positive.
    public static func cumulativeStrain(_ hr: [HRSample], bucketSeconds: Int = 900,
                                        maxHR: Double? = nil,
                                        restingHR: Double = defaultRestingHR,
                                        method: Method = .edwards, sex: String = "male",
                                        denominator: Double = strainDenominator) -> [CumulativeStrainPoint] {
        guard bucketSeconds > 0, hasEnoughData(hr) else { return [] }
        let sorted = hr.sorted { $0.ts < $1.ts }
        let effMax = maxHR ?? Double(defaultMaxHR())
        let reserve = effMax - restingHR
        guard reserve > 0 else { return [] }

        let sampleMinutes = sampleDurationMinutes(sorted)
        let b = banisterB(sex: sex)
        var acc = 0.0
        var out: [CumulativeStrainPoint] = []
        for (i, s) in sorted.enumerated() {
            acc += contribution(Double(s.bpm), restingHR: restingHR, reserve: reserve,
                                method: method, b: b)
            let isLast = i == sorted.count - 1
            let bucketEnds = isLast
                || floorDiv(sorted[i + 1].ts, bucketSeconds) != floorDiv(s.ts, bucketSeconds)
            guard bucketEnds else { continue }
            out.append(CumulativeStrainPoint(
                date: Date(timeIntervalSince1970: TimeInterval(s.ts)),
                strain: trimpToStrain(acc * sampleMinutes, denominator: denominator)))
        }
        return out
    }

    // MARK: - Internals shared with the incremental fold
    //
    // `StrainScorerIncremental` folds a live day without re-reading it, and reproduces the arithmetic
    // below symbol by symbol. These three names and the twelve constants above are the package's most
    // rigid interface: rename or re-define one and that file either stops compiling or, worse, keeps
    // compiling while drifting away from the batch curve.

    /// Percentile of an ALREADY SORTED series, by linear interpolation between order statistics —
    /// type 7 of Hyndman & Fan (1996), «Sample quantiles in statistical packages», the definition
    /// `numpy.percentile` uses by default and the one `CenitDesign.ReferenceRange` documents. The two
    /// must agree.
    static func percentile(_ sortedValues: [Double], _ pct: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        guard sortedValues.count > 1 else { return sortedValues[0] }
        let pos = (pct / 100.0) * Double(sortedValues.count - 1)
        let i = Int(pos.rounded(.down))
        let f = pos - Double(i)
        let lo = sortedValues[max(0, min(i, sortedValues.count - 1))]
        let hi = sortedValues[max(0, min(i + 1, sortedValues.count - 1))]
        return lo + f * (hi - lo)
    }

    /// Karvonen intensity for one beat, as a percentage of heart-rate reserve, clamped to `[0, 100]`.
    /// A non-positive reserve answers `0` — a missing maximum is not a reason to divide by zero.
    static func pctHRR(_ bpm: Double, restingHR: Double, hrReserve: Double) -> Double {
        guard hrReserve > 0 else { return 0 }
        return min(100, max(0, (bpm - restingHR) / hrReserve * 100))
    }

    /// Edwards' zone weight (0…5) for one beat.
    ///
    /// Evaluated on the UNCLAMPED reserve percentage. At both ends it agrees with the clamped value
    /// (under 50 gives 0, over 100 gives 5), but the two are written out separately on purpose so the
    /// weighting stays legible instead of depending on a clamp elsewhere.
    static func zoneWeight(_ bpm: Double, restingHR: Double, hrReserve: Double) -> Int {
        guard hrReserve > 0 else { return 0 }
        let p = (bpm - restingHR) / hrReserve * 100
        if p >= 90 { return 5 }
        if p >= 80 { return 4 }
        if p >= 70 { return 3 }
        if p >= 60 { return 2 }
        if p >= 50 { return 1 }
        return 0
    }

    // MARK: - Private

    /// Total TRIMP for a series, or `nil` when it cannot be measured.
    private static func trimp(_ hr: [HRSample], maxHR: Double?, restingHR: Double,
                              method: Method, sex: String) -> Double? {
        guard hasEnoughData(hr) else { return nil }
        let sorted = hr.sorted { $0.ts < $1.ts }
        let effMax = maxHR ?? Double(defaultMaxHR())
        let reserve = effMax - restingHR
        guard reserve > 0 else { return nil }

        let b = banisterB(sex: sex)
        var acc = 0.0
        for s in sorted {
            acc += contribution(Double(s.bpm), restingHR: restingHR, reserve: reserve,
                                method: method, b: b)
        }
        return acc * sampleDurationMinutes(sorted)
    }

    /// One beat's contribution, still to be scaled by the per-sample duration.
    private static func contribution(_ bpm: Double, restingHR: Double, reserve: Double,
                                     method: Method, b: Double) -> Double {
        switch method {
        case .edwards:
            return Double(zoneWeight(bpm, restingHR: restingHR, hrReserve: reserve))
        case .banister:
            let x = pctHRR(bpm, restingHR: restingHR, hrReserve: reserve) / 100.0
            return x * banisterScale * exp(b * x)
        }
    }

    /// Minutes each reading stands for: the series' median spacing.
    ///
    /// Using the median rather than the first gap is what stops one anomalous separation at the start
    /// of a series from rescaling the load of the entire day.
    private static func sampleDurationMinutes(_ sorted: [HRSample]) -> Double {
        guard sorted.count >= 2 else { return 1.0 / 60.0 }
        return HRZones.medianInterval(sorted) / 60.0
    }

    /// Banister's exponential coefficient. Anything beginning with «f» takes the female coefficient.
    private static func banisterB(sex: String) -> Double {
        sex.lowercased().hasPrefix("f") ? banisterBWomen : banisterBMen
    }

    /// Floor division that behaves for timestamps on either side of the epoch, so bucket boundaries
    /// are evenly spaced everywhere rather than folding around zero.
    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}
