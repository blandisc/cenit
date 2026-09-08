import Foundation
import CenitModels
import GRDB

// LogStore.swift — lo que se registró en un día: respuestas, entrenamientos y los totales de Apple.
//
// Las tres tablas comparten forma —clave natural por partición, alta idempotente, lectura por rango—
// y la misma trampa: SQLite se niega a resolver dos veces la misma clave de conflicto dentro de una
// sentencia, y estas altas llegan en lotes.

/// Reexportado sin calificar porque la instantánea del tablero lo usa así.
public typealias AppleDaily = CenitModels.AppleDaily

/// Una respuesta del diario. Clave natural `(deviceId, day, question)`.
public struct JournalEntry: Equatable, Codable {
    public let day: String
    public let question: String
    public let answeredYes: Bool
    public let notes: String?
    public init(day: String, question: String, answeredYes: Bool, notes: String?) {
        self.day = day
        self.question = question
        self.answeredYes = answeredYes
        self.notes = notes
    }
}

/// Un entrenamiento registrado. Clave natural `(deviceId, startTs, sport)`: dos deportes que empiezan
/// en el mismo instante son dos filas.
public struct WorkoutRow: Equatable, Hashable, Codable, Sendable {
    public let startTs: Int
    public let endTs: Int
    public let sport: String
    public let source: String
    public let durationS: Double?
    public let energyKcal: Double?
    public let avgHr: Int?
    public let maxHr: Int?
    public let strain: Double?
    public let distanceM: Double?
    public let zonesJSON: String?
    public let notes: String?
    public init(startTs: Int, endTs: Int, sport: String, source: String, durationS: Double?,
                energyKcal: Double?, avgHr: Int?, maxHr: Int?, strain: Double?, distanceM: Double?,
                zonesJSON: String?, notes: String?) {
        self.startTs = startTs
        self.endTs = endTs
        self.sport = sport
        self.source = source
        self.durationS = durationS
        self.energyKcal = energyKcal
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.strain = strain
        self.distanceM = distanceM
        self.zonesJSON = zonesJSON
        self.notes = notes
    }
}

/// Qué tanto alcanzó a traer la importación de Apple Health, para el panel de estado.
///
/// Una métrica sin un solo día **no aparece** en `daysByMetric`: la interfaz dibuja «falta» por
/// ausencia de la clave, y un `0` explícito diría otra cosa (que se buscó y no había nada).
public struct AppleHealthCoverage: Sendable, Equatable {
    public let firstDay: String?
    public let lastDay: String?
    public let totalDays: Int
    public let daysByMetric: [String: Int]
    public init(firstDay: String? = nil, lastDay: String? = nil,
                totalDays: Int = 0, daysByMetric: [String: Int] = [:]) {
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.totalDays = totalDays
        self.daysByMetric = daysByMetric
    }
}

extension CenitStore {

    // MARK: - Diario

    /// Escribe respuestas del diario bajo `deviceId`, devolviendo las filas cambiadas. En conflicto se
    /// reemplazan la respuesta y las notas.
    @discardableResult
    public func upsertJournal(_ rows: [JournalEntry], deviceId: String) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let unique = RowBatch.lastPerKey(rows) { AnswerKey(day: $0.day, question: $0.question) }
        return try syncWrite { db in
            try RowBatch.write(db, rows: unique, columnsPerRow: 5, sql: { values in
                """
                INSERT INTO journal (deviceId, day, question, answeredYes, notes) VALUES \(values)
                ON CONFLICT (deviceId, day, question) DO UPDATE SET
                    answeredYes = excluded.answeredYes,
                    notes = excluded.notes
                """
            }, arguments: { [deviceId, $0.day, $0.question, $0.answeredYes ? 1 : 0, $0.notes] })
        }
    }

    /// Borra UNA respuesta, acotada a su partición: limpiar una respuesta nativa nunca puede llevarse
    /// la fila idéntica que vino importada de otra fuente.
    @discardableResult
    public func deleteJournal(deviceId: String, day: String, question: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM journal WHERE deviceId = ? AND day = ? AND question = ?
                """, arguments: [deviceId, day, question])
            return db.changesCount
        }
    }

    /// «Empezar de cero»: borra TODAS las respuestas de esa partición, y sólo de esa.
    @discardableResult
    public func deleteAllJournal(deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM journal WHERE deviceId = ?", arguments: [deviceId])
            return db.changesCount
        }
    }

    /// Las respuestas en `from <= day <= to` (lexicográfico), ordenadas por día y luego por pregunta.
    public func journalEntries(deviceId: String, from: String, to: String) async throws -> [JournalEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, question, answeredYes, notes
                FROM journal WHERE deviceId = ? AND day BETWEEN ? AND ?
                ORDER BY day ASC, question ASC
                """, arguments: [deviceId, from, to])
                .map {
                    JournalEntry(day: $0["day"], question: $0["question"],
                                 answeredYes: ($0["answeredYes"] as Int) != 0, notes: $0["notes"])
                }
        }
    }

    // MARK: - Entrenamientos

    /// Escribe entrenamientos bajo `deviceId`, devolviendo las filas cambiadas. En conflicto se
    /// reemplazan todas las demás columnas, incluida la procedencia.
    @discardableResult
    public func upsertWorkouts(_ rows: [WorkoutRow], deviceId: String) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let unique = RowBatch.lastPerKey(rows) { SessionKey(startTs: $0.startTs, sport: $0.sport) }
        return try syncWrite { db in
            try RowBatch.write(db, rows: unique, columnsPerRow: 13, sql: { values in
                """
                INSERT INTO workout
                    (deviceId, startTs, endTs, sport, source, durationS, energyKcal, avgHr, maxHr,
                     strain, distanceM, zonesJSON, notes)
                VALUES \(values)
                ON CONFLICT (deviceId, startTs, sport) DO UPDATE SET
                    endTs = excluded.endTs,
                    source = excluded.source,
                    durationS = excluded.durationS,
                    energyKcal = excluded.energyKcal,
                    avgHr = excluded.avgHr,
                    maxHr = excluded.maxHr,
                    strain = excluded.strain,
                    distanceM = excluded.distanceM,
                    zonesJSON = excluded.zonesJSON,
                    notes = excluded.notes
                """
            }, arguments: {
                [deviceId, $0.startTs, $0.endTs, $0.sport, $0.source, $0.durationS, $0.energyKcal,
                 $0.avgHr, $0.maxHr, $0.strain, $0.distanceM, $0.zonesJSON, $0.notes]
            })
        }
    }

    /// Borra de esa partición los entrenamientos de ese deporte que empiezan en `[from, to]`. Es lo
    /// que vuelve idempotente la re-derivación: se barre el tramo y se vuelve a escribir.
    @discardableResult
    public func deleteWorkouts(deviceId: String, sport: String, from: Int, to: Int) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM workout WHERE deviceId = ? AND sport = ? AND startTs >= ? AND startTs <= ?
                """, arguments: [deviceId, sport, from, to])
            return db.changesCount
        }
    }

    /// Los entrenamientos que EMPIEZAN en `[from, to]` —filtro por inicio, no por traslape—,
    /// ascendentes por `startTs`, con tope.
    public func workouts(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [WorkoutRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, sport, source, durationS, energyKcal,
                       avgHr, maxHr, strain, distanceM, zonesJSON, notes
                FROM workout WHERE deviceId = ? AND startTs BETWEEN ? AND ?
                ORDER BY startTs ASC
                LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map {
                    WorkoutRow(startTs: $0["startTs"], endTs: $0["endTs"], sport: $0["sport"],
                               source: $0["source"], durationS: $0["durationS"],
                               energyKcal: $0["energyKcal"], avgHr: $0["avgHr"], maxHr: $0["maxHr"],
                               strain: $0["strain"], distanceM: $0["distanceM"],
                               zonesJSON: $0["zonesJSON"], notes: $0["notes"])
                }
        }
    }

    // MARK: - Totales diarios de Apple

    /// Escribe agregados diarios de Apple bajo `deviceId`, devolviendo las filas cambiadas. En
    /// conflicto de `(deviceId, day)` se reemplazan todas las columnas métricas.
    @discardableResult
    public func upsertAppleDaily(_ rows: [AppleDaily], deviceId: String) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let unique = RowBatch.lastPerKey(rows, by: \.day)
        return try syncWrite { db in
            try RowBatch.write(db, rows: unique, columnsPerRow: 10, sql: { values in
                """
                INSERT INTO appleDaily
                    (deviceId, day, steps, activeKcal, basalKcal, vo2max, avgHr, maxHr, walkingHr, weightKg)
                VALUES \(values)
                ON CONFLICT (deviceId, day) DO UPDATE SET
                    steps = excluded.steps,
                    activeKcal = excluded.activeKcal,
                    basalKcal = excluded.basalKcal,
                    vo2max = excluded.vo2max,
                    avgHr = excluded.avgHr,
                    maxHr = excluded.maxHr,
                    walkingHr = excluded.walkingHr,
                    weightKg = excluded.weightKg
                """
            }, arguments: {
                [deviceId, $0.day, $0.steps, $0.activeKcal, $0.basalKcal, $0.vo2max, $0.avgHr,
                 $0.maxHr, $0.walkingHr, $0.weightKg]
            })
        }
    }

    /// Los agregados de Apple en `from <= day <= to` (lexicográfico), ascendentes. Comparte el lector
    /// de fila con la instantánea del tablero.
    public func appleDaily(deviceId: String, from: String, to: String) async throws -> [AppleDaily] {
        try syncRead { try Self.fetchAppleDaily($0, deviceId: deviceId, from: from, to: to) }
    }

    // MARK: - Cobertura de la importación

    /// Qué días cubrió la importación y, por métrica, cuántos días traen un valor real.
    ///
    /// Los diez nombres de métrica son contrato con la interfaz. Una métrica con cero días queda
    /// FUERA del diccionario: la ausencia es lo que la interfaz lee como «no hay».
    public func appleHealthCoverage(deviceId: String) async throws -> AppleHealthCoverage {
        try syncRead { db in
            // Los totales diarios de Apple. Una fila por día, así que contar valores no nulos de una
            // columna es contar días con esa métrica.
            let fromApple = try Row.fetchOne(db, sql: """
                SELECT COUNT(steps) AS steps, COUNT(activeKcal) AS active_kcal,
                       COUNT(vo2max) AS vo2max, COUNT(avgHr) AS avg_hr
                FROM appleDaily WHERE deviceId = ?
                """, arguments: [deviceId])

            // Los escalares que el motor deja por noche.
            let fromDays = try Row.fetchOne(db, sql: """
                SELECT COUNT(totalSleepMin) AS asleep_min, COUNT(avgHrv) AS hrv,
                       COUNT(restingHr) AS resting_hr, COUNT(spo2Pct) AS spo2,
                       COUNT(respRateBpm) AS resp_rate, COUNT(skinTempDevC) AS skin_temp
                FROM dailyMetric WHERE deviceId = ?
                """, arguments: [deviceId])

            var daysByMetric: [String: Int] = [:]
            for (row, names) in [(fromApple, ["steps", "active_kcal", "vo2max", "avg_hr"]),
                                 (fromDays, ["asleep_min", "hrv", "resting_hr", "spo2",
                                             "resp_rate", "skin_temp"])] {
                guard let row else { continue }
                for name in names where (row[name] as Int? ?? 0) > 0 {
                    daysByMetric[name] = row[name]
                }
            }

            // El tramo se mide sobre la UNIÓN de los días de las dos tablas: un día que sólo tiene
            // sueño cuenta igual que uno que sólo tiene pasos, y el que está en ambas cuenta una vez.
            let span = try Row.fetchOne(db, sql: """
                SELECT MIN(day) AS firstDay, MAX(day) AS lastDay, COUNT(*) AS totalDays FROM (
                    SELECT day FROM appleDaily WHERE deviceId = ?
                    UNION
                    SELECT day FROM dailyMetric WHERE deviceId = ?
                )
                """, arguments: [deviceId, deviceId])

            return AppleHealthCoverage(firstDay: span?["firstDay"], lastDay: span?["lastDay"],
                                       totalDays: span?["totalDays"] ?? 0,
                                       daysByMetric: daysByMetric)
        }
    }

    /// La clave natural de una respuesta dentro de una partición.
    private struct AnswerKey: Hashable {
        let day: String
        let question: String
    }

    /// La clave natural de un entrenamiento dentro de una partición.
    private struct SessionKey: Hashable {
        let startTs: Int
        let sport: String
    }
}
