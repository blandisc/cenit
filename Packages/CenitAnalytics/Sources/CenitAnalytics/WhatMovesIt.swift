import Foundation
import CenitModels

// WhatMovesIt.swift — «Tu patrón»: which of the user's OWN daily series a metric moves with. (FER-438)
//
// Pure, deterministic, DB-free. Grew out of the FER-209 block for the two recovery vitals (HRV / resting
// HR) and the FER-239 strain drivers; both are folded in here as ONE family of relationships, so the
// multiplicity control can see every test at once. The app layer only maps the result to copy.
//
// METHOD (per relationship, then per family):
// • Pairing: `CorrelationEngine.pairs(x:y:lagDays:)` — x on day D against y on day D + lag. Day keys are
//   the storage keys: sleep and efficiency are keyed by the WAKING day (the night that ends the morning
//   of D), strain / steps / resting HR by the calendar day. So «strain[D] → sleep[D+1]» reads today's
//   load against the night that follows, and «efficiency[D] → strain[D]» reads last night against
//   today's load. `lagged` skips absent days, never interpolates.
// • Statistic: Spearman's ρ wherever strain or steps enter (strain is 0 on rest days — a zero-inflated
//   series on which Pearson mostly measures the 0-vs-not contrast — and steps are heavy-tailed);
//   Pearson's r where both series are continuous (duration, resting HR). p from Student's t on
//   df = n − 2 (Zar 1972 for ρ).
// • Effective n: the p of every CROSS pair is read on Bartlett's n_eff (`CorrelationEngine.effectiveN`,
//   lag-1 autocorrelations truncated at 0), because daily series are autocorrelated and the raw p is
//   anticonservative. The auto-lag (sleep → next night's sleep) does NOT: under H0 the series is white
//   and its own ρ₁ IS the statistic — shrinking n by it would double-count.
// • Minority-class floor: where the zero-inflated strain series enters and has at least one 0, the
//   pair needs min(#strain = 0, #strain > 0) ≥ `minorityFloor`; otherwise seven training days out of
//   49 pass a «finding» on seven points.
// • Family control: all testable pairs (n ≥ their floor, minority floor met, a defined coefficient)
//   are computed in ONE pass and their p-values pass through Benjamini-Hochberg
//   (`MultipleComparisons.benjaminiHochberg`); a finding needs q < `maxQ`. Eight tests at α = 0.05
//   would otherwise yield ≥ 1 false finding 34 % of the time under the null.
// • Direction only: a finding is the sign of the coefficient (`MetricTrend`), never the number, and
//   never a cause — it is «se mueve con», nothing more.
//
// RETIRED here (FER-438, gates /cso + /estadistico):
// • HRV: no relationship. The FER-209 block read `avgHrv` through `SourceLens.clearBandHrv`, which nils it
//   on every Apple row — the series was always empty and the block never painted. Reviving it takes a
//   dense nocturnal RMSSD series (separate issue); Apple's SDNN is the wrong construct (Zhang 2025).
// • Prior-day strain → strain (FER-239 auto-lag): for a strain that is 0 on rest days its lag-1
//   autocorrelation is −π/(1−π) by construction — «lighter the day after» for everyone who does not
//   train two days running. It described the calendar, not the body.
// • Same-day recovery → strain (FER-239): `recovery` is nil on every Apple row; the driver never fired.
//
// KNOBS (product calibration, NOT derived from a publication — rotulados): `minPairs` 42 ≈ six weeks of
// paired days (a calendar floor, not an n_eff); `minPairsWithEfficiency` 56 because the wrist's
// sleep/wake reliability ≈ 0.5 attenuates any true r by ~√0.5, so a visible pattern needs more nights
// and the block flickers less; `minorityFloor` 10 (at n₁ = 10 of 42 a finding still needs d ≥ 0.71);
// `minAbsR` 0.20 is COSMETIC — below n ≈ 97 the p is the binding bar (|r| ≥ 0.30 at n = 42).
//
// SOURCES (verified by the /cso gate): Kredlow 2015, J Behav Med 38(3):427 (acute exercise → TST,
// efficiency, WASO); Atoui 2021, Sleep Med Rev 57:101426 (efficiency → next-day activity; activity →
// shorter TST, small); Lambiase 2013, Med Sci Sports Exerc 45(12):2362; Mead 2019, Int J Behav Med
// 26(5):562 (day-of-week confounds activity); Borbély 1982 / 2022, J Sleep Res 31(4):e13598 (process
// S — the night-to-night rebound); Dettoni 2012, J Appl Physiol 113(2):232 and Faust 2020, npj Digit
// Med 3:39 (short / late nights → resting HR up); Stanley 2013, Sports Med 43(12):1259 (parasympathetic
// reactivation 24–48 h after hard effort).

/// One relationship the block may assert: x moves, and the metric (y) tends to move with it.
public enum WhatMovesItRelationship: String, CaseIterable, Sendable {
    /// Yesterday's strain → tonight's sleep duration (lag +1, Spearman).
    case sleepPriorStrain = "sleep.priorStrain"
    /// Last night's duration → tonight's (lag +1, Pearson; the homeostatic rebound or the habit).
    case sleepPriorNight = "sleep.priorNight"
    /// Last night's efficiency → today's strain (lag 0, Spearman).
    case strainEfficiency = "strain.efficiency"
    /// Yesterday's strain → tonight's efficiency (lag +1, Spearman).
    case efficiencyPriorStrain = "efficiency.priorStrain"
    /// Last night's efficiency → today's steps (lag 0, Spearman; today's partial count excluded).
    case stepsEfficiency = "steps.efficiency"
    /// Last night's duration → resting HR (lag 0, Pearson).
    case rhrSleepDuration = "rhr.sleepDuration"
    /// Yesterday's strain → resting HR (lag +1, Spearman).
    case rhrPriorStrain = "rhr.priorStrain"

    /// The metric whose sheet renders the finding — the `y` side. Every key here is a
    /// `MetricInfo.id` / `MetricDetailSpec` key; no relationship targets `hrv`.
    public var metricKey: String {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight: return "sleep"
        case .strainEfficiency:                   return "strain"
        case .efficiencyPriorStrain:              return "sleep_efficiency"
        case .stepsEfficiency:                    return "steps"
        case .rhrSleepDuration, .rhrPriorStrain:  return "rhr"
        }
    }

    enum Statistic { case pearson, spearman }
    enum Column { case sleepDuration, efficiency, strain, steps, restingHR }
    enum Side { case x, y }

    var x: Column {
        switch self {
        case .sleepPriorStrain, .efficiencyPriorStrain, .rhrPriorStrain: return .strain
        case .sleepPriorNight, .rhrSleepDuration:                        return .sleepDuration
        case .strainEfficiency, .stepsEfficiency:                        return .efficiency
        }
    }

    var y: Column {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight:  return .sleepDuration
        case .strainEfficiency:                    return .strain
        case .efficiencyPriorStrain:               return .efficiency
        case .stepsEfficiency:                     return .steps
        case .rhrSleepDuration, .rhrPriorStrain:   return .restingHR
        }
    }

    var lagDays: Int {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight, .efficiencyPriorStrain, .rhrPriorStrain: return 1
        case .strainEfficiency, .stepsEfficiency, .rhrSleepDuration:                       return 0
        }
    }

    var statistic: Statistic {
        switch self {
        case .sleepPriorNight, .rhrSleepDuration: return .pearson
        default:                                  return .spearman
        }
    }

    /// Cross pairs read p on n_eff; the auto-lag does not (see the file note).
    var usesEffectiveN: Bool { self != .sleepPriorNight }

    /// Which side carries the zero-inflated strain series (minority-class floor), if any.
    var zeroInflatedSide: Side? {
        switch self {
        case .sleepPriorStrain, .efficiencyPriorStrain, .rhrPriorStrain: return .x
        case .strainEfficiency:                                          return .y
        case .sleepPriorNight, .stepsEfficiency, .rhrSleepDuration:      return nil
        }
    }

    /// Pairs with efficiency on either side take the higher floor (its reliability knob).
    var involvesEfficiency: Bool { x == .efficiency || y == .efficiency }
}

/// One gated, directional relationship to render in the «Tu patrón» block. Never carries a
/// coefficient or an implied cause; the copy lives in the app catalog under `copyKey`.
public struct WhatMovesItFinding: Equatable, Sendable, Identifiable {
    public let relationship: WhatMovesItRelationship
    public let trend: MetricTrend

    public init(relationship: WhatMovesItRelationship, trend: MetricTrend) {
        self.relationship = relationship
        self.trend = trend
    }

    public var id: String { relationship.rawValue }

    /// The catalog key of the sentence: `patron.<relationship>.<rises|falls>` — the ONE home of the
    /// «Tu patrón» copy (every surface resolves this key; no per-screen switch).
    public var copyKey: String {
        "patron.\(relationship.rawValue).\(trend == .rises ? "rises" : "falls")"
    }
}

/// The bar a relationship must clear. Every field is a rotulado product knob (see the file note).
public struct WhatMovesItGate: Equatable, Sendable {
    /// Paired days required — a calendar floor (≈ six weeks), not an effective n.
    public var minPairs: Int
    /// The floor for the pairs that carry sleep efficiency (its wrist reliability ≈ 0.5).
    public var minPairsWithEfficiency: Int
    /// min(#strain = 0, #strain > 0) required when the strain series has any 0.
    public var minorityFloor: Int
    /// Cosmetic |coefficient| floor; the p / q is the binding bar below n ≈ 97.
    public var minAbsR: Double
    /// Benjamini-Hochberg q ceiling over the family.
    public var maxQ: Double

    public init(minPairs: Int = 42, minPairsWithEfficiency: Int = 56, minorityFloor: Int = 10,
                minAbsR: Double = 0.20, maxQ: Double = 0.05) {
        self.minPairs = minPairs
        self.minPairsWithEfficiency = minPairsWithEfficiency
        self.minorityFloor = minorityFloor
        self.minAbsR = minAbsR
        self.maxQ = maxQ
    }

    public static let `default` = WhatMovesItGate()

    func minPairs(for relationship: WhatMovesItRelationship) -> Int {
        relationship.involvesEfficiency ? minPairsWithEfficiency : minPairs
    }
}

/// One TESTABLE relationship with its numbers — for tests, docs and any transparency surface. The
/// screens never show these; they render `WhatMovesItFinding` only.
public struct WhatMovesItCandidate: Equatable, Sendable {
    public let relationship: WhatMovesItRelationship
    /// Spearman's ρ or Pearson's r, per the relationship's statistic.
    public let r: Double
    /// Pairs used.
    public let n: Int
    /// Bartlett's n_eff for a cross pair; `Double(n)` for the auto-lag.
    public let nEffective: Double
    /// Two-sided p on `nEffective`.
    public let p: Double
    /// Benjamini-Hochberg q over the family of candidates computed together.
    public let q: Double

    public var trend: MetricTrend { r >= 0 ? .rises : .falls }
}

public enum WhatMovesItEngine {

    /// Every testable relationship over `days`, computed in one pass with its BH q. `today` is the
    /// device's local day key: rows after it are ignored (a UTC «tomorrow» row), and today's own
    /// steps — a running total, not a finished day — are dropped from the steps pair.
    public static func candidates(days: [DailyMetric], today: String,
                                  gate: WhatMovesItGate = .default) -> [WhatMovesItCandidate] {
        struct Tested { let relationship: WhatMovesItRelationship; let r: Double; let n: Int; let nEff: Double; let p: Double }
        var tested: [Tested] = []

        for relationship in WhatMovesItRelationship.allCases {
            let xs = series(days, relationship.x, today: today)
            let ys = series(days, relationship.y, today: today)
            let pairs = CorrelationEngine.pairs(x: xs, y: ys, lagDays: relationship.lagDays)
            guard pairs.count >= gate.minPairs(for: relationship) else { continue }

            if let side = relationship.zeroInflatedSide {
                let strainValues = pairs.map { side == .x ? $0.0 : $0.1 }
                let zeros = strainValues.filter { $0 == 0 }.count
                let positives = strainValues.filter { $0 > 0 }.count
                if zeros >= 1, min(zeros, positives) < gate.minorityFloor { continue }
            }

            let x = pairs.map { $0.0 }, y = pairs.map { $0.1 }
            let c: Correlation?
            let ex: [Double], ey: [Double]
            switch relationship.statistic {
            case .pearson:
                c = CorrelationEngine.pearson(pairs)
                ex = x; ey = y
            case .spearman:
                c = CorrelationEngine.spearman(pairs)
                ex = CorrelationEngine.midranks(x); ey = CorrelationEngine.midranks(y)
            }
            guard let c else { continue }

            let nEff = relationship.usesEffectiveN ? CorrelationEngine.effectiveN(x: ex, y: ey) : Double(c.n)
            let p = relationship.usesEffectiveN ? CorrelationEngine.pValue(r: c.r, n: nEff) : c.pApprox
            tested.append(Tested(relationship: relationship, r: c.r, n: c.n, nEff: nEff, p: p))
        }

        let q = MultipleComparisons.benjaminiHochberg(tested.map(\.p))
        return zip(tested, q).map { t, q in
            WhatMovesItCandidate(relationship: t.relationship, r: t.r, n: t.n, nEffective: t.nEff, p: t.p, q: q)
        }
    }

    /// The findings that clear `gate`, by metric key (`sleep`, `strain`, `sleep_efficiency`, `steps`,
    /// `rhr`), each list in `WhatMovesItRelationship` order. A metric absent from the result — or with an
    /// empty list — has nothing to assert → the caller hides the block; it never invents a direction.
    public static func family(days: [DailyMetric], today: String,
                              gate: WhatMovesItGate = .default) -> [String: [WhatMovesItFinding]] {
        var out: [String: [WhatMovesItFinding]] = [:]
        for candidate in candidates(days: days, today: today, gate: gate)
        where candidate.q < gate.maxQ && abs(candidate.r) >= gate.minAbsR {
            out[candidate.relationship.metricKey, default: []]
                .append(WhatMovesItFinding(relationship: candidate.relationship, trend: candidate.trend))
        }
        return out
    }

    // MARK: - Internals

    /// One column's daily series, oldest → newest, rows after `today` dropped; the steps column also
    /// drops `today` itself (a partial running total).
    private static func series(_ days: [DailyMetric], _ column: WhatMovesItRelationship.Column,
                               today: String) -> [(day: String, value: Double)] {
        days.compactMap { d -> (day: String, value: Double)? in
            guard d.day <= today else { return nil }
            let value: Double?
            switch column {
            case .sleepDuration: value = d.totalSleepMin
            case .efficiency:    value = d.efficiency
            case .strain:        value = d.strain
            case .steps:         value = d.day < today ? d.steps.map(Double.init) : nil
            case .restingHR:     value = d.restingHr.map(Double.init)
            }
            return value.map { (day: d.day, value: $0) }
        }
        .sorted { $0.day < $1.day }
    }
}
