import Foundation

// BehaviorInsights.swift — "does this move the needle for me?"
//
// Pure, deterministic, DB-free, Foundation-only. Splits the days into the ones the user logged a
// behavior and the ones they did not, then contrasts an outcome (recovery, HRV, sleep…) across the
// two. It feeds the insight engine, the stress-pattern surfaces and the experiment verdict.
//
// METHOD:
// • Effect size: Cohen's d on the POOLED SD, sp = √(((n₁−1)v₁ + (n₂−1)v₂)/(n₁+n₂−2)), d = (m₁−m₂)/sp
//   (Cohen 1988, Statistical Power Analysis for the Behavioral Sciences, 2nd ed.). Zero when there
//   is no pooled dispersion to scale by.
// • Contrast: Welch's unequal-variance t (Welch 1947, Biometrika 34(1/2):28-35), with the
//   Welch-Satterthwaite degrees of freedom (Satterthwaite 1946, Biometrics Bulletin 2(6):110). The
//   tail is Student's EXACT tail at that fractional df — a normal approximation would understate p
//   in small samples, which is the only regime this engine ever runs in.
// • Multiplicity: ranking K behaviors against one outcome is K simultaneous tests, and at α = 0.05
//   a handful come out "significant" by chance alone. So the ranking rescales every p into a
//   Benjamini-Hochberg q (1995, JRSS B 57(1):289-300), which bounds the EXPECTED proportion of
//   false discoveries among the calls, and judges on the q.
//
// ASSOCIATION, NOT CAUSE. The exposure is self-assigned, never randomised, and it is within one
// person. No copy derived from this may say "effect" or "cause" without the association hedge.

/// One behavior contrasted against one outcome.
public struct BehaviorEffect: Equatable, Sendable {
    public let behavior: String
    public let outcome: String
    public let meanWith: Double
    public let meanWithout: Double
    /// `meanWith − meanWithout`.
    public let delta: Double
    /// `delta` as a percentage of |meanWithout|; `nil` when `meanWithout` is 0.
    public let pctChange: Double?
    public let nWith: Int
    public let nWithout: Int
    /// Cohen's d, pooled, signed — same sign as `delta`.
    public let cohensD: Double
    /// Two-sided Welch p. The tail is exact (the name is historical).
    public let pApprox: Double
    /// Whether this call survives its significance gate. From `effect` it is a SINGLE-TEST verdict
    /// that ignores multiplicity and must not be shown; `rank` overwrites it with the FDR-corrected
    /// one, which is the one a surface may use.
    public let significant: Bool

    public init(behavior: String, outcome: String, meanWith: Double, meanWithout: Double,
                delta: Double, pctChange: Double?, nWith: Int, nWithout: Int,
                cohensD: Double, pApprox: Double, significant: Bool) {
        self.behavior = behavior; self.outcome = outcome
        self.meanWith = meanWith; self.meanWithout = meanWithout
        self.delta = delta; self.pctChange = pctChange
        self.nWith = nWith; self.nWithout = nWithout
        self.cohensD = cohensD; self.pApprox = pApprox
        self.significant = significant
    }
}

public enum BehaviorInsights {

    // MARK: - Constants

    /// Minimum days on EACH side before a contrast may be called significant. Five, because 5 vs 5
    /// is the smallest balanced design where an exact rank test can still cross α = 0.05 with some
    /// overlap (minimum p = 2/252 ≈ 0.008); at 4 vs 4 only perfect separation classifies at all.
    /// Reused across the repo as the one sample floor — the experiment verdict's per-arm minimum,
    /// the insight engine's group floor and the stress time-of-day floor all read it.
    public static let minGroupForSignificance: Int = 5

    /// Significance level, for the single test and for the FDR. The insight engine keeps its own
    /// copy in parallel; the two must agree.
    public static let alpha: Double = 0.05

    // MARK: - One behavior

    /// Contrast `outcome` on the days `behavior` was logged against the days it was not.
    ///
    /// `eligibleDays` is the universe the question is even asked over. Without it (the default)
    /// every day carrying an outcome is eligible — the right reading for "alcohol", where not
    /// logging it means "I didn't drink". WITH it — diet adherence, say — a day with no entry is
    /// UNKNOWN, not "without", and counting it as "without" would contaminate the contrast; such
    /// days join neither group. Days in `behaviorDays` with no outcome simply do not appear.
    ///
    /// `nil` unless BOTH groups hold at least one value and their sizes sum to at least 3 — below
    /// that there is no variance to estimate.
    public static func effect(behaviorDays: Set<String>, outcomeByDay: [String: Double],
                              behavior: String, outcome: String,
                              eligibleDays: Set<String>? = nil) -> BehaviorEffect? {
        var withValues: [Double] = []
        var withoutValues: [Double] = []
        for (day, value) in outcomeByDay {
            if let eligible = eligibleDays, !eligible.contains(day) { continue }
            if behaviorDays.contains(day) {
                withValues.append(value)
            } else {
                withoutValues.append(value)
            }
        }

        let n1 = withValues.count, n2 = withoutValues.count
        guard n1 > 0, n2 > 0, n1 + n2 >= 3 else { return nil }

        let m1 = withValues.reduce(0, +) / Double(n1)
        let m2 = withoutValues.reduce(0, +) / Double(n2)
        let v1 = sampleVariance(withValues, mean: m1)
        let v2 = sampleVariance(withoutValues, mean: m2)
        let delta = m1 - m2

        let p = welchTwoSided(m1: m1, v1: v1, n1: n1, m2: m2, v2: v2, n2: n2)
        return BehaviorEffect(behavior: behavior,
                              outcome: outcome,
                              meanWith: m1,
                              meanWithout: m2,
                              delta: delta,
                              pctChange: m2 == 0 ? nil : delta / abs(m2) * 100,
                              nWith: n1,
                              nWithout: n2,
                              cohensD: pooledCohensD(delta: delta, n1: n1, v1: v1, n2: n2, v2: v2),
                              pApprox: p,
                              significant: passes(p: p, n1: n1, n2: n2))
    }

    // MARK: - Many behaviors at once

    /// Every behavior contrasted against the same outcome, ranked, with the family-wide false
    /// discovery rate controlled.
    ///
    /// Behaviors with no computable effect are dropped silently (one logged every single day has no
    /// "without" group). The surviving p-values go through Benjamini-Hochberg together, and each
    /// `significant` is REPLACED by the q-based verdict — so the very same raw p can be significant
    /// alone and not significant inside a family of ten. Ordered: significant first, then by |d|
    /// descending, then by behavior name ascending so ties are stable.
    public static func rank(behaviors: [String: Set<String>], outcomeByDay: [String: Double],
                            outcome: String) -> [BehaviorEffect] {
        let effects = behaviors.keys.sorted().compactMap {
            effect(behaviorDays: behaviors[$0] ?? [], outcomeByDay: outcomeByDay,
                   behavior: $0, outcome: outcome)
        }
        guard !effects.isEmpty else { return [] }

        let qValues = MultipleComparisons.benjaminiHochberg(effects.map(\.pApprox))
        let corrected = zip(effects, qValues).map { e, q in
            BehaviorEffect(behavior: e.behavior, outcome: e.outcome,
                           meanWith: e.meanWith, meanWithout: e.meanWithout,
                           delta: e.delta, pctChange: e.pctChange,
                           nWith: e.nWith, nWithout: e.nWithout,
                           cohensD: e.cohensD, pApprox: e.pApprox,
                           significant: passes(p: q, n1: e.nWith, n2: e.nWithout))
        }
        return corrected.sorted {
            if $0.significant != $1.significant { return $0.significant }
            if abs($0.cohensD) != abs($1.cohensD) { return abs($0.cohensD) > abs($1.cohensD) }
            return $0.behavior < $1.behavior
        }
    }

    // MARK: - Internals

    /// Sample variance, ddof = 1; 0 below two values.
    private static func sampleVariance(_ values: [Double], mean: Double) -> Double {
        guard values.count >= 2 else { return 0 }
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    }

    /// Cohen's d on the pooled SD; 0 when there is nothing to pool or nothing to scale by.
    private static func pooledCohensD(delta: Double, n1: Int, v1: Double, n2: Int, v2: Double) -> Double {
        let df = Double(n1 + n2 - 2)
        guard df > 0 else { return 0 }
        let pooled = (Double(n1 - 1) * v1 + Double(n2 - 1) * v2) / df
        guard pooled > 0 else { return 0 }
        return delta / pooled.squareRoot()
    }

    /// Welch's two-sided p. A group of one contributes no variance term, so the other fixes the df.
    /// With no dispersion anywhere the test cannot separate: identical means give 1, different
    /// means give 0.
    private static func welchTwoSided(m1: Double, v1: Double, n1: Int,
                                      m2: Double, v2: Double, n2: Int) -> Double {
        let se1 = v1 / Double(n1)
        let se2 = v2 / Double(n2)
        let s = se1 + se2
        guard s > 0 else { return m1 == m2 ? 1.0 : 0.0 }

        let t = (m1 - m2) / s.squareRoot()
        let dfDenominator = (n1 > 1 ? se1 * se1 / Double(n1 - 1) : 0)
                          + (n2 > 1 ? se2 * se2 / Double(n2 - 1) : 0)
        guard dfDenominator > 0 else { return m1 == m2 ? 1.0 : 0.0 }
        return CorrelationEngine.studentTTwoSided(t: t, df: s * s / dfDenominator)
    }

    /// The gate: small enough p (raw for a lone test, q inside a family) AND enough days on the
    /// thinner side.
    private static func passes(p: Double, n1: Int, n2: Int) -> Bool {
        p < alpha && min(n1, n2) >= minGroupForSignificance
    }
}
