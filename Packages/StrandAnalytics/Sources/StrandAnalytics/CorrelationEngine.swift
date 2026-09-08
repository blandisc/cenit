import Foundation

// CorrelationEngine.swift — how two daily series move together.
//
// Pure, deterministic, DB-free, Foundation-only. Pearson's coefficient, the least-squares line, an
// EXACT two-sided p, an inner join of two dated series, and the same thing at a lag.
//
// METHOD:
// • Coefficient and line: r = Sxy/√(Sxx·Syy), slope = Sxy/Sxx, intercept = ȳ − slope·x̄ (Pearson
//   1896, Phil Trans R Soc A 187:253-318; OLS Legendre 1805 / Gauss 1809). `r` is clamped to
//   [−1, 1] to absorb floating-point overshoot.
// • Significance: the classic t of a correlation, t = r·√((n−2)/(1−r²)), read against Student's t
//   on df = n − 2 (Student 1908, Biometrika 6(1):1-25). The tail is the REGULARIZED INCOMPLETE
//   BETA — p = I_x(df/2, 1/2) with x = df/(df + t²), the standard t ↔ beta identity — evaluated by
//   the modified Lentz continued fraction (Lentz 1976, Applied Optics 15(3):668; the presentation
//   in Numerical Recipes §6.4), with the front factor taken through `lgamma` for stability and the
//   reflection I_x(a,b) = 1 − I_{1−x}(b,a) applied where the fraction converges slowly.
//
//   It is EXACT, not a normal approximation, and that matters: on a short series Student's tails
//   are much heavier, and the normal understates p badly (at n = 5 the normal says ≈ 0.034 where
//   the t says ≈ 0.124 — a factor of 3.66 in the user's favour, in the wrong direction).
//
// • Lagged correlation: pair x[D] with y[D + lagDays]. A positive lag asks whether today predicts
//   the day after; a negative one looks back.
//
// • Spearman's ρ (FER-438): Pearson's r on the MIDRANKS of each variable, read against the same
//   Student's t on df = n − 2 (the classic t-approximation for ρ; Zar 1972, J Am Stat Assoc
//   67(339):578-580). For a zero-inflated or heavy-tailed series (a day strain that is 0 on rest
//   days, a step count with weekend spikes), where Pearson would mostly measure the 0-vs-not
//   contrast.
// • Effective sample size (FER-438): the p above tests H0: r = 0 on observations that are NOT
//   independent, and daily series are autocorrelated, so on n raw pairs it is ANTICONSERVATIVE.
//   `effectiveN` shrinks n by Bartlett's AR(1) factor, n_eff = n·(1 − ρ₁ₓρ₁ᵧ)/(1 + ρ₁ₓρ₁ᵧ)
//   (Bartlett 1935, J R Stat Soc 98(3):536-543; Dawdy & Matalas 1964, Handbook of Applied
//   Hydrology §8-III), each lag-1 autocorrelation truncated at 0, and `pValue(r:n:)` reads the
//   tail on that fractional n. Still approximate (AR(1) only), so the hedge in the copy stays.
// • Partial Spearman (FER-438): the first-order partial correlation on midranks,
//   r_xy·z = (r_xy − r_xz·r_yz) / √((1 − r_xz²)(1 − r_yz²)), read against Student's t on df = n − 3 —
//   one degree of freedom paid for the control (Fisher 1924, Metron 3:329-332). Why it exists: the
//   lag +1 pairs whose x is the day strain inherit a CALENDAR artefact. A strain that is 0 on rest
//   days and never trains two days running has ρ₁ ≈ −0.39 (two sessions a week), so whenever y follows
//   the strain of its OWN day (r₀), the pair strain[D] → y[D+1] reads −r₀·|ρ₁| of it — a longer night
//   on training days painted as «shorter the night after». Holding z = strain[D+1] fixed removes
//   exactly that; a real next-day effect survives it (`WhatMovesIt` reads the partial on n_eff − 3).
//
// APPROXIMATE, and association only — never a cause. `pApprox` on raw n remains anticonservative
// on autocorrelated daily series; that is precisely why `MetricTrend` degrades the result to a
// single bit of direction behind its own gate, why `WhatMovesIt` reads its p on n_eff and controls
// the family, and why the screens put much higher n floors on top.

/// Two daily series read against each other.
public struct Correlation: Equatable, Sendable {
    /// Pearson product-moment coefficient, in [−1, 1].
    public let r: Double
    /// Pairs actually used.
    public let n: Int
    /// Two-sided p for H0: r = 0, from Student's t on df = n − 2. The tail is EXACT (the name is
    /// historical). Anticonservative on autocorrelated daily series — see the file note.
    public let pApprox: Double
    /// Least-squares slope of y on x.
    public let slope: Double
    public let intercept: Double

    public init(r: Double, n: Int, pApprox: Double, slope: Double, intercept: Double) {
        self.r = r
        self.n = n
        self.pApprox = pApprox
        self.slope = slope
        self.intercept = intercept
    }
}

/// Two daily series read against each other with a third held fixed. (FER-438)
public struct PartialCorrelation: Equatable, Sendable {
    /// First-order partial coefficient r_xy·z, in [−1, 1].
    public let r: Double
    /// Triples actually used.
    public let n: Int
    /// Two-sided p for H0: r_xy·z = 0, from Student's t on df = n − 3. EXACT tail; anticonservative on
    /// autocorrelated daily series, exactly as `Correlation.pApprox`.
    public let pApprox: Double
}

public enum CorrelationEngine {

    // MARK: - Coefficient and line

    /// Pearson's r plus the least-squares line over `xy`.
    ///
    /// `nil` below `CorrelationStrength.minPairs` pairs — the mathematical floor, since at n = 2 the
    /// coefficient is trivially ±1 — and `nil` when either variable does not vary at all (r would
    /// be undefined). A screen may demand far more than this floor before it will SHOW a
    /// correlation; that is display policy, not this engine's.
    public static func pearson(_ xy: [(Double, Double)]) -> Correlation? {
        let n = xy.count
        guard n >= CorrelationStrength.minPairs else { return nil }

        let nD = Double(n)
        let meanX = xy.reduce(0) { $0 + $1.0 } / nD
        let meanY = xy.reduce(0) { $0 + $1.1 } / nD
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for (x, y) in xy {
            let dx = x - meanX, dy = y - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        guard sxx > 0, syy > 0 else { return nil }

        let r = min(1, max(-1, sxy / (sxx * syy).squareRoot()))
        let slope = sxy / sxx
        return Correlation(r: r, n: n, pApprox: significance(r: r, n: n),
                           slope: slope, intercept: meanY - slope * meanX)
    }

    // MARK: - Joining two dated series

    /// Inner join of two dated series: the `(a, b)` pairs of the days present in BOTH, ascending by
    /// day. A repeated day keeps its LAST entry, on either side.
    public static func alignByDay(_ a: [(day: String, value: Double)],
                                  _ b: [(day: String, value: Double)]) -> [(Double, Double)] {
        let left = lastWins(a)
        let right = lastWins(b)
        return left.keys.filter { right[$0] != nil }.sorted().map { (left[$0]!, right[$0]!) }
    }

    /// Correlate `x` on day D against `y` on day D + `lagDays`. A `lagDays` of 0 is exactly
    /// `pearson(alignByDay(x, y))`. Days of `x` are walked in order so the pair list is
    /// deterministic.
    public static func lagged(x: [(day: String, value: Double)],
                              y: [(day: String, value: Double)],
                              lagDays: Int) -> Correlation? {
        pearson(pairs(x: x, y: y, lagDays: lagDays))
    }

    /// The `(x[D], y[D + lagDays])` pairs behind `lagged`, ascending by D — exposed so a caller can run
    /// a different statistic (ranks, an effective n) over exactly the same pairing. Days absent from
    /// either side are skipped, never interpolated; a repeated day keeps its LAST entry. (FER-438)
    public static func pairs(x: [(day: String, value: Double)],
                             y: [(day: String, value: Double)],
                             lagDays: Int) -> [(Double, Double)] {
        let source = lastWins(x)
        let target = lastWins(y)
        var out: [(Double, Double)] = []
        for day in source.keys.sorted() {
            guard let shifted = shiftDay(day, by: lagDays), let yv = target[shifted] else { continue }
            out.append((source[day]!, yv))
        }
        return out
    }

    /// `pairs` with a third series read on y's day: the `(x[D], y[D + lagDays], z[D + lagDays])` triples,
    /// ascending by D, so a caller can hold z fixed (`spearmanPartial`). A D missing from ANY of the three
    /// sides is dropped, never interpolated; a repeated day keeps its LAST entry. (FER-438)
    public static func triples(x: [(day: String, value: Double)],
                               y: [(day: String, value: Double)],
                               z: [(day: String, value: Double)],
                               lagDays: Int) -> [(Double, Double, Double)] {
        let source = lastWins(x)
        let target = lastWins(y)
        let control = lastWins(z)
        var out: [(Double, Double, Double)] = []
        for day in source.keys.sorted() {
            guard let shifted = shiftDay(day, by: lagDays),
                  let yv = target[shifted], let zv = control[shifted] else { continue }
            out.append((source[day]!, yv, zv))
        }
        return out
    }

    // MARK: - Spearman's ρ (FER-438)

    /// Spearman's rank correlation over `xy`: `pearson` on the midranks of each variable, so `r` is ρ
    /// and `pApprox` its t-approximated two-sided p on df = n − 2 (Zar 1972). Same `nil` rules as
    /// `pearson` (too few pairs, or a variable that does not vary — every value tied). `slope` and
    /// `intercept` are the line through the RANKS, carried only so the type is shared; they are not a
    /// scale in the data's units.
    public static func spearman(_ xy: [(Double, Double)]) -> Correlation? {
        let rx = midranks(xy.map { $0.0 })
        let ry = midranks(xy.map { $0.1 })
        return pearson(Array(zip(rx, ry)))
    }

    /// 1-based midranks: tied values all take the mean of the positions they occupy
    /// (`[10, 20, 20, 30]` → `[1, 2.5, 2.5, 4]`).
    static func midranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var ranks = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, values[order[j + 1]] == values[order[i]] { j += 1 }
            let mean = Double(i + j) / 2 + 1
            for k in i...j { ranks[order[k]] = mean }
            i = j + 1
        }
        return ranks
    }

    // MARK: - Partial Spearman (FER-438)

    /// Spearman's ρ of x and y HOLDING z FIXED, over `xyz`: the first-order partial correlation
    /// r_xy·z = (r_xy − r_xz·r_yz) / √((1 − r_xz²)(1 − r_yz²)) on the midranks of the three variables,
    /// with `pApprox` its two-sided p on df = n − 3 (Fisher 1924). `nil` below four triples (the control
    /// costs a degree of freedom on top of `pearson`'s floor), when any variable does not vary, or when
    /// z fixes x or y entirely (|r_xz| = 1 or |r_yz| = 1 — nothing is left to correlate).
    public static func spearmanPartial(_ xyz: [(Double, Double, Double)]) -> PartialCorrelation? {
        let n = xyz.count
        guard n >= CorrelationStrength.minPairs + 1 else { return nil }
        let rx = midranks(xyz.map { $0.0 })
        let ry = midranks(xyz.map { $0.1 })
        let rz = midranks(xyz.map { $0.2 })
        guard let xy = pearson(Array(zip(rx, ry))),
              let xz = pearson(Array(zip(rx, rz))),
              let yz = pearson(Array(zip(ry, rz))),
              let r = partial(rxy: xy.r, rxz: xz.r, ryz: yz.r) else { return nil }
        return PartialCorrelation(r: r, n: n, pApprox: partialPValue(r: r, n: Double(n)))
    }

    /// The first-order partial coefficient from the three pairwise ones, clamped to [−1, 1]; `nil` when
    /// the denominator vanishes (z fixes x or y entirely).
    static func partial(rxy: Double, rxz: Double, ryz: Double) -> Double? {
        let denominator = ((1 - rxz * rxz) * (1 - ryz * ryz)).squareRoot()
        guard denominator > 0 else { return nil }
        return min(1, max(-1, (rxy - rxz * ryz) / denominator))
    }

    // MARK: - Effective sample size (FER-438)

    /// Lag-1 sample autocorrelation of `values` in the order given:
    /// Σ_{t<n}(v_t − v̄)(v_{t+1} − v̄) / Σ_t(v_t − v̄)². 0 for fewer than 3 values or a constant series.
    public static func lag1Autocorrelation(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 3 else { return 0 }
        let mean = values.reduce(0, +) / Double(n)
        var denominator = 0.0
        for v in values { denominator += (v - mean) * (v - mean) }
        guard denominator > 0 else { return 0 }
        var numerator = 0.0
        for t in 0..<(n - 1) { numerator += (values[t] - mean) * (values[t + 1] - mean) }
        return numerator / denominator
    }

    /// Bartlett's effective sample size for the correlation of two autocorrelated series read over
    /// the SAME pairs (`x[i]` with `y[i]`, in day order): n·(1 − ρ₁ₓρ₁ᵧ)/(1 + ρ₁ₓρ₁ᵧ), with each lag-1
    /// autocorrelation TRUNCATED at 0 — a negative one (a train/rest alternation) never buys extra
    /// evidence. Equals n when either series is white. AR(1)-approximate. (FER-438)
    public static func effectiveN(x: [Double], y: [Double]) -> Double {
        let n = Double(min(x.count, y.count))
        let product = max(0, lag1Autocorrelation(x)) * max(0, lag1Autocorrelation(y))
        return n * (1 - product) / (1 + product)
    }

    /// Two-sided p for a coefficient `r` against Student's t on df = `n` − 2, where `n` may be a
    /// FRACTIONAL effective sample size. `n ≤ 2` has no evidence to offer (1.0); a perfect |r| leaves
    /// no residual variance (0.0). On an integer n this is exactly `Correlation.pApprox`.
    public static func pValue(r: Double, n: Double) -> Double {
        pValue(r: r, degreesOfFreedom: n - 2)
    }

    /// `pValue(r:n:)` for a first-order PARTIAL coefficient: the same tail on df = `n` − 3, one degree of
    /// freedom paid for the control (Fisher 1924). `n` may be a fractional effective sample size; `n ≤ 3`
    /// has no evidence to offer (1.0). (FER-438)
    public static func partialPValue(r: Double, n: Double) -> Double {
        pValue(r: r, degreesOfFreedom: n - 3)
    }

    private static func pValue(r: Double, degreesOfFreedom df: Double) -> Double {
        guard df > 0, df.isFinite else { return 1.0 }
        if abs(r) >= 1 { return 0.0 }
        let t = r * (df / (1 - r * r)).squareRoot()
        return studentTTwoSided(t: t, df: df)
    }

    // MARK: - Student's t tail

    /// Two-sided tail of Student's t at `df` degrees of freedom: P(|T| ≥ |t|).
    ///
    /// `df` may be FRACTIONAL — Welch-Satterthwaite produces one, and so does the stress
    /// time-of-day family. `df ≤ 0` or `t = 0` yield 1.0 (no evidence); the result is clamped to
    /// [0, 1].
    static func studentTTwoSided(t: Double, df: Double) -> Double {
        guard df > 0, t != 0, t.isFinite, df.isFinite else { return 1.0 }
        let x = df / (df + t * t)
        return min(1, max(0, regularizedIncompleteBeta(a: df / 2, b: 0.5, x: x)))
    }

    // MARK: - Civil day arithmetic

    /// `day` plus `delta` days, as a normalised `"yyyy-MM-dd"` key. Gregorian, fixed to UTC, so it
    /// never moves with the device's time zone. A `delta` of 0 returns the string unchanged.
    ///
    /// `nil` unless the string has exactly three integer components with the month in 1…12 and the
    /// day at least 1. Output always carries a four-digit year and two-digit month and day.
    ///
    /// (The package's OTHER day arithmetic is `ComparisonEngine.epochDay`, which turns a key into
    /// an integer by pure arithmetic. Two exist because their consumers want different types; do
    /// not add a third.)
    static func shiftDay(_ day: String, by delta: Int) -> String? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              (1...12).contains(month), dayOfMonth >= 1 else { return nil }
        guard delta != 0 else { return day }

        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        calendar.timeZone = utc

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        guard let anchor = calendar.date(from: components),
              let moved = calendar.date(byAdding: .day, value: delta, to: anchor) else { return nil }

        let out = calendar.dateComponents([.year, .month, .day], from: moved)
        guard let y = out.year, let m = out.month, let d = out.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Internals

    /// Two-sided p for a coefficient on an integer n — `pValue(r:n:)` on the raw pair count.
    private static func significance(r: Double, n: Int) -> Double {
        pValue(r: r, n: Double(n))
    }

    /// Latest value per day key.
    private static func lastWins(_ rows: [(day: String, value: Double)]) -> [String: Double] {
        var out: [String: Double] = [:]
        for row in rows { out[row.day] = row.value }
        return out
    }

    /// Regularized incomplete beta I_x(a, b), to ~1e-10. Deterministic: `lgamma`, `exp`, `log` and
    /// a continued fraction, no tables.
    private static func regularizedIncompleteBeta(a: Double, b: Double, x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // xᵃ(1−x)ᵇ / B(a,b), through log-gamma so the factorials never overflow.
        let front = exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log1p(-x))
        // The fraction converges fast only on the near side of the distribution's mode; past it,
        // reflect: I_x(a,b) = 1 − I_{1−x}(b,a).
        if x < (a + 1) / (a + b + 2) {
            return front * betaFraction(a: a, b: b, x: x) / a
        }
        return 1 - front * betaFraction(a: b, b: a, x: 1 - x) / b
    }

    /// The continued fraction of the incomplete beta, by modified Lentz. `guard` is the zero-pivot
    /// floor, and the loop stops as soon as a factor stops moving.
    private static func betaFraction(a: Double, b: Double, x: Double) -> Double {
        let guardFloor = 1e-30
        let maxIterations = 200
        let tolerance = 1e-12

        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < guardFloor { d = guardFloor }
        d = 1 / d
        var h = d

        for m in 1...maxIterations {
            let mD = Double(m)
            let m2 = 2 * mD

            // Even step.
            var numerator = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1 + numerator * d
            if abs(d) < guardFloor { d = guardFloor }
            c = 1 + numerator / c
            if abs(c) < guardFloor { c = guardFloor }
            d = 1 / d
            h *= d * c

            // Odd step.
            numerator = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1 + numerator * d
            if abs(d) < guardFloor { d = guardFloor }
            c = 1 + numerator / c
            if abs(c) < guardFloor { c = guardFloor }
            d = 1 / d
            let factor = d * c
            h *= factor

            if abs(factor - 1) < tolerance { break }
        }
        return h
    }
}
