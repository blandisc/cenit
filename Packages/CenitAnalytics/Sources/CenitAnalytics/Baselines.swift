import Foundation

// Baselines.swift — your own normal, per nightly metric, and how far tonight sits from it.
//
// Pure, deterministic, DB-free, Foundation-only. Keeps a robust CENTER and a robust SPREAD per
// metric, both weighted toward recent nights, and answers the only question the screens ask:
// "this value, against YOUR normal — near or far?" Preparación, the typical-range band, the vital
// anomaly notice and the onboarding cold start all stand on it.
//
// METHOD, and why each piece is the published one:
//
// • Centering space. Nightly RMSSD is approximately LOG-NORMAL, and the established practice is to
//   monitor lnRMSSD rather than raw ms (Plews et al. 2013, Sports Med 43(9):773-781; RMSSD itself
//   per Task Force 1996, Circulation 93(5):1043-1065). Averaging in ms biases the center UPWARD and
//   under-weights the low nights, which are exactly the ones that matter. Apple's SDNN is just as
//   right-skewed and gets the same treatment. Linear metrics (resting HR, respiration, skin temp)
//   are centered as-is.
//
// • Center update: winsorized EWMA. Tonight is CLAMPED to ±`winsorK` dispersions of the current
//   center before it is folded in — bounded influence, the classic robust move (Huber 1964, Ann
//   Math Statist 35(1):73-101): an extreme night is capped, never deleted.
//
// • Spread update: EWMA of the ABSOLUTE deviation, computed from the UNCLAMPED value, so a genuine
//   regime change widens the band instead of hiding inside it.
//
// • Absolute deviation → σ. What we store is a mean absolute deviation, not a standard deviation.
//   For a normal, E|X − μ| = σ·√(2/π), so σ ≈ 1.253·spread. That bridge is an identity of the
//   method, not a tunable. (The canonical ALTERNATIVE robust estimator is the scaled MAD,
//   σ̂ = 1.4826·median|xᵢ − median(x)| — Rousseeuw & Croux 1993, JASA 88(424):1273-1283. It is NOT
//   used here: this estimator has to run one night at a time with no history retained, which the
//   MAD cannot do. The MAD shows up in the tests only as a cross-check of magnitude.)
//
// • Thin-baseline shrinkage. `confidence(nValid:)` is the weight a consumer uses to pull a z back
//   toward neutral while the base is young — empirical-Bayes / James-Stein shrinkage (Efron &
//   Morris 1977, JASA 72(360):311-319): thin evidence gets pulled to the center.
//
// APPROXIMATE by construction. Nothing here is a clinical instrument or a diagnosis.

/// How one nightly metric is bounded, floored and smoothed. Constructed per metric; the shipped set
/// lives in `Baselines.metricCfg`, and neighbours (skin-temp deviation, warming magnitude, spectral
/// band power) build their own with the same shape.
public struct MetricCfg: Equatable, Sendable {
    /// Lower physiological bound, in the metric's own units. A night outside `[minVal, maxVal]` is
    /// not folded (checked BEFORE any log transform).
    public let minVal: Double
    /// Upper physiological bound, in the metric's own units.
    public let maxVal: Double
    /// Noise floor for the dispersion, expressed in the CENTERING space — ln-units when
    /// `logDomain`, metric units otherwise.
    public let floorSpread: Double
    /// Half-life of the center, in nights: after this many nights a night's weight has halved.
    public let halfLifeB: Double
    /// Half-life of the dispersion, in nights. Deliberately slower than the center's.
    public let halfLifeS: Double
    /// Center and scale in ln(value) instead of the raw value. For right-skewed metrics (RMSSD,
    /// SDNN, spectral power) this is what makes the center a geometric mean and the band
    /// multiplicative.
    public let logDomain: Bool

    public init(minVal: Double, maxVal: Double, floorSpread: Double,
                halfLifeB: Double, halfLifeS: Double, logDomain: Bool = false) {
        self.minVal = minVal
        self.maxVal = maxVal
        self.floorSpread = floorSpread
        self.halfLifeB = halfLifeB
        self.halfLifeS = halfLifeS
        self.logDomain = logDomain
    }
}

/// How much a baseline can be trusted, by how many valid nights it has folded and how long since it
/// last saw one.
public enum BaselineStatus: String, Equatable, Sendable {
    /// Too few nights to compare against at all.
    case calibrating
    /// Enough to compare, not enough to lean on.
    case provisional
    /// Mature.
    case trusted
    /// Mature once, but it has not seen a night in too long to still describe you.
    case stale
}

/// A metric's personal baseline at one point in the night series.
public struct BaselineState: Equatable, Sendable {
    /// The center, always in DISPLAY units (ms, bpm, °C…) — de-centered for you, even in log domain.
    public let baseline: Double
    /// The internal absolute dispersion, in the CENTERING space: ln-units when `logDomain`, metric
    /// units otherwise. It is NOT a σ — multiply by 1.253 for that, which `deviation` and
    /// `normalRange` already do. The unit depends on `logDomain`, which is why the flag travels
    /// inside the state: readers never need the `MetricCfg` back.
    public let spread: Double
    /// Nights actually folded into the center.
    public let nValid: Int
    /// Nights since the last night that moved the center.
    public let nightsSinceUpdate: Int
    public let status: BaselineStatus
    /// Whether `baseline`/`spread` were computed in ln space.
    public let logDomain: Bool

    public init(baseline: Double, spread: Double, nValid: Int,
                nightsSinceUpdate: Int, status: BaselineStatus, logDomain: Bool = false) {
        self.baseline = baseline
        self.spread = spread
        self.nValid = nValid
        self.nightsSinceUpdate = nightsSinceUpdate
        self.status = status
        self.logDomain = logDomain
    }

    /// Mature enough to carry a verdict on its own.
    public var trusted: Bool { status == .trusted }
    /// Enough nights to be worth comparing against at all (`.provisional` or `.trusted`).
    public var usable: Bool { status == .provisional || status == .trusted }
}

/// One value read against one baseline.
public struct Deviation: Equatable, Sendable {
    /// Standardized distance from the center, in the centering space (ln for log metrics).
    public let z: Double
    /// Signed difference from the center, ALWAYS in display units.
    public let delta: Double
    /// Signed fractional difference from the center (`value/baseline − 1`), display units; 0 when
    /// the center is 0.
    public let ratio: Double
    /// Inside the typical range, i.e. |z| ≤ 1.
    public let inNormalRange: Bool

    public init(z: Double, delta: Double, ratio: Double, inNormalRange: Bool) {
        self.z = z
        self.delta = delta
        self.ratio = ratio
        self.inNormalRange = inNormalRange
    }
}

public enum Baselines {

    // MARK: - Method constants

    /// Winsorization width: tonight is clamped to ±3 dispersions of the center before folding
    /// (Huber 1964's bounded-influence convention).
    public static let winsorK: Double = 3.0
    /// Hard-rejection width: past ±5 dispersions a night is SEEN but not folded. Compared against
    /// `spread`, not σ — so ≈ 6.3 σ in practice. Deliberate: moving it silently changes which
    /// nights enter the baseline of every installed user.
    public static let hardOutlierK: Double = 5.0

    /// The mean-absolute-deviation → σ bridge for a normal: E|X − μ| = σ·√(2/π), so σ ≈ 1.253·MAD.
    /// An identity of the method, not a knob.
    private static let sigmaPerAbsDev: Double = 1.253

    // MARK: - Contract constants (a screen shows these, or divides by them)

    /// Valid nights before a baseline is worth comparing against. Shown to the user as the
    /// denominator of «Noche N de 4» during the cold start.
    public static let minNightsSeed: Int = 4
    /// Valid nights before a baseline is trusted. The denominator of the confidence bar.
    public static let minNightsTrust: Int = 14
    /// Nights without a reading after which a mature baseline is declared `.stale` — «tu base se
    /// quedó atrás».
    public static let staleDays: Int = 14
    /// Floor of the thin-baseline shrinkage weight. It moves displayed scores, so it is contract.
    public static let confidenceFloor: Double = 0.5

    // MARK: - Cold-start knobs (product calibration)

    /// Center half-life while the base is young. Much faster than the mature one on purpose: a
    /// badly placed seed has to converge in days, not weeks.
    public static let earlyHalfLifeB: Double = 3.0
    /// Dispersion-floor multiplier at the seed, ramping down to 1.0 at `minNightsTrust`. Keeps the
    /// band honestly wide while the dispersion estimate is still worthless.
    public static let earlySpreadInflation: Double = 1.5

    // MARK: - Per-metric configuration

    // Bounds are physiological plausibility; `floorSpread` is a noise floor; half-lives are the
    // repo convention (center 14 nights, dispersion 21 — slower on purpose).

    /// RMSSD/SDNN in ms. Log domain (Plews 2013): the floor is in ln-units, ≈ a ±10 % band.
    private static let hrvLike = MetricCfg(minVal: 5, maxVal: 250, floorSpread: 0.08,
                                           halfLifeB: 14, halfLifeS: 21, logDomain: true)
    /// Resting heart rate, bpm.
    private static let restingHR = MetricCfg(minVal: 30, maxVal: 120, floorSpread: 2.0,
                                             halfLifeB: 14, halfLifeS: 21)
    /// Respiration rate, breaths per minute.
    private static let respiration = MetricCfg(minVal: 4, maxVal: 40, floorSpread: 0.5,
                                               halfLifeB: 14, halfLifeS: 21)
    /// Wrist skin temperature, ABSOLUTE °C (the deviation-semantics config lives in `VitalBands`).
    private static let skinTemp = MetricCfg(minVal: 20, maxVal: 42, floorSpread: 0.3,
                                            halfLifeB: 14, halfLifeS: 21)
    /// Sleep efficiency as a FRACTION, never a percentage — `CenitImport` depends on this scale to
    /// avoid the 100× import error.
    private static let efficiency = MetricCfg(minVal: 0.2, maxVal: 1.0, floorSpread: 0.03,
                                              halfLifeB: 14, halfLifeS: 21)
    /// Sleeping-HR delta (bpm) between the first and last third of the night. The ONLY metric that
    /// can be negative, so it is never logarithmic. Bounds and floor are product calibration, not
    /// validated physiology.
    private static let nightThirdsDelta = MetricCfg(minVal: -30, maxVal: 30, floorSpread: 2.5,
                                                    halfLifeB: 14, halfLifeS: 21)

    /// The shipped configs, keyed by metric. Exactly seven keys — callers index them directly.
    ///
    /// `"sdnn"` is byte-identical to `"hrv"` but keeps its OWN key on purpose: Apple's SDNN and
    /// nocturnal RMSSD are different measurements and must never share one baseline, so retuning
    /// one can never move the other.
    public static let metricCfg: [String: MetricCfg] = [
        "hrv": hrvLike,
        "sdnn": hrvLike,
        "resting_hr": restingHR,
        "resp": respiration,
        "skin_temp": skinTemp,
        "efficiency": efficiency,
        "night_thirds_delta": nightThirdsDelta,
    ]

    public static var hrvCfg: MetricCfg { hrvLike }
    public static var restingHRCfg: MetricCfg { restingHR }
    public static var respCfg: MetricCfg { respiration }

    // MARK: - Shrinkage weight

    /// How much of a z a consumer should keep, given how many valid nights the baseline folded.
    /// `confidenceFloor` at or below the seed, 1.0 at or above trust, linear in between. Empirical
    /// Bayes: thin evidence is pulled toward the center rather than believed (Efron & Morris 1977).
    public static func confidence(nValid: Int) -> Double {
        confidenceFloor + (1.0 - confidenceFloor) * maturityRamp(nValid)
    }

    // MARK: - One night

    /// Fold one night into a baseline and return the new state. `nil` state seeds it; `nil` or
    /// out-of-bounds value holds it. Deterministic, no I/O, no clock.
    ///
    /// Order of evaluation (each rule shadows the ones after it):
    /// 1. No prior state → seed.
    /// 2. Missing value → skip and hold (`nightsSinceUpdate` advances, nothing else moves).
    /// 3. Outside `[cfg.minVal, cfg.maxVal]` → same as 2, checked in the metric's own units.
    /// 4. Past `hardOutlierK` dispersions AND the base is already mature → the night is SEEN
    ///    (`nightsSinceUpdate` resets) but not folded. While the base is young this gate is
    ///    SUSPENDED: otherwise a high seed would reject exactly the genuine low nights that ought
    ///    to correct it, and the center would sit wrong for weeks.
    /// 5. First real value after a midpoint seed → treat as a clean first night.
    /// 6. Otherwise → winsorized EWMA of the center, EWMA of the absolute deviation for the spread.
    ///
    /// While the base is young (`nValid < minNightsTrust`) the center uses `earlyHalfLifeB`, the
    /// hard gate is off, and the dispersion floor is inflated. At and above `minNightsTrust` all
    /// three revert exactly — the mature path is bit-identical to a model with no young branch.
    public static func update(_ state: BaselineState?, value: Double?, cfg: MetricCfg) -> BaselineState {
        let inBounds = value.map { $0 >= cfg.minVal && $0 <= cfg.maxVal } ?? false

        guard let prior = state else {
            // 1. Seed. A usable first night anchors the center; anything else parks it at the
            // midpoint of the physiological range with nothing folded yet.
            guard let v = value, inBounds else {
                return settled(baseline: (cfg.minVal + cfg.maxVal) / 2, spread: cfg.floorSpread,
                               nValid: 0, nightsSinceUpdate: 1, logDomain: cfg.logDomain)
            }
            return settled(baseline: v, spread: cfg.floorSpread, nValid: 1,
                           nightsSinceUpdate: 0, logDomain: cfg.logDomain)
        }

        // 2 & 3. Nothing usable tonight: hold everything, only the gap grows.
        guard let v = value, inBounds else { return holding(prior, nightsSinceUpdate: prior.nightsSinceUpdate + 1) }

        let young = prior.nValid < minNightsTrust
        let c = centered(v, logDomain: cfg.logDomain)
        let b = centered(prior.baseline, logDomain: cfg.logDomain)

        // 4. Hard outlier, mature bases only.
        if !young, abs(c - b) > hardOutlierK * prior.spread {
            return holding(prior, nightsSinceUpdate: 0)
        }

        // 5. First real value after a midpoint seed: anchor rather than drag the midpoint.
        if prior.nValid == 0 {
            return settled(baseline: v, spread: cfg.floorSpread, nValid: 1,
                           nightsSinceUpdate: 0, logDomain: cfg.logDomain)
        }

        // 6. Winsorize, then fold.
        let reach = winsorK * prior.spread
        let clamped = min(b + reach, max(b - reach, c))
        let lambdaB = decayFactor(halfLife: young ? earlyHalfLifeB : cfg.halfLifeB)
        let center = lambdaB * clamped + (1 - lambdaB) * b

        // The spread reads the UNCLAMPED night, so a real shift widens the band instead of hiding.
        let lambdaS = decayFactor(halfLife: cfg.halfLifeS)
        let raw = lambdaS * abs(c - center) + (1 - lambdaS) * prior.spread
        let spread = max(dispersionFloor(cfg, nValid: prior.nValid), raw)

        return settled(baseline: decentered(center, logDomain: cfg.logDomain), spread: spread,
                       nValid: prior.nValid + 1, nightsSinceUpdate: 0, logDomain: cfg.logDomain)
    }

    // MARK: - Whole series

    /// Fold a night series (oldest first) into one baseline. `nil` entries are missing nights and
    /// advance the staleness gap without moving the center.
    public static func foldHistory(_ values: [Double?], cfg: MetricCfg) -> BaselineState {
        var state: BaselineState?
        for v in values { state = update(state, value: v, cfg: cfg) }
        return state ?? seed(cfg)
    }

    /// Fold a dated night series, dropping every night strictly before `epoch` first. This is the
    /// re-anchor behind "recalibrate": nights before the epoch never touch the new baseline.
    ///
    /// The comparison is a plain lexicographic one on the `"yyyy-MM-dd"` key — that ordering is
    /// order-preserving for this format, so no date parsing, locale or time zone is involved.
    /// Input must be oldest-first. `epoch == nil` cuts nothing.
    public static func foldHistory(_ values: [(day: String, value: Double?)],
                                   epoch: String?, cfg: MetricCfg) -> BaselineState {
        let kept = epoch.map { e in values.filter { $0.day >= e } } ?? values
        return foldHistory(kept.map(\.value), cfg: cfg)
    }

    /// The PRIOR baseline for every night, in one forward pass: element `i` is the state folded
    /// over the strict prefix `values[0..<i]` — the base night `i` should be judged against,
    /// without judging itself. Element 0 is the empty seed, and the array has exactly
    /// `values.count` elements.
    ///
    /// Identical, value for value, to calling `foldHistory` on each prefix; only the cost differs
    /// (O(n) instead of O(n²)).
    public static func prefixStates(_ values: [Double?], cfg: MetricCfg) -> [BaselineState] {
        var out: [BaselineState] = []
        out.reserveCapacity(values.count)
        var running: BaselineState?
        for v in values {
            out.append(running ?? seed(cfg))
            running = update(running, value: v, cfg: cfg)
        }
        return out
    }

    /// The plain, auditable path: mean and sample SD over the trailing `window` valid nights, with
    /// no recency weighting at all. Used where a screen wants a band it can explain in one line.
    ///
    /// Everything is computed in the centering space, so for a log metric `baseline` is the
    /// GEOMETRIC mean — the right center for a log-symmetric series (the arithmetic mean sits
    /// above it). The SD is divided by the σ bridge BEFORE the floor is applied, which puts the
    /// result in the same internal space as the incremental path so the two agree exactly at the
    /// floor. With a single night there is no dispersion to estimate, so the floor stands alone.
    public static func rollingMeanSD(_ values: [Double?], cfg: MetricCfg, window: Int = 30) -> BaselineState {
        let valid = values.compactMap { $0 }.filter { $0 >= cfg.minVal && $0 <= cfg.maxVal }
        let tail = window > 0 ? Array(valid.suffix(window)) : []
        let n = tail.count
        guard n > 0 else { return seed(cfg) }

        let points = tail.map { centered($0, logDomain: cfg.logDomain) }
        let mean = points.reduce(0, +) / Double(n)
        let sd: Double
        if n >= 2 {
            let ss = points.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            sd = (ss / Double(n - 1)).squareRoot()
        } else {
            sd = cfg.floorSpread * sigmaPerAbsDev
        }
        return settled(baseline: decentered(mean, logDomain: cfg.logDomain),
                       spread: max(cfg.floorSpread, sd / sigmaPerAbsDev),
                       nValid: n, nightsSinceUpdate: 0, logDomain: cfg.logDomain)
    }

    // MARK: - Reading a value against a baseline

    /// How far `value` sits from `state`. `z` is standardized in the centering space (ln for a log
    /// metric); `delta` and `ratio` stay in display units, because that is what the screens print.
    public static func deviation(_ value: Double, state: BaselineState) -> Deviation {
        let sigma = max(sigmaPerAbsDev * state.spread, 1e-9)
        let z = (centered(value, logDomain: state.logDomain)
                 - centered(state.baseline, logDomain: state.logDomain)) / sigma
        let ratio = state.baseline == 0 ? 0 : value / state.baseline - 1
        return Deviation(z: z, delta: value - state.baseline, ratio: ratio,
                         inNormalRange: abs(z) <= 1)
    }

    /// The TYPICAL RANGE band: ±k·σ around the center, returned in display units.
    ///
    /// For a log metric the band is MULTIPLICATIVE — exp(ln b ± k·σ_ln) — so it stays positive and
    /// asymmetric in ms, which is the correct shape for a log-normal. That is exactly why it lives
    /// here and not in a view: `baseline ± 1.253·spread` is simply wrong in log space, and a screen
    /// must never re-derive it by hand.
    ///
    /// This is the person's typical range. It is NOT a smallest-worthwhile-change (SWC), and no
    /// copy may call it one or present leaving it as a clinical event.
    public static func normalRange(_ state: BaselineState, k: Double = 1.0) -> ClosedRange<Double> {
        let center = centered(state.baseline, logDomain: state.logDomain)
        let half = k * sigmaPerAbsDev * state.spread
        let a = decentered(center - half, logDomain: state.logDomain)
        let b = decentered(center + half, logDomain: state.logDomain)
        return Swift.min(a, b)...Swift.max(a, b)
    }

    // MARK: - Internals

    /// ln(v) for log metrics, v otherwise.
    private static func centered(_ v: Double, logDomain: Bool) -> Double {
        logDomain ? Foundation.log(v) : v
    }

    /// The inverse of `centered`.
    private static func decentered(_ c: Double, logDomain: Bool) -> Double {
        logDomain ? Foundation.exp(c) : c
    }

    /// EWMA weight for a half-life of `h` nights: λ = 1 − 0.5^(1/h), so after `h` steps a night's
    /// weight has halved.
    private static func decayFactor(halfLife: Double) -> Double {
        1 - Foundation.pow(0.5, 1 / halfLife)
    }

    /// Where `nValid` sits on the seed → trust ramp, clamped to [0, 1]. Shared by the shrinkage
    /// weight and the cold-start dispersion inflation so the two ramps can never drift apart.
    private static func maturityRamp(_ nValid: Int) -> Double {
        let span = Double(minNightsTrust - minNightsSeed)
        guard span > 0 else { return nValid >= minNightsTrust ? 1 : 0 }
        return Swift.min(1, Swift.max(0, Double(nValid - minNightsSeed) / span))
    }

    /// The dispersion floor for a base that has folded `nValid` nights: inflated at the seed,
    /// ramping down to exactly `cfg.floorSpread` at `minNightsTrust`.
    private static func dispersionFloor(_ cfg: MetricCfg, nValid: Int) -> Double {
        let inflation = earlySpreadInflation + (1 - earlySpreadInflation) * maturityRamp(nValid)
        return cfg.floorSpread * inflation
    }

    /// Lifecycle label, in this order: gone stale (mature but unseen too long) → calibrating →
    /// provisional → trusted.
    private static func lifecycle(nValid: Int, nightsSinceUpdate: Int) -> BaselineStatus {
        if nightsSinceUpdate > staleDays && nValid >= minNightsSeed { return .stale }
        if nValid < minNightsSeed { return .calibrating }
        if nValid < minNightsTrust { return .provisional }
        return .trusted
    }

    /// A state with its lifecycle label derived rather than passed in — the only way one is built.
    private static func settled(baseline: Double, spread: Double, nValid: Int,
                                nightsSinceUpdate: Int, logDomain: Bool) -> BaselineState {
        BaselineState(baseline: baseline, spread: spread, nValid: nValid,
                      nightsSinceUpdate: nightsSinceUpdate,
                      status: lifecycle(nValid: nValid, nightsSinceUpdate: nightsSinceUpdate),
                      logDomain: logDomain)
    }

    /// Everything held, only the gap moves.
    private static func holding(_ prior: BaselineState, nightsSinceUpdate: Int) -> BaselineState {
        settled(baseline: prior.baseline, spread: prior.spread, nValid: prior.nValid,
                nightsSinceUpdate: nightsSinceUpdate, logDomain: prior.logDomain)
    }

    /// The state of a baseline that has seen nothing at all: parked at the midpoint of the
    /// physiological range with nothing folded.
    private static func seed(_ cfg: MetricCfg) -> BaselineState {
        settled(baseline: (cfg.minVal + cfg.maxVal) / 2, spread: cfg.floorSpread,
                nValid: 0, nightsSinceUpdate: 0, logDomain: cfg.logDomain)
    }
}
