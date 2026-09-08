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
// APPROXIMATE, and association only — never a cause. Worse, the p tests H0: r = 0 on observations
// that are NOT independent: daily HRV / heart-rate / sleep series are strongly autocorrelated, so
// the p is ANTICONSERVATIVE. That is precisely why `MetricTrend` degrades the result to a single
// bit of direction behind its own gate, and why the screens put much higher n floors on top.

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
        let source = lastWins(x)
        let target = lastWins(y)
        var pairs: [(Double, Double)] = []
        for day in source.keys.sorted() {
            guard let shifted = shiftDay(day, by: lagDays), let yv = target[shifted] else { continue }
            pairs.append((source[day]!, yv))
        }
        return pearson(pairs)
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

    /// Two-sided p for a coefficient. `n ≤ 2` has no evidence to offer; a perfect |r| leaves no
    /// residual variance, so its tail is 0.
    private static func significance(r: Double, n: Int) -> Double {
        guard n > 2 else { return 1.0 }
        if abs(r) >= 1 { return 0.0 }
        let df = Double(n - 2)
        let t = r * (df / (1 - r * r)).squareRoot()
        return studentTTwoSided(t: t, df: df)
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
