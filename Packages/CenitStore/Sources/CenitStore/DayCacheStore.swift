import Foundation
import StrandModels
import GRDB

// DayCacheStore.swift — los días y las noches ya puntuados.
//
// El nombre «caché» engaña: no hay invalidación, no hay bandera de sucio y no hay aviso. Son valores
// durables que la capa de app vuelve a escribir cuando recalcula. La única protección contra un
// recálculo incompleto es la regla de conflicto de aquí abajo, y es lo más delicado del paquete.

/// Reexportados sin calificar porque la instantánea del tablero los usa así.
public typealias DailyMetric = StrandModels.DailyMetric
public typealias CachedSleepSession = StrandModels.CachedSleepSession

extension CenitStore {

    // MARK: - Noches

    /// Escribe sesiones de sueño bajo `deviceId`. Clave `(deviceId, startTs)`; en conflicto se
    /// reemplaza la fila completa —una noche re-puntuada sustituye a la anterior— y devuelve las
    /// filas cambiadas.
    @discardableResult
    public func upsertSleepSessions(_ sessions: [CachedSleepSession], deviceId: String) async throws -> Int {
        guard !sessions.isEmpty else { return 0 }
        let unique = RowBatch.lastPerKey(sessions, by: \.startTs)
        return try syncWrite { db in
            try RowBatch.write(db, rows: unique, columnsPerRow: 7, sql: { values in
                """
                INSERT INTO sleepSession
                    (deviceId, startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON)
                VALUES \(values)
                ON CONFLICT (deviceId, startTs) DO UPDATE SET
                    endTs = excluded.endTs,
                    efficiency = excluded.efficiency,
                    restingHr = excluded.restingHr,
                    avgHrv = excluded.avgHrv,
                    stagesJSON = excluded.stagesJSON
                """
            }, arguments: {
                [deviceId, $0.startTs, $0.endTs, $0.efficiency, $0.restingHr, $0.avgHrv, $0.stagesJSON]
            })
        }
    }

    /// Las sesiones que se TRASLAPAN con `[from, to]`, no las que empiezan dentro: quien se durmió
    /// antes de la medianoche local tiene una noche que empezó fuera de la ventana y que la ventana
    /// tiene que devolver. Ascendente por `startTs`, con tope.
    public func sleepSessions(deviceId: String, from: Int, to: Int,
                              limit: Int) async throws -> [CachedSleepSession] {
        try syncRead { try Self.fetchSleepSessions($0, deviceId: deviceId, from: from, to: to, limit: limit) }
    }

    // MARK: - Días

    /// Escribe agregados diarios bajo `deviceId`, devolviendo las filas cambiadas.
    ///
    /// **La regla de conflicto NO es un reemplazo.** El motor re-puntúa cada noche de su ventana en
    /// cada pasada, y una noche cuya sesión de sueño todavía no se detecta vuelve con nulos. Si el
    /// nulo pisara lo guardado, una pasada parcial blanquearía un día entero de historia. Por eso
    /// cada columna se funde con `COALESCE(entrante, existente)`: lo entrante manda cuando trae algo,
    /// y lo guardado sobrevive cuando no. Para BORRAR un día se borra, no se escribe con nulos.
    ///
    /// La carga (`strain`) tiene su propia regla, más estrecha, en `strainMerge`.
    @discardableResult
    public func upsertDailyMetrics(_ days: [DailyMetric], deviceId: String) async throws -> Int {
        guard !days.isEmpty else { return 0 }
        // Aquí NO se puede quedar sólo la última aparición de un día: la regla funde columna por
        // columna, así que perder la primera perdería los valores que sólo ella traía. Se reparte en
        // pasadas, que aplicadas en orden dan exactamente lo mismo que escribirlas una por una.
        return try syncWrite { db in
            var changed = 0
            for pass in RowBatch.passes(days, by: \.day) {
                changed += try RowBatch.write(db, rows: pass, columnsPerRow: 20, sql: { values in
                    """
                    INSERT INTO dailyMetric
                        (deviceId, day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                         disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                         spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst,
                         effortConfidence, restConfidence)
                    VALUES \(values)
                    ON CONFLICT (deviceId, day) DO UPDATE SET
                        totalSleepMin = COALESCE(excluded.totalSleepMin, dailyMetric.totalSleepMin),
                        efficiency = COALESCE(excluded.efficiency, dailyMetric.efficiency),
                        deepMin = COALESCE(excluded.deepMin, dailyMetric.deepMin),
                        remMin = COALESCE(excluded.remMin, dailyMetric.remMin),
                        lightMin = COALESCE(excluded.lightMin, dailyMetric.lightMin),
                        disturbances = COALESCE(excluded.disturbances, dailyMetric.disturbances),
                        restingHr = COALESCE(excluded.restingHr, dailyMetric.restingHr),
                        avgHrv = COALESCE(excluded.avgHrv, dailyMetric.avgHrv),
                        recovery = COALESCE(excluded.recovery, dailyMetric.recovery),
                        strain = \(Self.strainMerge),
                        exerciseCount = COALESCE(excluded.exerciseCount, dailyMetric.exerciseCount),
                        spo2Pct = COALESCE(excluded.spo2Pct, dailyMetric.spo2Pct),
                        skinTempDevC = COALESCE(excluded.skinTempDevC, dailyMetric.skinTempDevC),
                        respRateBpm = COALESCE(excluded.respRateBpm, dailyMetric.respRateBpm),
                        steps = COALESCE(excluded.steps, dailyMetric.steps),
                        activeKcalEst = COALESCE(excluded.activeKcalEst, dailyMetric.activeKcalEst),
                        effortConfidence = COALESCE(excluded.effortConfidence, dailyMetric.effortConfidence),
                        restConfidence = COALESCE(excluded.restConfidence, dailyMetric.restConfidence)
                    """
                }, arguments: {
                    [deviceId, $0.day, $0.totalSleepMin, $0.efficiency, $0.deepMin, $0.remMin,
                     $0.lightMin, $0.disturbances, $0.restingHr, $0.avgHrv, $0.recovery, $0.strain,
                     $0.exerciseCount, $0.spo2Pct, $0.skinTempDevC, $0.respRateBpm, $0.steps,
                     $0.activeKcalEst, $0.effortConfidence, $0.restConfidence]
                })
            }
            return changed
        }
    }

    /// La regla de la carga, que **no** es `COALESCE`.
    ///
    /// Un entrenamiento puntuado siempre gana. Una carga ya persistida no se degrada ni a «descanso»
    /// (0) ni a «falta el dato» (nulo): borrarla exigiría borrar el día. Pero un 0 guardado —que casi
    /// siempre es un falso descanso de una pasada sin pulso— sí puede volver a nulo, que es la
    /// verdad honesta. En SQL eso son tres casos, en este orden:
    ///
    ///   entrante > 0            → entrante   (el entrenamiento manda)
    ///   existente > 0           → existente  (lo persistido no se degrada)
    ///   en cualquier otro caso  → entrante   (0 y nulo se sustituyen libremente entre sí)
    private static let strainMerge = """
        CASE
            WHEN excluded.strain > 0 THEN excluded.strain
            WHEN dailyMetric.strain > 0 THEN dailyMetric.strain
            ELSE excluded.strain
        END
        """

    /// Borra de esa partición los días nombrados, y devuelve cuántas filas se fueron. Una lista vacía
    /// no toca la base.
    @discardableResult
    public func deleteDailyMetrics(deviceId: String, days: [String]) async throws -> Int {
        guard !days.isEmpty else { return 0 }
        return try syncWrite { db in
            var deleted = 0
            for chunk in days.chunked(into: RowBatch.chunkSize(columnsPerRow: 1) - 1) {
                let slots = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
                var bound: [DatabaseValueConvertible?] = [deviceId]
                bound.append(contentsOf: chunk)
                try db.execute(sql: "DELETE FROM dailyMetric WHERE deviceId = ? AND day IN (\(slots))",
                               arguments: StatementArguments(bound))
                deleted += db.changesCount
            }
            return deleted
        }
    }

    /// Los días guardados en `from <= day <= to` (lexicográfico), del más antiguo al más reciente.
    /// Comparte el lector de fila con la instantánea del tablero.
    public func dailyMetrics(deviceId: String, from: String, to: String) async throws -> [DailyMetric] {
        try syncRead { try Self.fetchDailyMetrics($0, deviceId: deviceId, from: from, to: to) }
    }
}
