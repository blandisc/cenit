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
// • Partial on the lag +1 strain pairs: the three pairs whose x is the day strain (→ the next night's
//   duration, the next night's efficiency, the next day's resting HR) read Spearman's ρ HOLDING FIXED the
//   strain of y's own day, z = strain[D+1] (`CorrelationEngine.spearmanPartial`, p on df = n_eff − 3).
//   Without it they inherit a calendar artefact: a strain that is 0 on rest days and never trains two
//   days running has ρ₁ ≈ −0.39 (two sessions a week), so whenever y follows the SAME day's strain (r₀)
//   the lag +1 pair reads −r₀·|ρ₁| of it — a longer night ON training days painted as «shorter the
//   night after». The post-implementation gate's fixture (sleep = 420 + 35·W(i) + 8K(i)) read
//   ρ = −0.28, q = 0.03 that way; the partial reads +0.04. The triples need strain on BOTH days, so a
//   D whose next day has no strain is dropped from that pair.
// • Second-order partial on the sleep auto-lag (FER-480): `sleepPriorNight` sits on BOTH ends of the
//   SAME calendar artefact — x = duration[D] falls on a day whose night was long BECAUSE it followed
//   a training day, y = duration[D+1] falls on a day that, by the strain series' own ρ₁ ≈ −0.39, is
//   rarely also a training day. Holding one side's strain fixed (the FER-438 fix) is not enough here
//   because the artefact touches x, not just y; it takes strain on BOTH days at once —
//   `CorrelationEngine.spearmanPartial2` holding z1 = strain[D] and z2 = strain[D+1] fixed, p on
//   df = n − 4. The CDO's pure-calendar fixture (sleep = 420 + 35·W(i), no real rebound) read
//   r = −0.405, p = 0.0015 before the control; the second-order partial reads r ≈ −0.016, p ≈ 0.91 —
//   effectively 100% of the −0.41 was the training calendar. A real homeostatic rebound (Borbély 1982
//   process S), a weekend catch-up, or another schedule driver, superposed on the same calendar,
//   survives the double control.
// • Simple-correlation fallback for a degenerate control (FER-483, owner decision, reversible): the
//   FER-480 partial above requires the training-calendar confound to be ESTIMABLE from strain[D] and
//   strain[D+1] — someone who does not train has no such calendar, and the control cannot buy back
//   what it cannot see. `WhatMovesItEngine.controlDegenerates` reads strain over the exact window
//   `sleepPriorNight`'s own duration series covers and answers NO (keep the partial) unless training
//   effort is functionally absent there: fewer than `WhatMovesItGate.effortPresenceFloor` (3) days
//   show ANY measurable (> 0) effort, or the available values are (numerically) constant — either
//   one alone means there is no on/off rhythm left for the partial to hold fixed, only for it to
//   waste two degrees of freedom on. Only THEN does `sleepPriorNight` fall back to the plain Pearson
//   auto-lag it used before FER-480 (`CorrelationEngine.pearson` on `CorrelationEngine.pairs`, raw n,
//   `pValue`, no midranks) — exactly the method `sleep`'s patternMethod footer already named for this
//   relationship, since FER-480 never updated it. Sparse but REAL training data (few quadruples yet
//   effort that varies) does NOT trip this: the calendar confound could still be operating over
//   whatever window is covered, so that case stays on the partial path and is hidden by the ordinary
//   `gate.minPairs` floor same as today, never silently downgraded to the simple correlation FER-480
//   introduced the partial specifically to correct.
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
// HRV — REVIVED here on the dense nocturnal RMSSD series (FER-472, gates /cso + /estadistico):
// • The FER-209 block read `avgHrv` (Apple's SDNN) through `SourceLens.clearBandHrv`, which nils it on
//   every Apple row — the series was always empty and the block never painted; FER-438 retired it. The
//   two `hrv.*` relationships below read a DIFFERENT series instead: the dense-night lnRMSSD the app
//   already recomputes from beat-to-beat intervals (`apple_rmssd_night`, `HealthKitBridge.ingestNocturnalHRV`,
//   day-keyed by the WAKING day), never `avgHrv`, never through `SourceLens`. RMSSD is right-skewed
//   (approximately lognormal), so the Pearson pair reads it in the natural-log domain — the same
//   transform `AutonomicTrend` already takes for its geometric-mean baseline; the Spearman pair is
//   rank-based and unaffected by the transform either way.
// • `hrv.sleepDuration` mirrors `rhr.sleepDuration` exactly: Pearson, lag 0, no partial. `hrv.priorStrain`
//   mirrors `rhr.priorStrain` exactly: Spearman, lag +1, first-order partial on the SAME day's strain —
//   the FER-438 fix, not FER-480's second-order one (that one is specific to the sleep auto-lag's
//   confound on BOTH ends of its own pair; this is an ordinary cross pair with the ordinary calendar
//   artefact on one end, y's day).
//
// RETIRED here (FER-438, gates /cso + /estadistico):
// • Prior-day strain → strain (FER-239 auto-lag): for a strain that is 0 on rest days its lag-1
//   autocorrelation is −π/(1−π) by construction — «lighter the day after» for everyone who does not
//   train two days running. It described the calendar, not the body.
// • Same-day recovery → strain (FER-239): `recovery` is nil on every Apple row; the driver never fired.
//
// KNOBS (product calibration, NOT derived from a publication — rotulados): `minPairs` 42 ≈ six weeks of
// paired days (a calendar floor, not an n_eff); `minPairsWithEfficiency` 56 because the wrist's
// sleep/wake reliability ≈ 0.5 attenuates any true r by ~√0.5, so a visible pattern needs more nights
// and the block flickers less; `minorityFloor` 10 (at n₁ = 10 of 42 a finding still needs d ≥ 0.71);
// `minAbsR` 0.20 is COSMETIC — below n ≈ 97 the p is the binding bar (|r| ≥ 0.30 at n = 42). The `hrv.*`
// pairs use the plain `minPairs` floor (42), not `minPairsWithEfficiency` — dense nights, not efficiency,
// gate their density, and a dense night already demands ≥ 60 clean beats / ≥ 30 successive pairs
// (`NocturnalHRV`), a stricter per-night bar than the wrist's sleep/wake call.
//
// SOURCES (verified by the /cso gate): Kredlow 2015, J Behav Med 38(3):427 (acute exercise → TST,
// efficiency, WASO); Atoui 2021, Sleep Med Rev 57:101426 (efficiency → next-day activity; activity →
// shorter TST, small); Lambiase 2013, Med Sci Sports Exerc 45(12):2362; Mead 2019, Int J Behav Med
// 26(5):562 (day-of-week confounds activity); Borbély 1982 / 2022, J Sleep Res 31(4):e13598 (process
// S — the night-to-night rebound); Dettoni 2012, J Appl Physiol 113(2):232 and Faust 2020, npj Digit
// Med 3:39 (short / late nights → resting HR up); Stanley 2013, Sports Med 43(12):1259 (parasympathetic
// reactivation 24–48 h after hard effort, cited for both `rhr.priorStrain` and `hrv.priorStrain`);
// Zhang 2025 (sleep loss moves RMSSD, not the all-day SDNN construct — why `hrv.sleepDuration` reads
// the dense-night RMSSD series and not `avgHrv`).

/// One relationship the block may assert: x moves, and the metric (y) tends to move with it.
public enum WhatMovesItRelationship: String, CaseIterable, Sendable {
    /// Yesterday's strain → tonight's sleep duration (lag +1, Spearman partial on today's strain).
    case sleepPriorStrain = "sleep.priorStrain"
    /// Last night's duration → tonight's (lag +1, Spearman partial of 2nd order on strain[D] AND
    /// strain[D+1]; the homeostatic rebound or the habit, net of the training calendar — FER-480).
    /// Falls back to a plain Pearson auto-lag when that control is degenerate — training effort is
    /// functionally absent over the window, so there is no calendar left to confound (FER-483).
    case sleepPriorNight = "sleep.priorNight"
    /// Last night's efficiency → today's strain (lag 0, Spearman).
    case strainEfficiency = "strain.efficiency"
    /// Yesterday's strain → tonight's efficiency (lag +1, Spearman partial on today's strain).
    case efficiencyPriorStrain = "efficiency.priorStrain"
    /// Last night's efficiency → today's steps (lag 0, Spearman; today's partial count excluded).
    case stepsEfficiency = "steps.efficiency"
    /// Last night's duration → resting HR (lag 0, Pearson).
    case rhrSleepDuration = "rhr.sleepDuration"
    /// Yesterday's strain → resting HR (lag +1, Spearman partial on today's strain).
    case rhrPriorStrain = "rhr.priorStrain"
    /// That same night's duration → its dense-night lnRMSSD (lag 0, Pearson) — the `rhr.sleepDuration`
    /// mirror, on the dense nocturnal RMSSD series, never `avgHrv` (FER-472).
    case hrvSleepDuration = "hrv.sleepDuration"
    /// Yesterday's strain → tonight's dense-night lnRMSSD (lag +1, Spearman partial on today's strain)
    /// — the `rhr.priorStrain` mirror (FER-472).
    case hrvPriorStrain = "hrv.priorStrain"

    /// The metric whose sheet renders the finding — the `y` side. Every key here is a
    /// `MetricInfo.id` / `MetricDetailSpec` key.
    public var metricKey: String {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight: return "sleep"
        case .strainEfficiency:                   return "strain"
        case .efficiencyPriorStrain:              return "sleep_efficiency"
        case .stepsEfficiency:                    return "steps"
        case .rhrSleepDuration, .rhrPriorStrain:  return "rhr"
        case .hrvSleepDuration, .hrvPriorStrain:  return "hrv"
        }
    }

    /// `spearmanPartial` is Spearman's ρ holding x on y's OWN day fixed (z = x[D + lag]) — the lag +1
    /// strain pairs (see the file note). `spearmanPartial2` holds `controlColumn` fixed on BOTH x's
    /// and y's day at once — `sleepPriorNight` today (FER-480).
    enum Statistic { case pearson, spearman, spearmanPartial, spearmanPartial2 }
    /// `hrv` is the dense-night lnRMSSD series (`apple_rmssd_night`, waking-day keyed), read in the
    /// natural-log domain — NEVER `DailyMetric.avgHrv` (Apple's all-day SDNN, the wrong construct;
    /// FER-438/FER-472) and never through `SourceLens`, which only ever touches `avgHrv`.
    enum Column { case sleepDuration, efficiency, strain, steps, restingHR, hrv }
    enum Side { case x, y }

    var x: Column {
        switch self {
        case .sleepPriorStrain, .efficiencyPriorStrain, .rhrPriorStrain, .hrvPriorStrain: return .strain
        case .sleepPriorNight, .rhrSleepDuration, .hrvSleepDuration:                      return .sleepDuration
        case .strainEfficiency, .stepsEfficiency:                                         return .efficiency
        }
    }

    var y: Column {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight:  return .sleepDuration
        case .strainEfficiency:                    return .strain
        case .efficiencyPriorStrain:               return .efficiency
        case .stepsEfficiency:                     return .steps
        case .rhrSleepDuration, .rhrPriorStrain:   return .restingHR
        case .hrvSleepDuration, .hrvPriorStrain:   return .hrv
        }
    }

    var lagDays: Int {
        switch self {
        case .sleepPriorStrain, .sleepPriorNight, .efficiencyPriorStrain, .rhrPriorStrain, .hrvPriorStrain: return 1
        case .strainEfficiency, .stepsEfficiency, .rhrSleepDuration, .hrvSleepDuration:                     return 0
        }
    }

    var statistic: Statistic {
        switch self {
        case .sleepPriorNight:                                           return .spearmanPartial2
        case .rhrSleepDuration, .hrvSleepDuration:                       return .pearson
        case .strainEfficiency, .stepsEfficiency:                        return .spearman
        case .sleepPriorStrain, .efficiencyPriorStrain, .rhrPriorStrain,
             .hrvPriorStrain:                                            return .spearmanPartial
        }
    }

    /// The series held fixed on both x's and y's day for `spearmanPartial2`; `nil` for every other
    /// statistic. `sleepPriorNight` controls on the day's effort (FER-480).
    var controlColumn: Column? { statistic == .spearmanPartial2 ? .strain : nil }

    /// Cross pairs (x and y are different columns) read p on n_eff; the auto-lag (x == y) does not
    /// (see the file note) — under H0 the series is white and its own ρ₁ IS the statistic, whether or
    /// not it is also read as a second-order partial. Only `sleepPriorNight` is an auto-lag today.
    var usesEffectiveN: Bool { x != y }

    /// Which side carries the zero-inflated strain series (minority-class floor), if any — the side
    /// whose column is `.strain`. `sleepPriorNight`'s CONTROL is strain too, but neither its x nor its
    /// y is, so it is not gated here — the floor only ever watches x/y, never a control.
    var zeroInflatedSide: Side? { x == .strain ? .x : (y == .strain ? .y : nil) }

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
    /// FER-483: minimum days with measurable (> 0) training effort, over `sleepPriorNight`'s own
    /// window, before its strain control counts as estimable. Below it (or at ~zero variance) the
    /// relationship falls back to the plain auto-lag correlation it used before FER-480 — see
    /// `WhatMovesItEngine.controlDegenerates` and the file note. 3 is a floor on the on/off RHYTHM
    /// the FER-480 artefact needs (≈ 2 sessions/week sustained over six-plus weeks reads ρ₁ ≈ −0.39);
    /// one or two isolated training days in that same window cannot manufacture a detectable
    /// alternation, so that reader is functionally the same population as someone who does not
    /// train — never the "trains rarely, on a real if thin schedule" population, which must stay
    /// hidden rather than fall back (a real, if sparse, calendar could still confound it).
    public var effortPresenceFloor: Int

    public init(minPairs: Int = 42, minPairsWithEfficiency: Int = 56, minorityFloor: Int = 10,
                minAbsR: Double = 0.20, maxQ: Double = 0.05, effortPresenceFloor: Int = 3) {
        self.minPairs = minPairs
        self.minPairsWithEfficiency = minPairsWithEfficiency
        self.minorityFloor = minorityFloor
        self.minAbsR = minAbsR
        self.maxQ = maxQ
        self.effortPresenceFloor = effortPresenceFloor
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
    /// Spearman's ρ (partial on the same-day strain for the lag +1 strain pairs; partial on strain[D]
    /// AND strain[D+1] for `sleepPriorNight`) or Pearson's r, per the relationship's statistic.
    public let r: Double
    /// Pairs used (triples on the order-1 partial pairs, quadruples on the order-2 one).
    public let n: Int
    /// Bartlett's n_eff for a cross pair; `Double(n)` for the auto-lag.
    public let nEffective: Double
    /// Two-sided p on `nEffective` (df = n_eff − 2; n_eff − 3 on the order-1 partial pairs; n_eff − 4
    /// on the order-2 one, `sleepPriorNight`).
    public let p: Double
    /// Benjamini-Hochberg q over the family of candidates computed together.
    public let q: Double
    /// FER-483: true only for `sleepPriorNight` when its strain control was degenerate and it fell
    /// back to the plain Pearson auto-lag (`r`/`n`/`p` are that fallback's, not the partial's). Always
    /// `false` for every other relationship, and for `sleepPriorNight` itself whenever the control was
    /// estimable. Exists for tests and any transparency surface, not for screen copy — the finding's
    /// sentence (`patron.sleep.priorNight.*`) does not change either way.
    public let usedSimpleFallback: Bool

    public var trend: MetricTrend { r >= 0 ? .rises : .falls }
}

public enum WhatMovesItEngine {

    /// Every testable relationship over `days`, computed in one pass with its BH q. `today` is the
    /// device's local day key: rows after it are ignored (a UTC «tomorrow» row), and today's own
    /// steps — a running total, not a finished day — are dropped from the steps pair. `hrvNights` is
    /// the dense-night RMSSD-per-night partition (`apple_rmssd_night`, waking-day keyed, raw
    /// milliseconds), read here in the natural-log domain for the two `hrv.*` pairs — NEVER
    /// `DailyMetric.avgHrv`; `[]` (the default) simply leaves both `hrv.*` relationships untestable,
    /// same as any other column with no data.
    public static func candidates(days: [DailyMetric], today: String,
                                  hrvNights: [(day: String, rmssdMs: Double)] = [],
                                  gate: WhatMovesItGate = .default) -> [WhatMovesItCandidate] {
        struct Tested {
            let relationship: WhatMovesItRelationship; let r: Double; let n: Int; let nEff: Double
            let p: Double; let usedSimpleFallback: Bool
        }
        var tested: [Tested] = []

        for relationship in WhatMovesItRelationship.allCases {
            let xs = series(days, relationship.x, today: today, hrvNights: hrvNights)
            let ys = series(days, relationship.y, today: today, hrvNights: hrvNights)
            let lag = relationship.lagDays
            // The partial pairs also need one (triples) or two (quadruples) controls read on the
            // same days the coefficient will use, so every floor below sees exactly those rows.
            let isPartial1 = relationship.statistic == .spearmanPartial
            let controls = relationship.controlColumn.map { series(days, $0, today: today, hrvNights: hrvNights) }
            // FER-483: a relationship that DECLARES `spearmanPartial2` only actually RUNS it when its
            // control is estimable over the relationship's own window (x's day range — `x == y` for
            // every `spearmanPartial2` relationship today, so `xs` already covers the whole span).
            // Degenerate → fall back to the plain Pearson auto-lag `sleepPriorNight` used before
            // FER-480, never to something new; see the file note and `controlDegenerates`.
            let declaresPartial2 = relationship.statistic == .spearmanPartial2
            let controlDegenerate = declaresPartial2 && controlDegenerates(
                valuesOn(controls ?? [], within: xs), floor: gate.effortPresenceFloor)
            let isPartial2 = declaresPartial2 && !controlDegenerate
            let usedSimpleFallback = declaresPartial2 && controlDegenerate

            let triples = isPartial1 ? CorrelationEngine.triples(x: xs, y: ys, z: xs, lagDays: lag) : []
            let quads = isPartial2 ? CorrelationEngine.quadruples(
                x: xs, y: ys, z1: controls ?? [], z2: controls ?? [], lagDays: lag) : []
            let pairs: [(Double, Double)]
            if isPartial1 { pairs = triples.map { ($0.0, $0.1) } }
            else if isPartial2 { pairs = quads.map { ($0.0, $0.1) } }
            else { pairs = CorrelationEngine.pairs(x: xs, y: ys, lagDays: lag) }
            guard pairs.count >= gate.minPairs(for: relationship) else { continue }

            if let side = relationship.zeroInflatedSide {
                let strainValues = pairs.map { side == .x ? $0.0 : $0.1 }
                let zeros = strainValues.filter { $0 == 0 }.count
                let positives = strainValues.filter { $0 > 0 }.count
                if zeros >= 1, min(zeros, positives) < gate.minorityFloor { continue }
            }

            let x = pairs.map { $0.0 }, y = pairs.map { $0.1 }
            let coefficient: (r: Double, n: Int)?
            switch relationship.statistic {
            case .pearson:          coefficient = CorrelationEngine.pearson(pairs).map { ($0.r, $0.n) }
            case .spearman:         coefficient = CorrelationEngine.spearman(pairs).map { ($0.r, $0.n) }
            case .spearmanPartial:  coefficient = CorrelationEngine.spearmanPartial(triples).map { ($0.r, $0.n) }
            case .spearmanPartial2: coefficient = isPartial2
                ? CorrelationEngine.spearmanPartial2(quads).map { ($0.r, $0.n) }
                : CorrelationEngine.pearson(pairs).map { ($0.r, $0.n) }   // FER-483 fallback
            }
            guard let c = coefficient else { continue }

            // n_eff is read on the ranks for a rank-based statistic, on the values for Pearson —
            // including the FER-483 fallback, which IS plain Pearson; the auto-lag reads raw n
            // either way (`pValue` on an integer n is exactly `Correlation.pApprox`) — see
            // `usesEffectiveN`.
            let ranked = relationship.statistic != .pearson && !usedSimpleFallback
            let ex = ranked ? CorrelationEngine.midranks(x) : x
            let ey = ranked ? CorrelationEngine.midranks(y) : y
            let nEff = relationship.usesEffectiveN ? CorrelationEngine.effectiveN(x: ex, y: ey) : Double(c.n)
            let p = isPartial1 ? CorrelationEngine.partialPValue(r: c.r, n: nEff)
                  : isPartial2 ? CorrelationEngine.partialPValue2(r: c.r, n: nEff)
                  : CorrelationEngine.pValue(r: c.r, n: nEff)
            tested.append(Tested(relationship: relationship, r: c.r, n: c.n, nEff: nEff, p: p,
                                 usedSimpleFallback: usedSimpleFallback))
        }

        let q = MultipleComparisons.benjaminiHochberg(tested.map(\.p))
        return zip(tested, q).map { t, q in
            WhatMovesItCandidate(relationship: t.relationship, r: t.r, n: t.n, nEffective: t.nEff, p: t.p,
                                 q: q, usedSimpleFallback: t.usedSimpleFallback)
        }
    }

    /// The findings that clear `gate`, by metric key (`sleep`, `strain`, `sleep_efficiency`, `steps`,
    /// `rhr`, `hrv`), each list in `WhatMovesItRelationship` order. A metric absent from the result — or
    /// with an empty list — has nothing to assert → the caller hides the block; it never invents a
    /// direction. `hrvNights` — see `candidates`.
    public static func family(days: [DailyMetric], today: String,
                              hrvNights: [(day: String, rmssdMs: Double)] = [],
                              gate: WhatMovesItGate = .default) -> [String: [WhatMovesItFinding]] {
        var out: [String: [WhatMovesItFinding]] = [:]
        for candidate in candidates(days: days, today: today, hrvNights: hrvNights, gate: gate)
        where candidate.q < gate.maxQ && abs(candidate.r) >= gate.minAbsR {
            out[candidate.relationship.metricKey, default: []]
                .append(WhatMovesItFinding(relationship: candidate.relationship, trend: candidate.trend))
        }
        return out
    }

    // MARK: - FER-483: the simple-correlation fallback for a degenerate `spearmanPartial2` control

    /// The values of `column` on exactly the days `xs` covers — the window a `spearmanPartial2`
    /// control must earn its keep over, BEFORE any lag join narrows it to whatever quadruples happen
    /// to survive. For every relationship that declares `spearmanPartial2` today, `x == y` (it is an
    /// auto-lag), so `xs` already spans the relationship's whole calendar range; a day missing from
    /// `column` here (no strain reading at all) simply drops out, exactly like every other join in
    /// this file. (FER-483)
    static func valuesOn(_ column: [(day: String, value: Double)],
                        within xs: [(day: String, value: Double)]) -> [Double] {
        let days = Set(xs.map(\.day))
        return column.filter { days.contains($0.day) }.map(\.value)
    }

    /// Whether a `spearmanPartial2` control is too sparse or too invariant to hold fixed — i.e.
    /// whether the training calendar it stands in for is functionally absent, so there is no
    /// confound left to guard against. `values` is `valuesOn(_:within:)`'s output (every strain
    /// reading available over the relationship's own window, unfiltered by pairing). Either trigger
    /// alone is enough:
    /// • fewer than `floor` days show ANY measurable effort (> 0) — see `WhatMovesItGate.
    ///   effortPresenceFloor` for why a small, fixed floor (not the pair count) is the right test:
    ///   a person who trains rarely but on a real schedule must stay on the partial path (and hidden
    ///   by the ordinary `minPairs` floor if that schedule is too sparse to hold fixed reliably),
    ///   never fall back to a simple correlation the calendar could still be confounding.
    /// • the measurable values have (numerically) zero variance — literally always the same number,
    ///   0 included. `spearmanPartial2` would already return `nil` here on its own (its internal
    ///   `pearson` calls need every variable to vary), so this makes that judgement EXPLICIT and
    ///   testable up front, instead of inferring "no signal" from a `nil` that could equally mean
    ///   too few quadruples — a case this function must NOT treat as degenerate (see above).
    static func controlDegenerates(_ values: [Double], floor: Int) -> Bool {
        let measurable = values.filter(\.isFinite)
        guard measurable.filter({ $0 > 0 }).count >= floor else { return true }
        let n = Double(measurable.count)
        let mean = measurable.reduce(0, +) / n
        let variance = measurable.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return variance < 1e-9
    }

    // MARK: - Internals

    /// One column's daily series, oldest → newest, rows after `today` dropped; the steps column also
    /// drops `today` itself (a partial running total). `.hrv` reads `hrvNights` instead of `days` —
    /// `ln(rmssdMs)`, never `DailyMetric.avgHrv` (see the file note) — so a `nil`/empty `days` row on a
    /// night that still emitted a dense RMSSD reading is not lost.
    private static func series(_ days: [DailyMetric], _ column: WhatMovesItRelationship.Column,
                               today: String,
                               hrvNights: [(day: String, rmssdMs: Double)]) -> [(day: String, value: Double)] {
        if column == .hrv {
            return hrvNights.compactMap { night -> (day: String, value: Double)? in
                guard night.day <= today, night.rmssdMs > 0 else { return nil }
                return (day: night.day, value: Foundation.log(night.rmssdMs))
            }
            .sorted { $0.day < $1.day }
        }
        return days.compactMap { d -> (day: String, value: Double)? in
            guard d.day <= today else { return nil }
            let value: Double?
            switch column {
            case .sleepDuration: value = d.totalSleepMin
            case .efficiency:    value = d.efficiency
            case .strain:        value = d.strain
            case .steps:         value = d.day < today ? d.steps.map(Double.init) : nil
            case .restingHR:     value = d.restingHr.map(Double.init)
            case .hrv:           value = nil  // unreachable — handled above
            }
            return value.map { (day: d.day, value: $0) }
        }
        .sorted { $0.day < $1.day }
    }
}
