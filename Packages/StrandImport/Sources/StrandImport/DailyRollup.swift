import Foundation

// MARK: - Day reduction (FER-382)
//
// One export becomes one row per civil day. The reduction is INCREMENTAL by construction:
// a record is folded into its day the moment it is read and then forgotten, so memory grows
// with the number of days (thousands) and never with the number of records (tens of
// millions). Everything the streaming importer and the pure helpers below need is here, in
// ONE place — two implementations of "the mean of a day" would eventually disagree, and the
// user's history would quietly split in half.

// MARK: - HealthKit identifiers

enum HealthTypeName {

    /// The identifier prefixes Apple puts in front of every type name in an export.
    /// The first one that matches is removed; none is a prefix of another, so order is
    /// irrelevant. `AlreadyClean` comes back unchanged.
    private static let prefixes = [
        "HKQuantityTypeIdentifier",
        "HKCategoryTypeIdentifier",
        "HKDataTypeIdentifier",
        "HKWorkoutActivityType",
    ]

    static func stripped(_ identifier: String) -> String {
        for prefix in prefixes where identifier.hasPrefix(prefix) {
            return String(identifier.dropFirst(prefix.count))
        }
        return identifier
    }
}

/// The quantity readings that reach a field of the daily row. Types outside this list are
/// still legitimate (`BodyTemperature` is imported and counted) — they simply have nowhere
/// to land yet, so they create the day and leave it empty.
private enum ReadingKind {
    case restingHr, hrv, respRate, walkingHr, spo2
    case heartRate
    case steps, activeKcal, basalKcal
    case vo2max, weight, leanMass, bodyFat, bmi

    /// Accepts the prefix-free name; the caller strips first, so `HeartRate` and
    /// `HKQuantityTypeIdentifierHeartRate` reduce identically.
    init?(strippedType: String) {
        switch strippedType {
        case "RestingHeartRate":          self = .restingHr
        case "HeartRateVariabilitySDNN":  self = .hrv
        case "RespiratoryRate":           self = .respRate
        case "WalkingHeartRateAverage":   self = .walkingHr
        case "OxygenSaturation":          self = .spo2
        case "HeartRate":                 self = .heartRate
        case "StepCount":                 self = .steps
        case "ActiveEnergyBurned":        self = .activeKcal
        case "BasalEnergyBurned":         self = .basalKcal
        case "VO2Max":                    self = .vo2max
        case "BodyMass":                  self = .weight
        case "LeanBodyMass":              self = .leanMass
        case "BodyFatPercentage":         self = .bodyFat
        case "BodyMassIndex":             self = .bmi
        default:                          return nil
        }
    }
}

// MARK: - Constant-space accumulators

/// A running mean. `nil` until the day has seen at least one reading.
private struct RunningMean {
    private var total = 0.0
    private var count = 0

    mutating func add(_ value: Double) {
        total += value
        count += 1
    }

    var value: Double? { count == 0 ? nil : total / Double(count) }
}

/// A running sum. Stays `nil` for a day with no reading of that type, so "zero steps" and
/// "no step data" never collapse into the same number.
private struct RunningTotal {
    private(set) var value: Double?

    mutating func add(_ amount: Double) {
        value = (value ?? 0) + amount
    }
}

/// A per-source daily total for CUMULATIVE quantities (steps, active/basal energy). FER-411: the
/// export often carries the same day recorded by BOTH the iPhone and the Apple Watch; summing across
/// sources double-counts. This mirrors the live path's `HKStatisticsCollectionQuery` (without
/// `.separateBySource`), which dedupes cumulative types by source: we sub-total per source and, on
/// read, keep the SINGLE largest-contributing source of the day — never the sum across sources. A
/// nil/absent source folds into one bucket (key ""), so an export without `sourceName` behaves exactly
/// like a single source (back-compat: values still add up within that one bucket). `nil` until the day
/// has any reading, so "zero" and "no data" stay distinct.
private struct SourcedTotal {
    private var bySource: [String: Double] = [:]

    mutating func add(_ amount: Double, source: String?) {
        bySource[source ?? "", default: 0] += amount
    }

    /// The largest single-source total; ties broken deterministically by the lexicographically smaller
    /// source key so the result never depends on record order.
    var value: Double? {
        bySource.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.value
    }
}

/// A running maximum.
private struct RunningMax {
    private(set) var value: Double?

    mutating func offer(_ candidate: Double) {
        if let current = value, current >= candidate { return }
        value = candidate
    }
}

/// The last reading of the day, by `end`. An exact tie is won by whichever arrived last.
private struct LatestOfDay {
    private(set) var value: Double?
    private var at: Date?

    mutating func offer(_ candidate: Double, at instant: Date) {
        if let current = at, instant < current { return }
        value = candidate
        at = instant
    }
}

/// Everything one civil day accumulates from quantity readings.
private struct DayRollup {
    var restingHr = RunningMean()
    var hrv = RunningMean()
    var respRate = RunningMean()
    var walkingHr = RunningMean()
    var spo2 = RunningMean()
    var heartRate = RunningMean()
    var heartRateMax = RunningMax()
    var steps = SourcedTotal()        // FER-411: cross-source dedup (max source/day, not the sum)
    var activeKcal = SourcedTotal()
    var basalKcal = SourcedTotal()
    var vo2max = LatestOfDay()
    var weight = LatestOfDay()
    var leanMass = LatestOfDay()
    var bodyFat = LatestOfDay()
    var bmi = LatestOfDay()
}

/// Everything one night accumulates from sleep stage segments.
private struct NightRollup {
    var deep = 0.0
    var rem = 0.0
    var core = 0.0
    /// The legacy "Asleep" bucket: counts as sleep, belongs to no stage.
    var unspecified = 0.0
    var awake = 0.0
    var inBed = 0.0

    /// Awake and in-bed time is time in bed, not time asleep.
    var asleep: Double { core + deep + rem + unspecified }
}

// MARK: - The engine

/// Folds Apple Health readings and sleep segments into one row per civil day.
///
/// A reference type on purpose: the importer hands it record after record while the
/// document streams. It is used from a single thread per import and is deliberately NOT
/// `Sendable` — adding locking would cost on a path that runs tens of millions of times.
public final class AppleHealthDayAggregator {

    private var days: [String: DayRollup] = [:]
    private var nights: [String: NightRollup] = [:]

    public init() {}

    // MARK: Folding

    /// Folds one quantity reading into its civil day.
    ///
    /// The day comes from `start` with the supplied offset; `end` only breaks ties for the
    /// "last reading of the day" metrics. A reading with no usable value is ignored outright
    /// and does not bring its day into existence.
    public func addRecord(type: String, value: Double?, unit: String?,
                          source: String? = nil,
                          start: Date, tzOffsetMin: Int, end: Date) {
        guard let raw = value else { return }

        let name = HealthTypeName.stripped(type)
        let day = AppleHealthAggregator.localDay(start, tzOffsetMin: tzOffsetMin)
        var rollup = days[day] ?? DayRollup()

        switch ReadingKind(strippedType: name) {
        case .restingHr:  rollup.restingHr.add(raw)
        case .hrv:        rollup.hrv.add(raw)
        case .respRate:   rollup.respRate.add(raw)
        case .walkingHr:  rollup.walkingHr.add(raw)
        case .spo2:       rollup.spo2.add(Self.asPercentage(raw))
        case .heartRate:
            rollup.heartRate.add(raw)
            rollup.heartRateMax.offer(raw)
        case .steps:       rollup.steps.add(raw, source: source)
        case .activeKcal:  rollup.activeKcal.add(raw, source: source)
        case .basalKcal:   rollup.basalKcal.add(raw, source: source)
        case .vo2max:      rollup.vo2max.offer(raw, at: end)
        case .weight:      rollup.weight.offer(Self.asKilograms(raw, unit: unit), at: end)
        case .leanMass:    rollup.leanMass.offer(Self.asKilograms(raw, unit: unit), at: end)
        case .bodyFat:     rollup.bodyFat.offer(Self.asPercentage(raw), at: end)
        case .bmi:         rollup.bmi.offer(raw, at: end)
        case .none:
            // A relevant type with no destination field yet (body temperature). The day is
            // still real and still shows up in the row list — it just carries no numbers.
            break
        }

        days[day] = rollup
    }

    /// Folds one sleep segment into the night it WOKE UP on: a night is filed under the
    /// civil day of its `end`, so everything before and after midnight belongs together.
    public func addSleep(stage: SleepStage, start: Date, end: Date, tzOffsetMin: Int) {
        let minutes = max(0, end.timeIntervalSince(start)) / 60
        let night = AppleHealthAggregator.localDay(end, tzOffsetMin: tzOffsetMin)
        var rollup = nights[night] ?? NightRollup()

        switch stage {
        case .asleepDeep:        rollup.deep += minutes
        case .asleepREM:         rollup.rem += minutes
        case .asleepCore:        rollup.core += minutes
        case .asleepUnspecified: rollup.unspecified += minutes
        case .awake:             rollup.awake += minutes
        case .inBed:             rollup.inBed += minutes
        case .unknown:           break   // the night exists; the minutes go nowhere
        }

        nights[night] = rollup
    }

    // MARK: Reading out

    /// Sleep totals per night, keyed by the civil day the night ended on.
    public func sleepByDay() -> [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] {
        var output: [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] = [:]
        output.reserveCapacity(nights.count)
        for (night, rollup) in nights {
            output[night] = (asleep: rollup.asleep, deep: rollup.deep, rem: rollup.rem,
                             core: rollup.core, awake: rollup.awake, inBed: rollup.inBed)
        }
        return output
    }

    /// One row per day that saw quantity readings, sleep fields left `nil`, ascending by day.
    public func sampleDaily() -> [AppleDailyAggregate] {
        days.keys.sorted().map { row(for: $0, night: nil) }
    }

    /// One row per day present in EITHER source, ascending by day. The order is contract:
    /// the app consumes the array as it comes.
    public func merged() -> [AppleDailyAggregate] {
        var keys = Set(days.keys)
        keys.formUnion(nights.keys)
        return keys.sorted().map { row(for: $0, night: nights[$0]) }
    }

    private func row(for day: String, night: NightRollup?) -> AppleDailyAggregate {
        let rollup = days[day] ?? DayRollup()
        return AppleDailyAggregate(
            day: day,
            restingHr: rollup.restingHr.value,
            hrvSDNN: rollup.hrv.value,
            spo2Pct: rollup.spo2.value,
            respRate: rollup.respRate.value,
            avgHr: rollup.heartRate.value,
            maxHr: rollup.heartRateMax.value,
            walkingHr: rollup.walkingHr.value,
            steps: rollup.steps.value,
            activeKcal: rollup.activeKcal.value,
            basalKcal: rollup.basalKcal.value,
            vo2max: rollup.vo2max.value,
            weightKg: rollup.weight.value,
            bodyFatPct: rollup.bodyFat.value,
            leanMassKg: rollup.leanMass.value,
            bmi: rollup.bmi.value,
            asleepMin: night?.asleep,
            deepMin: night?.deep,
            remMin: night?.rem,
            coreMin: night?.core,
            awakeMin: night?.awake,
            inBedMin: night?.inBed)
    }

    // MARK: Unit normalisation

    /// Apple exports oxygen saturation and body fat as a fraction. Anything already above 1
    /// is taken to be a percentage and left alone.
    private static func asPercentage(_ value: Double) -> Double {
        (value > 0 && value <= 1) ? value * 100 : value
    }

    /// Pounds → kilograms (1 lb = 0.453592 kg). A mass with no declared unit is assumed to
    /// be metric, which is what Apple writes.
    private static func asKilograms(_ value: Double, unit: String?) -> Double {
        guard let unit else { return value }
        let normalized = unit.lowercased()
        let isPounds = normalized == "lb" || normalized == "lbs" || normalized.contains("pound")
        return isPounds ? value * 0.453592 : value
    }
}

// MARK: - Pure reduction rules

/// The day rules, callable on plain arrays. Every entry point here funnels through
/// `AppleHealthDayAggregator`, so a batch reduction and a streaming import can never drift
/// apart.
public enum AppleHealthAggregator {

    /// The `yyyy-MM-dd` civil day an instant belongs to, given the wall-clock offset that was
    /// in force when it was recorded.
    ///
    /// Pure integer arithmetic, and deliberately independent of the device's own time zone:
    /// two readings taken either side of a daylight-saving change, each carrying its own
    /// offset, still land on the same day. This string is the join key of nearly every table
    /// the user owns — changing how it is produced silently moves history.
    public static func localDay(_ utc: Date, tzOffsetMin: Int) -> String {
        let localSeconds = Int(utc.timeIntervalSince1970.rounded(.down)) + tzOffsetMin * 60
        return CivilTime.dayString(CivilTime.floorDiv(localSeconds, CivilTime.secondsPerDay))
    }

    /// Reduces quantity readings only: one row per day, sleep fields `nil`.
    public static func daily(samples: [HealthSample]) -> [AppleDailyAggregate] {
        let engine = AppleHealthDayAggregator()
        for sample in samples {
            engine.addRecord(type: sample.type, value: sample.value, unit: sample.unit,
                             source: sample.sourceName,
                             start: sample.start, tzOffsetMin: sample.tzOffsetMin, end: sample.end)
        }
        return engine.sampleDaily()
    }

    /// Reduces sleep segments only: totals per night.
    public static func sleepDaily(
        _ intervals: [SleepStageInterval]
    ) -> [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] {
        let engine = AppleHealthDayAggregator()
        for interval in intervals {
            engine.addSleep(stage: interval.stage, start: interval.start, end: interval.end,
                            tzOffsetMin: interval.tzOffsetMin)
        }
        return engine.sleepByDay()
    }

    /// Reduces both, and returns the union of the days either source touched.
    public static func aggregate(samples: [HealthSample],
                                 sleepIntervals: [SleepStageInterval]) -> [AppleDailyAggregate] {
        let engine = AppleHealthDayAggregator()
        for sample in samples {
            engine.addRecord(type: sample.type, value: sample.value, unit: sample.unit,
                             source: sample.sourceName,
                             start: sample.start, tzOffsetMin: sample.tzOffsetMin, end: sample.end)
        }
        for interval in sleepIntervals {
            engine.addSleep(stage: interval.stage, start: interval.start, end: interval.end,
                            tzOffsetMin: interval.tzOffsetMin)
        }
        return engine.merged()
    }

    // MARK: Flattening

    /// Flattens the rows into `(day, key, value)` triples for the generic series store.
    ///
    /// Only present values are emitted, and the emission order — days as given, fields in the
    /// order below — is observable. THE KEYS ARE PERSISTED IN THE USER'S DATABASE: renaming
    /// one orphans that metric's whole history without raising a single error.
    public static func metricPoints(_ daily: [AppleDailyAggregate]) -> [(day: String, key: String, value: Double)] {
        var points: [(day: String, key: String, value: Double)] = []
        points.reserveCapacity(daily.count * 8)

        for row in daily {
            func emit(_ key: String, _ value: Double?) {
                guard let value else { return }
                points.append((day: row.day, key: key, value: value))
            }
            emit("resting_hr", row.restingHr)
            emit("hrv", row.hrvSDNN)
            emit("spo2", row.spo2Pct)
            emit("resp_rate", row.respRate)
            emit("avg_hr", row.avgHr)
            emit("max_hr", row.maxHr)
            emit("walking_hr", row.walkingHr)
            emit("steps", row.steps)
            emit("active_kcal", row.activeKcal)
            emit("basal_kcal", row.basalKcal)
            emit("vo2max", row.vo2max)
            emit("weight", row.weightKg)
            emit("body_fat", row.bodyFatPct)
            emit("lean_mass", row.leanMassKg)
            emit("bmi", row.bmi)
            emit("asleep_min", row.asleepMin)
            emit("deep_min", row.deepMin)
            emit("rem_min", row.remMin)
            emit("core_min", row.coreMin)
            emit("awake_min", row.awakeMin)
            emit("in_bed_min", row.inBedMin)
        }
        return points
    }
}
