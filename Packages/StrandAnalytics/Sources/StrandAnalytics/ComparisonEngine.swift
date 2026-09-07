import Foundation

// ComparisonEngine.swift — summarising a slice of a daily series, and comparing one period of it
// against the period before.
//
// Pure, deterministic, DB-free, Foundation-only. Every trend chip in the app ("last 30 days vs the
// 30 before") comes through here, plus the plain descriptive stats a detail screen prints under a
// chart.
//
// METHOD:
// • Location and dispersion: arithmetic mean, order-statistic median, and the SAMPLE standard
//   deviation with ddof = 1 (the usual unbiased-variance convention). The median is NOT computed
//   here — it is delegated to the one median in the package (`HRVAnalyzer.median`), because a
//   second copy of a median is exactly the kind of duplicate the repo has already paid for.
// • Trend: ordinary least squares of the value against its 0-based POSITION in the slice
//   (Legendre 1805 / Gauss 1809). Position, not calendar day: gaps in the series are skipped
//   rather than spaced, so this describes the shape of what is there, not a rate per real day.
// • Period contrast: the difference of the two means, and that difference as a percentage of the
//   ABSOLUTE previous mean — absolute so the sign of the percentage follows the sign of the
//   difference even for metrics that can go negative.
// • Civil day → days since 1970-01-01: pure integer arithmetic on the proleptic Gregorian
//   calendar (Howard Hinnant's days-from-civil algorithm, public domain). No `DateFormatter`, no
//   calendar object, no time zone, so it can never drift with the device.
//
// APPROXIMATE and descriptive. Nothing here is a hypothesis test.

/// The descriptive summary of one slice of a daily series.
public struct SeriesStat: Equatable, Sendable {
    public let mean: Double
    public let median: Double
    public let min: Double
    public let max: Double
    /// Sample standard deviation (ddof = 1); 0 for fewer than two values.
    public let stdev: Double
    public let n: Int
    /// OLS slope against the 0-based index within the slice — per POSITION, not per calendar day.
    public let slopePerDay: Double

    public init(mean: Double, median: Double, min: Double, max: Double,
                stdev: Double, n: Int, slopePerDay: Double) {
        self.mean = mean
        self.median = median
        self.min = min
        self.max = max
        self.stdev = stdev
        self.n = n
        self.slopePerDay = slopePerDay
    }

    /// The summary of nothing: every field zero, `n = 0`.
    public static let empty = SeriesStat(mean: 0, median: 0, min: 0, max: 0,
                                         stdev: 0, n: 0, slopePerDay: 0)
}

/// One period of a daily series against the period immediately before it.
public struct PeriodComparison: Equatable, Sendable {
    public let current: SeriesStat
    public let previous: SeriesStat
    /// `current.mean − previous.mean`.
    public let delta: Double
    /// `delta` as a percentage of |previous.mean|. `nil` when there is no previous period or its
    /// mean is 0 — and `nil` MEANS something to the UI: the trend chip hides rather than showing
    /// a misleading "0 %".
    public let pctChange: Double?
    /// −1, 0 or +1. Always 0 when either period is empty.
    public let direction: Int

    public init(current: SeriesStat, previous: SeriesStat, delta: Double,
                pctChange: Double?, direction: Int) {
        self.current = current
        self.previous = previous
        self.delta = delta
        self.pctChange = pctChange
        self.direction = direction
    }
}

public enum ComparisonEngine {

    // MARK: - Summarising a slice

    /// Summarise `values` in the order given. Empty input yields `SeriesStat.empty`; a single value
    /// yields itself for mean/median/min/max with zero dispersion and zero slope.
    public static func stat(_ values: [Double]) -> SeriesStat {
        let n = values.count
        guard n > 0 else { return .empty }

        let mean = values.reduce(0, +) / Double(n)
        let stdev: Double
        if n >= 2 {
            let ss = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            stdev = (ss / Double(n - 1)).squareRoot()
        } else {
            stdev = 0
        }
        return SeriesStat(mean: mean,
                          median: HRVAnalyzer.median(values),
                          min: values.min() ?? 0,
                          max: values.max() ?? 0,
                          stdev: stdev,
                          n: n,
                          slopePerDay: ordinaryLeastSquaresSlope(values))
    }

    // MARK: - Comparing two periods

    /// Contrast two already-sliced periods on their means.
    public static func compare(current: [Double], previous: [Double]) -> PeriodComparison {
        let cur = stat(current)
        let prev = stat(previous)
        let delta = cur.mean - prev.mean
        // FER-465: `prev.mean != 0` deja pasar NaN (`NaN != 0` es `true`) → `pct` NaN, que aguas
        // abajo hace `Int(pct.rounded())` un trap en los formateadores. Exige operandos finitos: un
        // periodo con un valor no-finito da `pctChange == nil` (sin porcentaje), no un crash.
        let pct: Double? = (prev.n > 0 && prev.mean.isFinite && prev.mean != 0 && delta.isFinite)
            ? delta / abs(prev.mean) * 100 : nil
        let direction: Int
        if cur.n == 0 || prev.n == 0 {
            direction = 0
        } else {
            direction = delta > 0 ? 1 : (delta < 0 ? -1 : 0)
        }
        return PeriodComparison(current: cur, previous: prev, delta: delta,
                                pctChange: pct, direction: direction)
    }

    /// Contrast the `windowDays` days ending at `referenceDay` against the equally long window
    /// immediately before it. Days outside both windows are ignored.
    ///
    /// This is the one that follows the window the USER picked (7 / 30 / 90 / 180 / 365 — those
    /// live in the app's `ExploreRange`, not here; this takes `windowDays` as a parameter).
    /// Values are sorted by day key before summarising, so the slope is chronological no matter
    /// what order the rows arrive in. A `windowDays < 1` or an unparseable reference yields two
    /// empty periods.
    public static func periodOverPeriod(byDay: [(day: String, value: Double)],
                                        windowDays: Int, referenceDay: String) -> PeriodComparison {
        guard windowDays >= 1, let ref = epochDay(of: referenceDay) else {
            return compare(current: [], previous: [])
        }
        var current: [(day: String, value: Double)] = []
        var previous: [(day: String, value: Double)] = []
        for row in byDay {
            guard let d = epochDay(of: row.day) else { continue }
            let back = ref - d
            if back >= 0 && back < windowDays {
                current.append(row)
            } else if back >= windowDays && back < 2 * windowDays {
                previous.append(row)
            }
        }
        return compare(current: chronological(current), previous: chronological(previous))
    }

    // MARK: - Civil day arithmetic

    /// Days since 1970-01-01 for a `"yyyy-MM-dd"` key, by pure integer arithmetic on the proleptic
    /// Gregorian calendar (Hinnant's days-from-civil, public domain). No `DateFormatter`, no
    /// calendar, no time zone — it is the canonical inverse of the day key, used both to place a
    /// point on a chart and to decide whether two days are civil-contiguous.
    ///
    /// `nil` unless the string has exactly three integer components with the month in 1…12 and the
    /// day in 1…31. It validates RANGE, not calendar: day 31 of a 30-day month is accepted, because
    /// every key it is ever handed is one this repo produced.
    ///
    /// (The package's OTHER day arithmetic is `CorrelationEngine.shiftDay`, which adds days to a
    /// key and returns a key. Two exist because their consumers want different types; do not add a
    /// third.)
    public static func epochDay(of day: String) -> Int? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(dayOfMonth) else { return nil }

        // Shift the year so March starts it: then a leap day is always the last day of the year and
        // the month-length pattern is a clean 153-day/5-month repeat.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                     // [0, 399]
        let shiftedMonth = month + (month > 2 ? -3 : 9)                   // March = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + dayOfMonth - 1     // [0, 365]
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    // MARK: - Internals

    /// OLS slope of `values` against their 0-based index. Zero for fewer than two points or a
    /// degenerate denominator.
    private static func ordinaryLeastSquaresSlope(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        let meanIndex = Double(n - 1) / 2
        let meanValue = values.reduce(0, +) / Double(n)
        var covariance = 0.0
        var variance = 0.0
        for (i, y) in values.enumerated() {
            let dx = Double(i) - meanIndex
            covariance += dx * (y - meanValue)
            variance += dx * dx
        }
        guard variance != 0 else { return 0 }
        return covariance / variance
    }

    /// Values ordered by day key — the keys sort lexicographically into chronological order.
    private static func chronological(_ rows: [(day: String, value: Double)]) -> [Double] {
        rows.sorted { $0.day < $1.day }.map(\.value)
    }
}
