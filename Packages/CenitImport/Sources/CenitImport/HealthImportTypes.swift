import Foundation

// MARK: - Vocabulary of an Apple Health import (FER-382)
//
// The value types the importer speaks: what came out of the export file (`HealthSample`,
// `HealthWorkout`, `SleepStageInterval`), what the day reducer produced
// (`AppleDailyAggregate`), and what the caller gets back (`AppleHealthImportResult` +
// `ImportSummary`). All of them are plain, Foundation-only and `Sendable`: the analysis
// runs off the main thread and the result crosses back.

/// Where a batch of imported rows came from. Cénit reads Apple Health and nothing else.
public enum DataSourceKind: String, Sendable, Codable, Equatable, CaseIterable {
    case appleHealth
}

// MARK: - Records

/// One reading as it appeared in the export.
///
/// `type` is the HealthKit identifier with its `HK…TypeIdentifier` prefix already removed
/// (`HeartRate`, `SleepAnalysis`). `value` is the number for a quantity sample;
/// `valueString` keeps the raw text (a category sample carries an enumerated string).
/// `start`/`end` are instants in UTC and `tzOffsetMin` is the wall-clock offset the export
/// declared, in minutes east of UTC (`60` for `+0100`, `-300` for `-0500`) — the two
/// together are what lets a sample be filed under the civil day the user actually lived.
public struct HealthSample: Sendable, Equatable, Hashable {
    public var type: String
    public var value: Double?
    public var valueString: String?
    public var unit: String?
    public var start: Date
    public var end: Date
    public var tzOffsetMin: Int
    public var sourceName: String?

    public init(type: String, value: Double?, valueString: String?, unit: String?,
                start: Date, end: Date, tzOffsetMin: Int, sourceName: String?) {
        self.type = type
        self.value = value
        self.valueString = valueString
        self.unit = unit
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }

    /// A stable identity for the reading: type, both instants, origin and value, joined by
    /// `|`. Published API with an observable shape — the streaming importer does NOT use it
    /// (it de-duplicates structurally, see `AppleHealthImporter`), because a key set with one
    /// entry per record is exactly the kind of per-sample growth a multi-gigabyte export
    /// cannot afford.
    public var dedupeKey: String {
        let raw = valueString ?? value.map(String.init(describing:)) ?? ""
        return "\(type)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(sourceName ?? "")|\(raw)"
    }
}

/// One workout as it appeared in the export. Durations in seconds, distances in metres,
/// energy in kilocalories.
public struct HealthWorkout: Sendable, Equatable {
    public var activityType: String
    public var durationS: Double?
    public var distanceM: Double?
    public var energyKcal: Double?
    public var start: Date
    public var end: Date
    public var tzOffsetMin: Int
    public var sourceName: String?

    public init(activityType: String, durationS: Double?, distanceM: Double?, energyKcal: Double?,
                start: Date, end: Date, tzOffsetMin: Int, sourceName: String?) {
        self.activityType = activityType
        self.durationS = durationS
        self.distanceM = distanceM
        self.energyKcal = energyKcal
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }
}

// MARK: - Sleep

/// A sleep stage as Apple writes it into a `SleepAnalysis` category sample.
///
/// `asleepUnspecified` is the pre-watchOS-9 "Asleep" value: it counts as sleep but carries
/// no stage, so it can never be attributed to core, deep or REM.
public enum SleepStage: String, Sendable, Equatable, CaseIterable {
    case inBed
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
    case unknown

    /// Maps the raw `value` text of a `SleepAnalysis` record to a stage.
    ///
    /// Deliberately NOT the synthesized `RawRepresentable` initializer: an export can spell
    /// the same stage three ways — the full `HKCategoryValueSleepAnalysis…` constant, the
    /// bare suffix, or the numeric raw value — and anything unrecognised must degrade to
    /// `.unknown` rather than fail.
    public static func from(rawValue raw: String) -> SleepStage {
        switch raw {
        case "HKCategoryValueSleepAnalysisInBed", "InBed", "0":
            return .inBed
        case "HKCategoryValueSleepAnalysisAsleep",
             "HKCategoryValueSleepAnalysisAsleepUnspecified", "Asleep", "1":
            return .asleepUnspecified
        case "HKCategoryValueSleepAnalysisAwake", "Awake", "2":
            return .awake
        case "HKCategoryValueSleepAnalysisAsleepCore", "AsleepCore", "3":
            return .asleepCore
        case "HKCategoryValueSleepAnalysisAsleepDeep", "AsleepDeep", "4":
            return .asleepDeep
        case "HKCategoryValueSleepAnalysisAsleepREM", "AsleepREM", "5":
            return .asleepREM
        default:
            return .unknown
        }
    }
}

/// One stage segment of a night.
public struct SleepStageInterval: Sendable, Equatable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public var tzOffsetMin: Int
    public var sourceName: String?

    public init(stage: SleepStage, start: Date, end: Date, tzOffsetMin: Int, sourceName: String?) {
        self.stage = stage
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }
}

// MARK: - Result

/// What an import saw, in numbers the screen can show without touching the rows.
///
/// Built with O(1) state while the document streams past — never by walking a retained
/// array of samples.
public struct ImportSummary: Sendable, Equatable {
    public var sourceKind: DataSourceKind
    /// Accepted records (sleep and value-less ones included) plus workouts. The app shows
    /// this number literally, so what counts is contract.
    public var recordCount: Int
    public var earliest: Date?
    public var latest: Date?
    /// Histogram by prefix-free type, plus the literal key `Workout`.
    public var countsByCategory: [String: Int]
    /// Runs of bytes the sanitizer had to drop or replace, plus one for a truncated tail.
    public var skippedSpans: Int

    public init(sourceKind: DataSourceKind, recordCount: Int, earliest: Date?, latest: Date?,
                countsByCategory: [String: Int], skippedSpans: Int = 0) {
        self.sourceKind = sourceKind
        self.recordCount = recordCount
        self.earliest = earliest
        self.latest = latest
        self.countsByCategory = countsByCategory
        self.skippedSpans = skippedSpans
    }
}

/// Everything an Apple Health import produces: one row per civil day, the workout list in
/// document order, and the summary.
public struct AppleHealthImportResult: Sendable, Equatable {
    public var daily: [AppleDailyAggregate]
    public var workouts: [HealthWorkout]
    public var summary: ImportSummary

    public init(daily: [AppleDailyAggregate], workouts: [HealthWorkout], summary: ImportSummary) {
        self.daily = daily
        self.workouts = workouts
        self.summary = summary
    }
}

// MARK: - Errors

/// Why an import could not be completed. `description` is shown to the user verbatim.
public enum ImportError: Error, Equatable, Sendable, CustomStringConvertible {
    case fileNotFound(String)
    case notAZipOrFolder(String)
    case missingEntry(String)
    case xmlParseFailed(String)
    /// Kept as published API. Nothing throws it: an export with no usable data yields an
    /// empty result, not a failure.
    case emptyExport(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):     return "File not found: \(path)"
        case .notAZipOrFolder(let path):  return "Expected a folder or .zip: \(path)"
        case .missingEntry(let entry):    return "Required entry not found: \(entry)"
        case .xmlParseFailed(let reason): return "XML parse failed: \(reason)"
        case .emptyExport(let reason):    return "Export contained no usable data: \(reason)"
        }
    }
}

// MARK: - Daily aggregate

/// One civil day, reduced.
///
/// Every field is optional and `nil` means "no data that day" — distinct from `0`, which
/// for a sum means the day had readings that added up to nothing. The `day` string
/// (`yyyy-MM-dd`) is the de-facto primary key of the user's tables, so its format and the
/// rule that produces it (see `AppleHealthAggregator.localDay`) are frozen.
///
/// Units: `*Min` in minutes, energies in kcal, heart rates in beats/min, `spo2Pct` and
/// `bodyFatPct` as a 0–100 percentage, `vo2max` in mL/kg/min, masses in kilograms.
public struct AppleDailyAggregate: Equatable, Sendable {
    public let day: String
    public let restingHr: Double?, hrvSDNN: Double?, spo2Pct: Double?, respRate: Double?
    public let avgHr: Double?, maxHr: Double?, walkingHr: Double?
    public let steps: Double?, activeKcal: Double?, basalKcal: Double?, vo2max: Double?
    public let weightKg: Double?, bodyFatPct: Double?, leanMassKg: Double?, bmi: Double?
    public let asleepMin: Double?, deepMin: Double?, remMin: Double?
    public let coreMin: Double?, awakeMin: Double?, inBedMin: Double?

    public init(
        day: String,
        restingHr: Double? = nil, hrvSDNN: Double? = nil, spo2Pct: Double? = nil, respRate: Double? = nil,
        avgHr: Double? = nil, maxHr: Double? = nil, walkingHr: Double? = nil,
        steps: Double? = nil, activeKcal: Double? = nil, basalKcal: Double? = nil, vo2max: Double? = nil,
        weightKg: Double? = nil, bodyFatPct: Double? = nil, leanMassKg: Double? = nil, bmi: Double? = nil,
        asleepMin: Double? = nil, deepMin: Double? = nil, remMin: Double? = nil,
        coreMin: Double? = nil, awakeMin: Double? = nil, inBedMin: Double? = nil
    ) {
        self.day = day
        self.restingHr = restingHr; self.hrvSDNN = hrvSDNN; self.spo2Pct = spo2Pct; self.respRate = respRate
        self.avgHr = avgHr; self.maxHr = maxHr; self.walkingHr = walkingHr
        self.steps = steps; self.activeKcal = activeKcal; self.basalKcal = basalKcal; self.vo2max = vo2max
        self.weightKg = weightKg; self.bodyFatPct = bodyFatPct; self.leanMassKg = leanMassKg; self.bmi = bmi
        self.asleepMin = asleepMin; self.deepMin = deepMin; self.remMin = remMin
        self.coreMin = coreMin; self.awakeMin = awakeMin; self.inBedMin = inBedMin
    }
}
