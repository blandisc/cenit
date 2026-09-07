import Foundation
import StrandModels

// ReadinessEngine.swift — today's signals, and the training load behind them, read as one verdict.
//
// WHAT IT ANSWERS. Given the daily rows the app already stores, it reports where each signal sits
// against THIS person's own recent normal, where recent training load sits against their usual, and
// a single word for the two together. Pure and deterministic: no network, no stored state, no clock —
// «today» is an argument.
//
// THE SIGNALS, and the method behind each:
//
//   • HRV against the personal baseline — Plews et al. (2013), Sports Med 43(9):773-781, on
//     monitoring lnRMSSD relative to a person's own rolling normal rather than to a population.
//   • Resting-heart-rate drift — Buchheit (2014), Front Physiol 5:73, on resting, exercise and
//     recovery heart rate as training-status markers. A citation that is easy to get wrong here:
//     Lamberts et al. (2004) is about SUBMAXIMAL heart rate DURING exercise, which is a different
//     measurement; if it is ever cited, say so explicitly.
//   • Respiratory rate and skin temperature, each against the person's own nights.
//   • Acute:chronic training load — the 7-day and 28-day horizons of Gabbett (2016), Br J Sports Med
//     50:273-280.
//   • Training monotony — Foster (1998), Med Sci Sports Exerc 30(7):1164-1168: the week's mean load
//     divided by its standard deviation.
//
// THE LOAD RATIO DESCRIBES BALANCE. IT DOES NOT ANTICIPATE INJURY. This is a hard limit on what the
// engine and its copy may say, and there are two independent reasons for it:
//
//   1. The popular link between a «sweet spot» in this ratio and injury risk was never validated. It
//      is a widely repeated heuristic, not an established threshold (Lolli et al. 2019, BJSM).
//   2. Separately from what it might mean, the ratio's own construction forbids the reading: the
//      acute window is CONTAINED IN the chronic one, so the two are mathematically coupled and their
//      correlation with any outcome is inflated by that alone. Those statistical properties rule out
//      a causal interpretation regardless of the physiology (Impellizzeri et al. 2020, Int J Sports
//      Physiol Perform 15(6):907, and Br J Sports Med 54:1451-1462).
//
// So every sentence this file produces about load says where recent effort sits relative to usual
// effort, and stops there. No imperative about fatigue, no warning about getting hurt.
//
// NOT MEDICAL ADVICE, and not a diagnosis. These are descriptions of trends in a person's own data,
// nothing more.

public enum ReadinessEngine {

    /// The verdict, coarsest possible: five words for a whole morning.
    public enum Level: String, Sendable, Equatable {
        /// Signals aligned and load supported.
        case primed
        /// Nothing flagging.
        case balanced
        /// Something is flagging, but only one thing.
        case strained
        /// Several signals down at once.
        case rundown
        /// Not enough history to say anything honest.
        case insufficient
    }

    /// How one signal reads: its valence, never its direction.
    public enum Flag: String, Sendable, Equatable {
        case good, neutral, watch, bad

        /// The single place the σ cutoffs live: an oriented z (+ = better than baseline) → flag.
        /// Both the readiness signals and the recovery-summary «Qué la movió hoy» rows (FER-628) map
        /// through this, so a signal's state word can never disagree across surfaces.
        public init(orientedZ z: Double) {
            switch z {
            case 0.5...:        self = .good
            case -0.5..<0.5:    self = .neutral
            case -1.0 ..< -0.5: self = .watch
            default:            self = .bad
            }
        }
    }

    /// Why the verdict reads the way it does, as one small decision the UI turns into a single
    /// sentence. Kept separate from the copy so the *decision* is unit-testable without asserting
    /// localized strings.
    public enum BridgeKind: String, Sendable, Equatable {
        case aligned          // primed / balanced — nothing meaningfully flagging
        case strainedFlat     // strained — one thing is flagging
        case rundown          // several signals down at once
        case none             // insufficient history — no verdict to reconcile
    }

    /// The acute:chronic workload band, as a small named scale shared by every surface so the
    /// thresholds (0.8 / 1.3 / 1.5) live in exactly one place. The verdict hero shows `shortLabel`
    /// colored by `flag`; the signals list keeps the longer per-band sentence in `acwrSignal`.
    public enum LoadBand: String, Sendable, Equatable {
        case rampingDown   // < 0.8  — backing off, room to build
        case sweetSpot     // 0.8–1.3 — the productive band
        case buildingFast  // 1.3–1.5 — ramping hard
        case spiking       // ≥ 1.5  — load well above your usual; a context signal, not an injury claim

        /// Short, glanceable label for the verdict row. Localized against the host app catalog.
        /// FER-705 unified the band vocabulary: one plain direction word per band, shared by the
        /// verdict hero, «Your patterns», the Tendencias card and its explainer sheet.
        public var shortLabel: String {
            switch self {
            case .rampingDown:  return appLocalized("Easing off")
            case .sweetSpot:    return appLocalized("In balance")
            case .buildingFast: return appLocalized("Ramping up")
            case .spiking:      return appLocalized("Ramping fast")
            }
        }

        /// The flag color this band maps to — same mapping the `acwr` Signal uses.
        public var flag: Flag {
            switch self {
            case .sweetSpot:                  return .good
            case .rampingDown, .buildingFast: return .watch
            case .spiking:                    return .bad
            }
        }
    }

    /// One row of the morning read.
    public struct Signal: Sendable, Equatable {
        /// Stable identifier: `"hrv"` | `"rhr"` | `"respRate"` | `"skinTemp"` | `"acwr"` | `"monotony"`.
        public let key: String
        /// Localized name.
        public let label: String
        /// Localized sentence saying how this signal reads today.
        public let detail: String
        /// The valence of that reading.
        public let flag: Flag
        /// A compact, glanceable read-out of HOW FAR this signal sits from its personal baseline — the
        /// engine's own currency exposed for the instrument cluster's «Señales» row (FER-292 v2). Signed
        /// toward the raw direction (above baseline = `+`), independent of valence (the `flag` carries
        /// good/bad). σ for the z-scored body signals (HRV / resting-HR / respiratory rate), °C for skin
        /// temperature, the bare acute:chronic ratio for training load. Locale-neutral (σ, °C, a number),
        /// so it needs no catalog string. nil when there's nothing meaningful to quantify. Additive — the
        /// flag/level synthesis never reads it, so verdicts are unchanged.
        public let value: String?
        /// The same deviation as `value`, but as a raw signed number in σ (above baseline = `+`), for
        /// surfaces that need to POSITION it on an axis (the recovery «vs your base» bar), not just print
        /// it. Only the z-scored body signals (HRV / resting-HR / respiratory rate) carry it; nil for
        /// skin-temperature (°C, an asymmetric one-sided flag) and training load (a ratio, not a σ).
        /// Additive — the flag/level synthesis never reads it, so verdicts are unchanged. (FER-476)
        public let z: Double?
        public init(key: String, label: String, detail: String, flag: Flag, value: String? = nil, z: Double? = nil) {
            self.key = key; self.label = label; self.detail = detail; self.flag = flag
            self.value = value; self.z = z
        }
    }

    /// Everything the morning read produces.
    public struct Readiness: Sendable, Equatable {
        public let level: Level
        /// Localized verdict word.
        public let headline: String
        /// Localized sentence under it.
        public let summary: String
        /// The signals that could be computed today, in the order they were considered.
        public let signals: [Signal]
        /// The acute:chronic load ratio, or `nil` when the emission gate did not pass.
        public let acwr: Double?
        /// Foster monotony over the trailing calendar week, or `nil`.
        public let monotony: Double?
        /// True when last night's sleep ran short enough to undermine the morning's HRV/recovery read
        /// — the verdict still stands, but surfaces should flag it (caveat line + "Low conf" on HRV)
        /// rather than present it as high-confidence. Additive; defaults to false for existing callers.
        public let confidenceLow: Bool
        /// A localized one-liner explaining `confidenceLow` (nil when confidence is normal).
        public let confidenceNote: String?
        /// Why the verdict reads the way it does — the testable decision behind `bridge`.
        public let bridgeKind: BridgeKind
        /// A localized one-liner restating the verdict for the user. nil only for `.none`.
        public let bridge: String?
        /// Short localized noun for what's behind the verdict, for the verdict card sublabel
        /// ("from your training load"). nil when nothing is to blame (aligned / insufficient).
        public let culpritNoun: String?

        /// The defaults on the last five are CONTRACT: call sites build this without them.
        public init(level: Level, headline: String, summary: String,
                    signals: [Signal], acwr: Double?, monotony: Double?,
                    confidenceLow: Bool = false, confidenceNote: String? = nil,
                    bridgeKind: BridgeKind = .none, bridge: String? = nil,
                    culpritNoun: String? = nil) {
            self.level = level; self.headline = headline; self.summary = summary
            self.signals = signals; self.acwr = acwr; self.monotony = monotony
            self.confidenceLow = confidenceLow; self.confidenceNote = confidenceNote
            self.bridgeKind = bridgeKind; self.bridge = bridge
            self.culpritNoun = culpritNoun
        }

        /// The training-load band for this read, derived from `acwr` (nil when there's no load yet).
        /// Surfaces show `loadBand?.shortLabel` instead of a raw ratio the user can't interpret.
        public var loadBand: LoadBand? { acwr.map(ReadinessEngine.loadBand(forACWR:)) }
    }

    // MARK: - Windows
    //
    // The two load horizons are METHOD (Gabbett 2016). The other three are RECALIBRATABLE, each with
    // its own criterion.

    /// Nights of history a personal baseline is folded over. Criterion: enough nights for a stable
    /// centre and spread, without dragging a whole season into today's comparison.
    private static let baselineWindow = 30
    /// Fewest valid nights before a z-score is trusted at all. Criterion: below this a sample standard
    /// deviation is noise, and a flag raised on it would be noise too.
    private static let minBaseline = 7
    /// Acute load horizon, days.
    private static let acuteWindow = 7
    /// Chronic load horizon, days.
    private static let chronicWindow = 28
    /// Days of load history before a ratio may be emitted. Criterion: half the chronic horizon.
    private static let minChronic = 14

    /// Coupled EWMA time-constants (Williams et al. 2017): λ = 2/(N+1) over the same
    /// acute (7) / chronic (28) horizons the old rigid means used.
    private static let lambdaAcute: Double   = 2.0 / (Double(acuteWindow) + 1)     // 2/8  = 0.25
    private static let lambdaChronic: Double = 2.0 / (Double(chronicWindow) + 1)   // 2/29 ≈ 0.0689655
    /// Piso NUEVO (FER — «CARGA VIVA»): días REALES con carga (`load`, strain>0) dentro de la ventana
    /// crónica (28 días calendario) que deben existir antes de emitir un ACWR — evita que 14 días de
    /// puros ceros (zero-fill) trivialicen `minChronic` y produzcan un ACWR/spike espurio. Punto de
    /// calibración de `/estadistico`.
    private static let minActiveDays = 4
    /// Below this much sleep last night the morning read is flagged low-confidence (a short night
    /// suppresses HRV and inflates resting HR independent of true recovery). 6 hours.
    private static let shortNightMinutes: Double = 360
    // Respiratory-rate plausibility + thresholds (FER-675). The nightly RR is RSA-derived and
    // noisy; an implausible estimate scored against a tight baseline SD would fabricate a spurious
    // `.bad` and flip the verdict to RUNDOWN. Both today's value and the baseline samples are gated
    // to this plausible sleeping-RR band before any z is computed. The z cutoffs are deliberately
    // SEPARATE from — and wider than — the HRV/RHR 0.5σ `Flag(orientedZ:)` cutoffs: an illness RR
    // drift is a larger, later move, so a `.watch`/`.bad` needs a full 1σ/1.5σ rise.
    private static let respPlausibleMin: Double = 8
    private static let respPlausibleMax: Double = 25
    private static let respWatchZ: Double = 1.0
    private static let respBadZ: Double = 1.5

    // MARK: - The read

    /// Today's readiness from the daily rows.
    ///
    /// `today` names the row to read, and when it is given the match must be EXACT. A stale import
    /// must not be able to synthesize a morning read out of whichever row happens to be newest — that
    /// row could be months old. With no `today`, the most recent row is used.
    ///
    /// Signals are appended in a fixed order — HRV, resting heart rate, breathing, skin temperature,
    /// then load and monotony — and that order matters downstream: the reconciliation takes the FIRST
    /// worst-flagged signal as the natural culprit.
    public static func evaluate(days: [DailyMetric], today: String? = nil) -> Readiness {
        let sorted = days.sorted { $0.day < $1.day }
        let latestRow: DailyMetric?
        if let today {
            latestRow = sorted.last { $0.day == today }
        } else {
            latestRow = sorted.last
        }
        guard let latest = latestRow else {
            return Readiness(level: .insufficient,
                             headline: appLocalized("Readiness"),
                             summary: appLocalized("A few more nights of data and your readiness read will sharpen."),
                             signals: [], acwr: nil, monotony: nil)
        }
        let history = sorted.filter { $0.day < latest.day }

        var signals: [Signal] = []
        var acwr: Double?
        var monotony: Double?

        if let s = zSignal(
            value: latest.avgHrv,
            history: history.map { $0.avgHrv }, cfg: Baselines.hrvCfg,
            higherIsBetter: true,
            key: "hrv", label: appLocalized("HRV"),
            goodText: appLocalized("above your baseline — well recovered"),
            neutralText: appLocalized("in your normal range"),
            watchText: appLocalized("slightly below your usual"),
            badText: appLocalized("suppressed — a sign of autonomic fatigue")) {
            signals.append(s)
        }

        if let s = zSignal(
            value: latest.restingHr.map(Double.init),
            history: history.map { $0.restingHr.map(Double.init) }, cfg: Baselines.restingHRCfg,
            higherIsBetter: false,
            key: "rhr", label: appLocalized("Resting HR"),
            goodText: appLocalized("at or below baseline"),
            neutralText: appLocalized("in your normal range"),
            watchText: appLocalized("running a little high"),
            badText: appLocalized("elevated — overtraining or illness can do this")) {
            signals.append(s)
        }

        // Plausibility gate (8–25 bpm): a noisy RSA-derived RR outside the physiological sleeping
        // band must produce NO signal, so it can't fabricate a spurious `.bad` and flip the verdict
        // to RUNDOWN (FER-675). Today's value and the baseline samples are both gated.
        let respBand = respPlausibleMin...respPlausibleMax
        if let rr = latest.respRateBpm, respBand.contains(rr) {
            let base = history.suffix(baselineWindow).compactMap { $0.respRateBpm }.filter(respBand.contains)
            if base.count >= minBaseline, let m = mean(base), let sd = sampleSD(base), sd > 0 {
                let z = (rr - m) / sd
                if z >= respBadZ {
                    signals.append(Signal(key: "respRate", label: appLocalized("Respiratory rate"),
                        detail: appLocalized("up vs baseline — sometimes an early sign of getting sick"),
                        flag: .bad, value: String(format: "%+.1fσ", z), z: z))
                } else if z >= respWatchZ {
                    signals.append(Signal(key: "respRate", label: appLocalized("Respiratory rate"),
                        detail: appLocalized("slightly raised vs baseline"),
                        flag: .watch, value: String(format: "%+.1fσ", z), z: z))
                }
            }
        }

        // Skin-temperature rise (illness / overreaching early signal) --------
        // skinTempDevC is already baseline-normalized (°C above the personal mean);
        // a sustained rise is a classic early illness marker (Oura uses ~+0.5 °C).
        if let dev = latest.skinTempDevC {
            if dev >= 0.8 {
                signals.append(Signal(key: "skinTemp", label: appLocalized("Skin temperature"),
                    detail: appLocalized("well above baseline — often an early sign of illness"),
                    flag: .bad, value: String(format: "%+.1f °C", dev)))
            } else if dev >= 0.4 {
                signals.append(Signal(key: "skinTemp", label: appLocalized("Skin temperature"),
                    detail: appLocalized("running warm vs baseline"),
                    flag: .watch, value: String(format: "%+.1f °C", dev)))
            }
        }

        // Coupled EWMA over the EXPLICIT calendar-day sequence (Williams 2017),
        // computed on TRIMP-like LINEAR load via strainToLoad so a spike reads as
        // a spike. rest(0) folds/decays the acute leg; missing (nil strain) holds.
        // Gate: coverageDays ≥ minChronic AND activeInWindow ≥ minActiveDays AND chronic > 0
        // — so 14 pure-rest zeros never emit a ratio.
        let replay = ewmaReplay(sorted)
        if let point = replay.points.first(where: { $0.day == latest.day }), gatePasses(point) {
            let ratio = point.acute / point.chronic
            acwr = ratio
            signals.append(acwrSignal(ratio: ratio))

            // Foster (1998) monotony over the calendar week that ends today. A rest day counts as a
            // zero — a week of unrelenting work is precisely what the ratio exists to expose — while a
            // day with no reading at all is skipped rather than imputed. The window is a literal
            // calendar week: when days are missing it simply carries fewer values, and it never
            // reaches further back to top the count up, which would quietly measure this week
            // against an older one.
            if let weekly = weeklyMonotony(endingOn: latest.day, replay: replay) {
                monotony = weekly.value
                if let signal = weekly.signal { signals.append(signal) }
            }
        }

        let (level, headline, summary) = synthesize(signals: signals, history: history)

        // Confidence: a short night suppresses HRV / lifts resting HR regardless of true recovery,
        // so the morning read is honestly flagged low-confidence (drives the verdict caveat + the
        // "Low conf" chip on HRV). Only claimed when we actually have last night's sleep duration.
        let confidenceLow = (latest.totalSleepMin ?? .greatestFiniteMagnitude) < Self.shortNightMinutes
        let confidenceNote = confidenceLow
            ? appLocalized("Based on a short night — confidence low.")
            : nil

        // Name the one signal most responsible for the verdict, decide the sentence in one place
        // (testable), then localize it.
        let lead = leadSignal(signals)
        let kind = bridgeKind(level: level, lead: lead)
        return Readiness(level: level, headline: headline, summary: summary,
                         signals: signals, acwr: acwr, monotony: monotony,
                         confidenceLow: confidenceLow, confidenceNote: confidenceNote,
                         bridgeKind: kind, bridge: bridgeCopy(kind, lead: lead),
                         culpritNoun: verdictCulprit(kind: kind, lead: lead))
    }

    // MARK: - Signals

    /// Build a z-score signal for a metric, scored against the SAME robust EWMA baseline (winsorized
    /// centre + abs-dev spread) the rest of the package consumes — so two surfaces can never tell
    /// different stories about the same HRV / resting-HR night. `history` is the ordered nightly series
    /// before today (oldest → newest), with nils for missing nights (skip-and-hold).
    ///
    /// `nil` when there is no value, or no baseline solid enough to compare against.
    ///
    /// The dissociation between the printed number and the flag is DELIBERATE and is screen contract:
    /// `value` and `z` carry the UNORIENTED deviation (above baseline is `+`, whatever that means for
    /// the metric), while the flag carries valence. A high resting heart rate therefore reads «+1.2σ»
    /// with a warning dot, and a high HRV reads «+1.4σ» with a good one. Do not «fix» this by
    /// orienting the number: the number is direction, the dot is valence.
    private static func zSignal(value: Double?, history: [Double?], cfg: MetricCfg,
                                higherIsBetter: Bool, key: String, label: String,
                                goodText: String, neutralText: String,
                                watchText: String, badText: String) -> Signal? {
        guard let v = value else { return nil }
        let state = Baselines.foldHistory(Array(history.suffix(baselineWindow)), cfg: cfg)
        guard state.nValid >= minBaseline, state.spread > 0 else { return nil }
        // deviation.z = (value − baseline) / (1.253 × spread); orient so positive
        // always means "better" (invert for lower-is-better metrics like resting HR).
        let dev = Baselines.deviation(v, state: state)
        // Shrink toward neutral when the baseline is thin (FER-13), so a flag isn't
        // raised on weak evidence; a trusted baseline (≥ minNightsTrust) is unshrunk.
        let z = (higherIsBetter ? dev.z : -dev.z) * Baselines.confidence(nValid: state.nValid)
        let flag = Flag(orientedZ: z)
        let text: String
        switch flag {
        case .good:    text = goodText
        case .neutral: text = neutralText
        case .watch:   text = watchText
        case .bad:     text = badText
        }
        let valueText = String(format: "%+.1fσ", dev.z)
        return Signal(key: key, label: label, detail: text, flag: flag, value: valueText, z: dev.z)
    }

    // MARK: - Load

    /// The acute:chronic thresholds, public so UI scales (the Tendencias sheet's band bar and the
    /// mini-trend's shaded balance zone, FER-705) draw the SAME numbers `loadBand` cuts on and can
    /// never drift from the engine.
    public static let acwrSweetSpotLow  = 0.8
    public static let acwrSweetSpotHigh = 1.3
    public static let acwrSpikeAt       = 1.5

    /// The one place the acute:chronic thresholds live. `acwrSignal` and `Readiness.loadBand`
    /// both route through this, so the verdict word and the signal sentence can never disagree.
    public static func loadBand(forACWR ratio: Double) -> LoadBand {
        switch ratio {
        case ..<acwrSweetSpotLow:                  return .rampingDown
        case acwrSweetSpotLow..<acwrSweetSpotHigh: return .sweetSpot
        case acwrSweetSpotHigh..<acwrSpikeAt:      return .buildingFast
        default:                                   return .spiking
        }
    }

    /// The acute:chronic ratio recomputed for each of the last `lastN` calendar days that clear the
    /// emission gate — the series behind the Tendencias «Training load» card's mini-trend (FER-705).
    /// Pure input→output: the SAME coupled-EWMA replay `evaluate` runs for today's `acwr`
    /// (Williams et al. 2017, Br J Sports Med 51:209; horizons still Gabbett 2016). When today
    /// clears the emission gate the last point equals today's `evaluate().acwr`; when today FAILS
    /// the gate (e.g. fewer than `minActiveDays` active days in the window) `evaluate().acwr` is nil
    /// and this series simply ends at the most recent day that did pass — the card is hidden on a nil
    /// read, so the two never disagree on screen. Days that fail coverage / active-days / chronic>0
    /// are skipped; `days` may be in any order. Descriptive context only, never an injury predictor
    /// (Impellizzeri et al. 2020).
    public static func acwrSeries(days: [DailyMetric], lastN: Int = 28) -> [(day: String, ratio: Double)] {
        let sorted = days.sorted { $0.day < $1.day }
        let points = ewmaReplay(sorted).points
        let gated = points.filter(gatePasses).map { (day: $0.day, ratio: $0.acute / $0.chronic) }
        return Array(gated.suffix(lastN))
    }

    // MARK: Coupled EWMA replay (Williams 2017 — shared by evaluate + acwrSeries)

    /// One day of the coupled-EWMA replay.
    struct EwmaPoint: Equatable {
        let day: String
        let acute: Double
        let chronic: Double
        /// Cumulative count of KNOWN days (rest OR load — i.e. `DailyMetric.strain != nil`) from the
        /// first known day through this one. Mirrors the old `strainSeries.count` gate exactly.
        let coverageDays: Int
        /// Count of `load` (strain > 0) days within the trailing `chronicWindow` (28) CALENDAR days
        /// ending on this day (a sliding window over calendar days, not over known-days — so it can
        /// go back to zero if a user stops logging workouts long enough for old active days to age out).
        let activeInWindow: Int
    }

    /// Replay result: points + the day→row lookup monotony reuses (no second pass).
    private struct EwmaReplay {
        let points: [EwmaPoint]
        let rowByDay: [String: DailyMetric]
    }

    /// Build the EXPLICIT calendar-day sequence spanning `sorted.first.day...sorted.last.day`
    /// (`sorted` already day-ascending), replaying the coupled EWMA once, O(n). A calendar day with NO
    /// row in `sorted`, or a row whose `strain == nil`, is `.missing` — held (no fold, no coverage
    /// increment). A row with `strain == 0` is `.rest` — folds as 0 (decays the acute leg). A row with
    /// `strain > 0` is `.load` — folds at its `strainToLoad` value AND counts toward `activeInWindow`.
    /// Seeds both EWMA legs directly (no recurrence) at the FIRST known day; emits a point for every
    /// calendar day from that first known day onward (days before the first known day are skipped
    /// entirely — nothing to seed from).
    private static func ewmaReplay(_ sorted: [DailyMetric]) -> EwmaReplay {
        guard let firstDay = sorted.first?.day, let lastDay = sorted.last?.day,
              let start = DayKey.parseUTC(firstDay), let end = DayKey.parseUTC(lastDay) else {
            return EwmaReplay(points: [], rowByDay: [:])
        }
        var rowByDay: [String: DailyMetric] = [:]
        for d in sorted { rowByDay[d.day] = d }   // day is a natural key; last-writer-wins is harmless

        var calendarDays: [String] = []
        var cursor = start
        while cursor <= end {
            calendarDays.append(DayKey.utc(cursor))
            guard let next = DayKey.utcCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var points: [EwmaPoint] = []
        var acute = 0.0, chronic = 0.0
        var seeded = false
        var coverageDays = 0
        var recentActive: [Bool] = []   // trailing `chronicWindow` calendar days, oldest first

        for day in calendarDays {
            let load: Double? = rowByDay[day]?.strain.map(strainToLoad)   // nil ⇒ missing
            recentActive.append(load.map { $0 > 0 } ?? false)
            if recentActive.count > chronicWindow { recentActive.removeFirst() }

            if let load {
                if !seeded { acute = load; chronic = load; seeded = true }
                else {
                    acute   = load * lambdaAcute   + acute   * (1 - lambdaAcute)
                    chronic = load * lambdaChronic + chronic * (1 - lambdaChronic)
                }
                coverageDays += 1
            }
            if seeded {
                points.append(EwmaPoint(day: day, acute: acute, chronic: chronic,
                                        coverageDays: coverageDays,
                                        activeInWindow: recentActive.filter { $0 }.count))
            }
        }
        return EwmaReplay(points: points, rowByDay: rowByDay)
    }

    /// Whether a point clears the emission gate: enough coverage history, enough REAL active days in
    /// the trailing chronic window (the zero-fill piso), and a non-zero chronic denominator.
    private static func gatePasses(_ p: EwmaPoint) -> Bool {
        p.coverageDays >= minChronic && p.activeInWindow >= minActiveDays && p.chronic > 0
    }

    /// The load signal. `value` is the BARE ratio to ONE decimal — no σ, because load is already a
    /// normalized ratio rather than a deviation from a baseline — while the sentence glosses it to TWO.
    static func acwrSignal(ratio: Double) -> Signal {
        let label = appLocalized("Training load")
        let band = loadBand(forACWR: ratio)
        let value = String(format: "%.1f", ratio)
        let pct = String(format: "%.2f", ratio)
        // Copy is PURELY DESCRIPTIVE of the acute↔chronic relationship — no injury-risk imperative
        // ("watch fatigue", "ease off"): Impellizzeri et al. 2020 (Br J Sports Med 54:1451–1462) show the
        // ACWR does NOT predict injury, so the sentence states where your recent load sits vs your usual,
        // nothing more. See docs/ANALYTICS.md (Training Stress Balance). FER-705 de-jargoned the face:
        // the band word + the glossed ratio lead; "acute:chronic (ACWR)" lives only in the ⓘ/method.
        switch band {
        case .rampingDown:
            return Signal(key: "acwr", label: label,
                detail: appLocalized("easing off (\(pct)) — recent load below your usual"), flag: band.flag, value: value)
        case .sweetSpot:
            return Signal(key: "acwr", label: label,
                detail: appLocalized("in balance (\(pct)) — recent load in line with your usual"), flag: band.flag, value: value)
        case .buildingFast:
            return Signal(key: "acwr", label: label,
                detail: appLocalized("ramping up (\(pct)) — recent load above your usual"), flag: band.flag, value: value)
        case .spiking:
            return Signal(key: "acwr", label: label,
                detail: appLocalized("ramping fast (\(pct)) — recent load well above your usual"), flag: band.flag, value: value)
        }
    }

    // MARK: - Monotony
    //
    // Foster (1998): the week's mean load over its standard deviation. Both knobs are RECALIBRATABLE.
    // The watch threshold is the value usually cited alongside the method — a high monotony is
    // associated with more strain and more illness. The four-value minimum is there because a sample
    // standard deviation over fewer observations is too unstable to raise anything on.

    private static let monotonyWatchAt: Double = 2.0
    private static let monotonyMinDays = 4

    // MARK: - Verdict

    /// The verdict, from the flags alone. Evaluated in this order, and the order IS the definition.
    ///
    /// The set of keys that count as «the body» INCLUDES skin temperature.
    private static func synthesize(signals: [Signal], history: [DailyMetric]) -> (Level, String, String) {
        guard !signals.isEmpty, !history.isEmpty else {
            return (.insufficient, appLocalized("Readiness"),
                    appLocalized("A few more nights of data and your readiness read will sharpen."))
        }
        let recoveryDown = signals.contains { ["hrv", "rhr", "respRate", "skinTemp"].contains($0.key) && ($0.flag == .bad) }
        let loadHigh = signals.contains { $0.key == "acwr" && $0.flag == .bad }
        let badCount = signals.filter { $0.flag == .bad }.count
        let goodCount = signals.filter { $0.flag == .good }.count
        let anyWatch = signals.contains { $0.flag == .watch }

        if badCount >= 2 || (recoveryDown && loadHigh) {
            return (.rundown, appLocalized("Run down"),
                    appLocalized("Several signals are down at once. Treat today as recovery — easy movement, real sleep tonight."))
        }
        if recoveryDown || loadHigh || badCount >= 1 {
            return (.strained, appLocalized("Strained"),
                    appLocalized("One of your signals is flagging. You can train, but keep it controlled and bank the recovery."))
        }
        if goodCount >= 2 && !anyWatch {
            return (.primed, appLocalized("Primed"),
                    appLocalized("Your signals are aligned and your load is supported. A harder session is well backed today."))
        }
        return (.balanced, appLocalized("Balanced"),
                appLocalized("Nothing's flagging. Train to feel — your body's holding steady."))
    }

    // MARK: Naming what drove the verdict

    /// The single signal most responsible for the verdict, for the reconciling sentence: the
    /// worst-flagged one (`.bad` before `.watch`), taken in append order so the first match is the
    /// natural culprit. nil when nothing is flagging.
    static func leadSignal(_ signals: [Signal]) -> Signal? {
        signals.first { $0.flag == .bad } ?? signals.first { $0.flag == .watch }
    }

    /// The sentence decision (pure, deterministic, testable): a straight restatement of the verdict,
    /// since the verdict is the only thing there is to reconcile.
    static func bridgeKind(level: Level, lead: Signal?) -> BridgeKind {
        switch level {
        case .insufficient:      return .none
        case .primed, .balanced: return .aligned
        case .rundown:           return .rundown
        case .strained:          return .strainedFlat
        }
    }

    /// Possessive noun for a signal, for the verdict card's sublabel ("from {your training load}").
    /// One source so every surface agrees.
    private static func signalNoun(_ key: String) -> String {
        switch key {
        case "acwr":     return appLocalized("your training load")
        case "hrv":      return appLocalized("your HRV")
        case "rhr":      return appLocalized("your resting heart rate")
        case "skinTemp": return appLocalized("your skin temperature")
        case "respRate": return appLocalized("your breathing")
        default:         return appLocalized("one of your signals")
        }
    }

    /// Short noun for the culprit behind the verdict, for the verdict card's sublabel
    /// ("Strained · from your training load"). nil when there's nothing to blame (aligned / none).
    static func verdictCulprit(kind: BridgeKind, lead: Signal?) -> String? {
        switch kind {
        case .none, .aligned:
            return nil
        case .rundown:
            return appLocalized("several signals")
        case .strainedFlat:
            return lead.map { signalNoun($0.key) }
        }
    }

    /// The localized sentence for a verdict decision (nil only for `.none`).
    static func bridgeCopy(_ kind: BridgeKind, lead: Signal?) -> String? {
        switch kind {
        case .none:
            return nil
        case .aligned:
            return appLocalized("Your signals are aligned and your load is supported. A harder session is well backed today.")
        case .rundown:
            return appLocalized("Several signals are down at once. Treat today as recovery.")
        case .strainedFlat:
            return appLocalized("One of your signals is flagging. You can train, but keep it controlled.")
        }
    }

    // MARK: - Small statistics

    /// Arithmetic mean; `nil` for an empty set, which has no mean to report.
    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (`n − 1`); `nil` with fewer than two values, which is when the
    /// denominator has nothing to divide by.
    static func sampleSD(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        var ss = 0.0
        for x in xs {
            let d = x - m
            ss += d * d
        }
        return (ss / Double(xs.count - 1)).squareRoot()
    }

    /// Foster (1998) monotony for the calendar week ending on `day`: the mean daily dose divided by
    /// its sample spread, both taken over the linearized load so a spike reads as a spike. Answers
    /// `nil` when the week carries too few readings for a sample spread to mean anything, or when
    /// the dose never varies at all and the ratio has no denominator. The value is reported on its
    /// own; the signal rides along only once the ratio reaches the watch threshold.
    private static func weeklyMonotony(endingOn day: String,
                                       replay: EwmaReplay) -> (value: Double, signal: Signal?)? {
        guard let lastDay = DayKey.parseUTC(day) else { return nil }
        var loads: [Double] = []
        var cursor = lastDay
        for _ in 0..<acuteWindow {
            if let strain = replay.rowByDay[DayKey.utc(cursor)]?.strain {
                loads.append(strainToLoad(strain))
            }
            guard let previousDay = DayKey.utcCalendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previousDay
        }
        guard loads.count >= monotonyMinDays,
              let spread = sampleSD(loads), spread > 0,
              let average = mean(loads)
        else { return nil }
        let ratio = average / spread
        guard ratio >= monotonyWatchAt else { return (ratio, nil) }
        return (ratio, Signal(key: "monotony",
                              label: appLocalized("Training variety"),
                              detail: appLocalized("low — similar strain every day raises strain/illness risk"),
                              flag: .watch,
                              value: String(format: "%.1f", ratio)))
    }

    /// Linearize a 0–21 logarithmic strain back to a TRIMP-like load (the inverse
    /// of StrainScorer's `21·ln(TRIMP+1)/ln(D)` map) so ACWR and monotony run on a
    /// dose linear in physiological load. For imported strains on a comparable 0–21
    /// log scale this is a consistent linearization, not an exact TRIMP recovery.
    /// Forwards to `StrainScorer.strainToTrimp` — the ONE copy of the inverse (ola 1 · E2 made it
    /// public so the session-RPE overlay adds loads on the same axis). Numerically unchanged.
    static func strainToLoad(_ strain: Double) -> Double {
        StrainScorer.strainToTrimp(strain)
    }
}
