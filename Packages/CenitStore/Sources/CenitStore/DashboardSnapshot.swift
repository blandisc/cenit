import Foundation
import GRDB
import CenitTraining

// DashboardSnapshot.swift — FER-970 (R-03). Everything `Repository.performRefresh` used to read in
// ~13 sequential actor round-trips (each with its own hop + read transaction + WAL snapshot) is
// read here in ONE transaction: one hop, one snapshot, cross-table consistent by construction.
// The row SQL/mapping is shared with the individual accessors via the `fetch…` helpers below —
// zero duplicated SQL, so the snapshot and the accessors cannot drift.
//
// Deliberate omission: Apple workout-HR samples are NOT part of the snapshot — R-01 reads them in
// a separate, skippable phase (only when some merged day still needs an estimated strain).

/// Parameters of the one-pass dashboard read. The two flags reproduce the source-mode gating
/// Repository does at query time — an excluded source is not read at all.
public struct DashboardReadRequest: Sendable {
    // Los tres ids de partición son valores PERSISTIDOS: así están escritos en las filas del disco.
    public var legacyDeviceId: String        // "strap"
    public var computedDeviceId: String     // "strap-noop"
    public var appleDeviceId: String        // "apple-health"
    public var fromDay: String              // YYYY-MM-DD window (dailyMetrics / appleDaily / metricSeries)
    public var toDay: String
    public var fromTs: Int                  // unix window (sleepSessions)
    public var toTs: Int
    public var sleepLimit: Int
    public var includeApple: Bool           // dataSourceMode.usesAppleHealth
    public var includeLegacySeries: Bool     // series de la partición heredada

    public init(legacyDeviceId: String, computedDeviceId: String, appleDeviceId: String,
                fromDay: String, toDay: String, fromTs: Int, toTs: Int,
                sleepLimit: Int = 4000, includeApple: Bool, includeLegacySeries: Bool) {
        self.legacyDeviceId = legacyDeviceId
        self.computedDeviceId = computedDeviceId
        self.appleDeviceId = appleDeviceId
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromTs = fromTs
        self.toTs = toTs
        self.sleepLimit = sleepLimit
        self.includeApple = includeApple
        self.includeLegacySeries = includeLegacySeries
    }
}

/// Every raw result the dashboard refresh consumes, read in one transaction. Field-for-field the
/// same rows the individual accessors return with identical parameters.
///
/// ⚠️ `appleDays` is NEVER gated on `includeApple`: it feeds the stored-coverage diagnostic
/// (FER-485, «nothing is deleted») and `DataSourcePolicy` — the mode gating for the dashboard
/// itself happens in memory, in Repository. Same for the two raw imported-source sleep arrays.
public struct DashboardSnapshot: Sendable {
    public var importedDays: [DailyMetric] = []
    public var computedDays: [DailyMetric] = []
    public var appleDays: [DailyMetric] = []
    public var importedSleeps: [CachedSleepSession] = []
    public var computedSleeps: [CachedSleepSession] = []
    public var appleSleeps: [CachedSleepSession] = []
    public var appleAgg: [AppleDaily] = []
    public var stepsEst: [MetricPoint] = []
    public var sleepPerformance: [MetricPoint] = []
    public var sleepConsistency: [MetricPoint] = []
    public var sleepNeed: [MetricPoint] = []
    public var sleepDebt: [MetricPoint] = []
    /// Ola 1 · E2: the finished Cénit strength sessions in the window, so the assembler can overlay
    /// their load onto the daily series (`SourceFusion.overlayStrengthLoad`). Read here, in the same
    /// transaction as everything else, so the overlay is cross-table consistent by construction.
    public var strengthLoads: [StrengthSessionLoad] = []
    /// Ola 1 · E2: the spans of the Apple workouts in the window — a strength session that OVERLAPS
    /// one of these is probably the same training Apple already counted, so the day takes the max
    /// instead of double-counting. Gated on `includeApple`, like every other Apple read.
    public var appleWorkouts: [WorkoutSpan] = []

    public init() {}
}

/// A finished Cénit strength session, reduced to what the daily-load overlay needs (ola 1 · E2).
public struct StrengthSessionLoad: Sendable, Equatable {
    public var startTs: Int
    public var endTs: Int
    /// The session's 0–21 load; `nil` = trained, load unknown (no pulse, no rating).
    public var strain: Double?
    /// Where `strain` came from. `nil` alongside a non-nil `strain` = a pre-v42 row = measured.
    public var strainSource: StrainSource?
    public init(startTs: Int, endTs: Int, strain: Double?, strainSource: StrainSource?) {
        self.startTs = startTs; self.endTs = endTs
        self.strain = strain; self.strainSource = strainSource
    }
}

/// The wall-clock span of one Apple workout (ola 1 · E2).
public struct WorkoutSpan: Sendable, Equatable {
    public var startTs: Int
    public var endTs: Int
    public init(startTs: Int, endTs: Int) { self.startTs = startTs; self.endTs = endTs }
}

extension CenitStore {

    /// ALL the dashboard reads in ONE read transaction (one WAL snapshot). `nonisolated`: touches
    /// no actor state — it reads `dbWriter` (a `let`) and resolves nothing through the actor's
    /// device-id cache; the apple surrogate isn't needed here (HR moved out, R-01). On the pool
    /// backend (R-04) this async read is served by a WAL reader connection, so it never queues
    /// behind a long write on the actor's executor.
    public nonisolated func dashboardSnapshot(_ req: DashboardReadRequest) async throws -> DashboardSnapshot {
        try await dbWriter.read { db in
            var snap = DashboardSnapshot()
            snap.importedDays = try Self.fetchDailyMetrics(db, deviceId: req.legacyDeviceId,
                                                           from: req.fromDay, to: req.toDay)
            snap.computedDays = try Self.fetchDailyMetrics(db, deviceId: req.computedDeviceId,
                                                           from: req.fromDay, to: req.toDay)
            snap.appleDays = try Self.fetchDailyMetrics(db, deviceId: req.appleDeviceId,
                                                        from: req.fromDay, to: req.toDay)
            snap.importedSleeps = try Self.fetchSleepSessions(db, deviceId: req.legacyDeviceId,
                                                              from: req.fromTs, to: req.toTs,
                                                              limit: req.sleepLimit)
            snap.computedSleeps = try Self.fetchSleepSessions(db, deviceId: req.computedDeviceId,
                                                              from: req.fromTs, to: req.toTs,
                                                              limit: req.sleepLimit)
            if req.includeApple {
                snap.appleSleeps = try Self.fetchSleepSessions(db, deviceId: req.appleDeviceId,
                                                               from: req.fromTs, to: req.toTs,
                                                               limit: req.sleepLimit)
                snap.appleAgg = try Self.fetchAppleDaily(db, deviceId: req.appleDeviceId,
                                                         from: req.fromDay, to: req.toDay)
            }
            if req.includeLegacySeries {
                snap.stepsEst = try Self.fetchMetricSeries(db, deviceId: req.computedDeviceId,
                                                           key: "steps_est", from: req.fromDay, to: req.toDay)
                snap.sleepPerformance = try Self.fetchMetricSeries(db, deviceId: req.legacyDeviceId,
                                                                   key: "sleep_performance",
                                                                   from: req.fromDay, to: req.toDay)
                snap.sleepConsistency = try Self.fetchMetricSeries(db, deviceId: req.legacyDeviceId,
                                                                   key: "sleep_consistency",
                                                                   from: req.fromDay, to: req.toDay)
                snap.sleepNeed = try Self.fetchMetricSeries(db, deviceId: req.legacyDeviceId,
                                                            key: "sleep_need_min",
                                                            from: req.fromDay, to: req.toDay)
                snap.sleepDebt = try Self.fetchMetricSeries(db, deviceId: req.legacyDeviceId,
                                                            key: "sleep_debt_min",
                                                            from: req.fromDay, to: req.toDay)
            }
            // Ola 1 · E2: strength sessions are Cénit's own — never gated on a source mode — plus the
            // Apple workout spans the overlay needs to tell «the same training» from «extra work».
            snap.strengthLoads = try Self.fetchStrengthLoads(db, from: req.fromTs, to: req.toTs)
            if req.includeApple {
                snap.appleWorkouts = try Self.fetchWorkoutSpans(db, deviceId: req.appleDeviceId,
                                                                from: req.fromTs, to: req.toTs)
            }
            return snap
        }
    }

    // MARK: - Shared row fetchers (one body serves the accessor AND the snapshot)

    static func fetchDailyMetrics(_ db: Database, deviceId: String,
                                  from: String, to: String) throws -> [DailyMetric] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                   disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                   spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst,
                   effortConfidence, restConfidence
            FROM dailyMetric WHERE deviceId = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: [deviceId, from, to])
        return rows.map { row in
            DailyMetric(day: row["day"],
                        totalSleepMin: row["totalSleepMin"],
                        efficiency: row["efficiency"],
                        deepMin: row["deepMin"],
                        remMin: row["remMin"],
                        lightMin: row["lightMin"],
                        disturbances: row["disturbances"],
                        restingHr: row["restingHr"],
                        avgHrv: row["avgHrv"],
                        recovery: row["recovery"],
                        strain: row["strain"],
                        exerciseCount: row["exerciseCount"],
                        spo2Pct: row["spo2Pct"],
                        skinTempDevC: row["skinTempDevC"],
                        respRateBpm: row["respRateBpm"],
                        steps: row["steps"],
                        activeKcalEst: row["activeKcalEst"],
                        effortConfidence: row["effortConfidence"],
                        restConfidence: row["restConfidence"])
        }
    }

    static func fetchSleepSessions(_ db: Database, deviceId: String,
                                   from: Int, to: Int, limit: Int) throws -> [CachedSleepSession] {
        // Traslape, no inicio: la noche de quien se durmió antes de la medianoche local empezó fuera
        // de la ventana y aun así es suya.
        let rows = try Row.fetchAll(db, sql: """
            SELECT startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON
            FROM sleepSession WHERE deviceId = ? AND startTs <= ? AND endTs >= ?
            ORDER BY startTs ASC
            LIMIT ?
            """, arguments: [deviceId, to, from, limit])
        return rows.map { row in
            CachedSleepSession(startTs: row["startTs"],
                               endTs: row["endTs"],
                               efficiency: row["efficiency"],
                               restingHr: row["restingHr"],
                               avgHrv: row["avgHrv"],
                               stagesJSON: row["stagesJSON"])
        }
    }

    static func fetchAppleDaily(_ db: Database, deviceId: String,
                                from: String, to: String) throws -> [AppleDaily] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT day, steps, activeKcal, basalKcal, vo2max,
                   avgHr, maxHr, walkingHr, weightKg
            FROM appleDaily WHERE deviceId = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: [deviceId, from, to])
        return rows.map { row in
            AppleDaily(day: row["day"],
                       steps: row["steps"],
                       activeKcal: row["activeKcal"],
                       basalKcal: row["basalKcal"],
                       vo2max: row["vo2max"],
                       avgHr: row["avgHr"],
                       maxHr: row["maxHr"],
                       walkingHr: row["walkingHr"],
                       weightKg: row["weightKg"])
        }
    }

    static func fetchStrengthLoads(_ db: Database, from: Int, to: Int) throws -> [StrengthSessionLoad] {
        try Row.fetchAll(db, sql: """
            SELECT startTs, endTs, strain, strainSource FROM strengthSession
            WHERE endTs IS NOT NULL AND startTs >= ? AND startTs <= ?
            ORDER BY startTs ASC
            """, arguments: [from, to])
            .map {
                StrengthSessionLoad(startTs: $0["startTs"], endTs: $0["endTs"], strain: $0["strain"],
                                    strainSource: ($0["strainSource"] as String?)
                                        .flatMap(StrainSource.init(rawValue:)))
            }
    }

    static func fetchWorkoutSpans(_ db: Database, deviceId: String,
                                  from: Int, to: Int) throws -> [WorkoutSpan] {
        try Row.fetchAll(db, sql: """
            SELECT startTs, endTs FROM workout
            WHERE deviceId = ? AND endTs >= ? AND startTs <= ?
            ORDER BY startTs ASC
            """, arguments: [deviceId, from, to])
            .map { WorkoutSpan(startTs: $0["startTs"], endTs: $0["endTs"]) }
    }

    static func fetchMetricSeries(_ db: Database, deviceId: String, key: String,
                                  from: String, to: String) throws -> [MetricPoint] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT day, key, value
            FROM metricSeries WHERE deviceId = ? AND key = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: [deviceId, key, from, to])
        return rows.map { row in
            MetricPoint(day: row["day"], key: row["key"], value: row["value"])
        }
    }
}
