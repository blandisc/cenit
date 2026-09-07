import Foundation

// VitalBands.swift — is tonight's vital sign «in range» FOR THIS PERSON, and on what evidence.
//
// THE PROBLEM THIS EXISTS TO SOLVE. A population reference range answers «is this value normal for
// humans». That is the wrong question for a passive nightly readout, and answering it produces a
// specific, corrosive false positive: someone whose own HRV has sat at 35 ms every night for a year
// is told, every single morning, that they are out of range — because a textbook band starts at 40.
// Nothing is wrong with them; the comparison is wrong. So when there is enough of a person's own
// history to say what THEIR normal is, that is what the value is compared against, and the answer
// says which of the two comparisons it used.
//
// WHAT THIS ENGINE DOES NOT DO, and the reason it is worth writing down: the plausibility bounds
// carried by a metric's baseline configuration are NOT used as the «in range» band. They are there to
// reject impossible readings before a baseline absorbs them. Using them as the band is exactly how
// the false positive above comes back.
//
// CRITERION. In range when the robust deviation from the personal baseline is within `sigmaK`. The
// baseline itself — a winsorised EWMA of the person's own nights — belongs to `Baselines`; this file
// only decides what to compare against and how wide the band is.
//
// NO CALLER TODAY for the band decision itself: `sigmaK` is what the rest of the package cites. The
// engine stays because this is where the rule is WRITTEN DOWN and tested; reducing it to a loose
// constant would leave the criterion with no home.

public enum VitalBands {

    /// Which side of the band a value fell on.
    public enum Band: String, Equatable, Sendable {
        case inRange
        case outOfRange
        /// No value to judge.
        case noData
    }

    /// What the decision was made against.
    public enum Basis: String, Equatable, Sendable {
        /// The person's own baseline.
        case personal
        /// A population reference range — the fallback while a personal baseline is not yet
        /// trustworthy, or when the metric has no personal-baseline configuration at all.
        case population
    }

    /// The decision, plus how much of the person's own history stood behind it.
    public struct Result: Equatable, Sendable {
        public let band: Band
        public let basis: Basis
        /// Valid nights in the history that was folded.
        public let nights: Int

        public init(band: Band, basis: Basis, nights: Int) {
            self.band = band
            self.basis = basis
            self.nights = nights
        }
    }

    /// Half-width of the personal band, in robust standard deviations.
    ///
    /// NOT a knob to turn lightly. Two σ marks roughly 95 % of a person's own nights as ordinary,
    /// which is the right sensitivity for something that reports passively every morning. At one σ,
    /// about a third of perfectly normal nights would come back flagged — noise presented as signal —
    /// which is why `k = 1` is refused repository-wide and several engines cite this constant by name
    /// so that «outside your normal» means one thing across the app.
    public static let sigmaK: Double = 2.0

    /// Skin temperature can arrive in two different semantics in the same series: an ABSOLUTE reading
    /// in °C, and a DEVIATION from the person's own nightly baseline in ±°C. Mixed together they make
    /// a bimodal series that no baseline can describe.
    ///
    /// The two are separable without ambiguity because their ranges cannot overlap: no real skin
    /// temperature is below 20 °C, and no real nightly deviation reaches ±20 °C. This threshold sits
    /// in the empty space between them.
    public static func isAbsoluteSkinTemp(_ v: Double) -> Bool { v >= 20.0 }

    /// Keep only the history entries that share the semantics of the value being shown, replacing the
    /// rest with `nil` so positions are preserved. Comparing a deviation against absolute readings
    /// (or the reverse) would be comparing two different quantities.
    public static func skinTempHistory(matching value: Double, in history: [Double?]) -> [Double?] {
        let wantAbsolute = isAbsoluteSkinTemp(value)
        return history.map { v in
            guard let v else { return nil }
            return isAbsoluteSkinTemp(v) == wantAbsolute ? v : nil
        }
    }

    /// Baseline configuration for the DEVIATION form of skin temperature (±°C around the person's own
    /// nightly normal), as opposed to the absolute form that `Baselines.metricCfg["skin_temp"]`
    /// describes. Not log-domain: a deviation is signed.
    public static let skinTempDeviationCfg = MetricCfg(
        minVal: -5.0, maxVal: 5.0, floorSpread: 0.3, halfLifeB: 14.0, halfLifeS: 21.0)

    /// Expand day-keyed readings into a contiguous daily series between the first and last day
    /// present, with `nil` on every day in between that has no reading.
    ///
    /// The padding is the point. Without it, someone who stops recording for two months and comes back
    /// is compared against a baseline built from their last fourteen readings — a baseline that is two
    /// months old but looks perfectly fresh to anything counting entries. The `nil` days are what let
    /// the baseline notice it has gone stale.
    ///
    /// Date arithmetic is fixed to UTC over the key strings themselves: no clock and no timezone are
    /// read, so the same input always produces the same series. Malformed keys are dropped, and a
    /// repeated key keeps its last value.
    public static func calendarSeries(_ rows: [(day: String, value: Double?)]) -> [Double?] {
        var byDay: [String: Double?] = [:]
        var days: [Date] = []
        for r in rows {
            guard let d = dayParser.date(from: r.day) else { continue }
            if byDay[r.day] == nil { days.append(d) }
            byDay[r.day] = r.value
        }
        guard let first = days.min(), let last = days.max() else { return [] }

        var out: [Double?] = []
        var cursor = first
        while cursor <= last {
            out.append(byDay[dayParser.string(from: cursor)] ?? nil)
            cursor = cursor.addingTimeInterval(86_400)
        }
        return out
    }

    /// Whether today's value is in range for this person, and on what evidence.
    ///
    /// The order of the checks is part of the contract:
    ///
    ///   1. No value at all → nothing to judge.
    ///   2. No baseline configuration → the population range decides, permanently. This is the right
    ///      answer for blood-oxygen saturation: there is no personal-baseline configuration for it,
    ///      and an absolute floor IS meaningful there regardless of anyone's history.
    ///   3. Fold the person's own history into a baseline.
    ///   4. A value outside the metric's plausibility bounds is out of range, FULL STOP. This check
    ///      cannot move below the personal branch: absolute implausibility outranks any amount of
    ///      personal dispersion, or a wide baseline would end up excusing an impossible reading.
    ///   5. With a trustworthy personal baseline, `|z| ≤ sigmaK`.
    ///   6. Otherwise fall back to the population range, and say so.
    ///
    /// `history` is the nightly series EXCLUDING the day being shown, oldest first, with `nil` for
    /// nights without a reading — see `calendarSeries` for why those `nil`s matter.
    public static func band(value: Double?, history: [Double?],
                           populationRange: ClosedRange<Double>, cfg: MetricCfg?) -> Result {
        guard let value else { return Result(band: .noData, basis: .population, nights: 0) }
        guard let cfg else {
            return Result(band: populationBand(value, populationRange), basis: .population, nights: 0)
        }
        let state = Baselines.foldHistory(history, cfg: cfg)
        guard value >= cfg.minVal, value <= cfg.maxVal else {
            return Result(band: .outOfRange, basis: .population, nights: state.nValid)
        }
        guard state.trusted else {
            return Result(band: populationBand(value, populationRange), basis: .population,
                          nights: state.nValid)
        }
        let z = Baselines.deviation(value, state: state).z
        return Result(band: abs(z) <= sigmaK ? .inRange : .outOfRange, basis: .personal,
                      nights: state.nValid)
    }

    // MARK: - Private

    private static func populationBand(_ value: Double, _ range: ClosedRange<Double>) -> Band {
        range.contains(value) ? .inRange : .outOfRange
    }

    /// Fixed POSIX/UTC parser for day keys, so the expansion never depends on the device's locale or
    /// timezone. Built once; constructing a formatter per row is expensive.
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
