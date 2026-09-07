import Foundation
import GRDB

// SeriesStore.swift — la serie métrica larga.
//
// La contraparte «alta y flaca» de las cachés anchas: cualquier escalar de cualquier fuente cabe aquí
// como (día, clave, valor) y se lee por clave, sin inventar una columna ni una migración por métrica
// nueva.

/// Un escalar de un día. `day` es el día civil local, `"YYYY-MM-DD"`.
public struct MetricPoint: Equatable, Codable, Sendable {
    public let day: String
    public let key: String
    public let value: Double
    public init(day: String, key: String, value: Double) {
        self.day = day
        self.key = key
        self.value = value
    }
}

extension CenitStore {

    /// Escribe `rows` bajo `deviceId` y devuelve cuántas filas cambiaron (insertadas **más**
    /// actualizadas): reescribir N puntos idénticos devuelve N, no 0.
    ///
    /// En conflicto de `(deviceId, day, key)` gana el valor entrante — un recálculo reemplaza, no
    /// funde.
    @discardableResult
    public func upsertMetricSeries(_ rows: [MetricPoint], deviceId: String) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let unique = RowBatch.lastPerKey(rows) { PointKey(day: $0.day, key: $0.key) }
        return try syncWrite { db in
            try RowBatch.write(db, rows: unique, columnsPerRow: 4, sql: { values in
                """
                INSERT INTO metricSeries (deviceId, day, key, value) VALUES \(values)
                ON CONFLICT (deviceId, day, key) DO UPDATE SET value = excluded.value
                """
            }, arguments: { [deviceId, $0.day, $0.key, $0.value] })
        }
    }

    /// Borra todos los puntos de esa partición y esa clave. Igualdad exacta de la clave: nada de
    /// rangos ni comodines, para que borrar `hrv` no se lleve `hrv_lf`.
    public func deleteMetricSeries(deviceId: String, key: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM metricSeries WHERE deviceId = ? AND key = ?",
                           arguments: [deviceId, key])
        }
    }

    /// Los puntos de una clave en `from <= day <= to` (comparación lexicográfica de `YYYY-MM-DD`),
    /// del más antiguo al más reciente.
    ///
    /// Delega en el lector de fila que también sirve a la instantánea del tablero: un solo SQL, así
    /// que la lectura suelta y la del tablero no pueden divergir.
    public func metricSeries(deviceId: String, key: String,
                             from: String, to: String) async throws -> [MetricPoint] {
        try syncRead { try Self.fetchMetricSeries($0, deviceId: deviceId, key: key, from: from, to: to) }
    }

    /// Varias claves en UNA lectura — quien arma 24 claves horarias no debe hacer 24 viajes.
    ///
    /// Orden público: `day` ascendente y, a igualdad, `key` ascendente. Ese orden NO se pide en SQL:
    /// el índice está por `(deviceId, key, day)`, así que ordenar por `(day, key)` obligaría a SQLite
    /// a construir un B-TREE temporal sobre miles de filas. Se ordena siguiendo el índice y se
    /// restablece el orden público en memoria, que es barato y no aparece en el plan.
    public func metricSeries(deviceId: String, keys: [String],
                             from: String, to: String) async throws -> [MetricPoint] {
        guard !keys.isEmpty else { return [] }
        let rows: [MetricPoint] = try syncRead { db in
            let slots = Array(repeating: "?", count: keys.count).joined(separator: ", ")
            var bound: [DatabaseValueConvertible?] = [deviceId]
            bound.append(contentsOf: keys)
            bound.append(contentsOf: [from, to])
            return try Row.fetchAll(db, sql: """
                SELECT day, key, value FROM metricSeries
                WHERE deviceId = ? AND key IN (\(slots)) AND day >= ? AND day <= ?
                ORDER BY key ASC, day ASC
                """, arguments: StatementArguments(bound))
                .map { MetricPoint(day: $0["day"], key: $0["key"], value: $0["value"]) }
        }
        return rows.sorted { ($0.day, $0.key) < ($1.day, $1.key) }
    }

    /// Las claves distintas que esa partición tiene guardadas, ascendentes.
    public func metricKeys(deviceId: String) async throws -> [String] {
        try syncRead { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT key FROM metricSeries WHERE deviceId = ? ORDER BY key ASC
                """, arguments: [deviceId])
        }
    }

    /// El primer y el último día con un punto de esa clave, o `nil` si no hay ninguno.
    ///
    /// La agregación siempre devuelve una fila, incluso sin datos: por eso la ausencia se detecta en
    /// el mínimo nulo y no en la falta de fila.
    public func metricDays(deviceId: String, key: String) async throws -> (earliest: String, latest: String)? {
        try syncRead { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT MIN(day) AS earliest, MAX(day) AS latest FROM metricSeries
                WHERE deviceId = ? AND key = ?
                """, arguments: [deviceId, key]),
                  let earliest: String = row["earliest"], let latest: String = row["latest"]
            else { return nil }
            return (earliest, latest)
        }
    }

    /// La clave natural de un punto dentro de una partición.
    private struct PointKey: Hashable {
        let day: String
        let key: String
    }
}
