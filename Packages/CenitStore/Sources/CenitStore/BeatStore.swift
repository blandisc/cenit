import Foundation
import BiometricStreams
import GRDB

// BeatStore.swift — los latidos crudos: alta idempotente y lecturas por ventana.
//
// Son las dos tablas de mayor volumen del archivo (un día de pulso a 1 Hz son ~86 000 filas), y las
// únicas particionadas por el entero suplente en vez del texto de la fuente.

/// El promedio de pulso de una cubeta de tiempo. `ts` es el INICIO de la cubeta.
public struct HRBucket: Sendable, Equatable {
    public let ts: Int
    public let bpm: Double
    public init(ts: Int, bpm: Double) {
        self.ts = ts
        self.bpm = bpm
    }
}

extension CenitStore {

    // MARK: - Alta

    /// Persiste los latidos de `streams` bajo `deviceId` y devuelve cuántas filas entraron de verdad.
    ///
    /// Idempotente por clave natural: `(deviceId, ts)` para el pulso y `(deviceId, ts, rrMs)` para los
    /// intervalos; lo que ya estaba no se toca y no cuenta. Reimportar el mismo periodo completo
    /// devuelve `(0, 0)` y deja la base igual.
    ///
    /// Sólo se guardan esos dos flujos. Los demás campos que `Streams` sigue cargando pertenecen a
    /// tablas que ya no existen: intentar escribirlos lanzaría «no such table» y tumbaría la
    /// transacción entera, incluidos los latidos que sí viven.
    @discardableResult
    public func insert(_ streams: Streams, deviceId: String) async throws -> (hr: Int, rr: Int) {
        guard !streams.hr.isEmpty || !streams.rr.isEmpty else { return (0, 0) }
        // El suplente se resuelve UNA vez por llamada, no por fila.
        let partition = try partitionId(deviceId, creating: true)!

        return try syncWrite { db in
            var hrRows = 0
            if !streams.hr.isEmpty {
                let stmt = try db.cachedStatement(
                    sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES (?, ?, ?) ON CONFLICT DO NOTHING")
                for beat in streams.hr {
                    try stmt.execute(arguments: [partition, beat.ts, beat.bpm])
                    hrRows += db.changesCount
                }
            }
            var rrRows = 0
            if !streams.rr.isEmpty {
                let stmt = try db.cachedStatement(
                    sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES (?, ?, ?) ON CONFLICT DO NOTHING")
                for interval in streams.rr {
                    try stmt.execute(arguments: [partition, interval.ts, interval.rrMs])
                    rrRows += db.changesCount
                }
            }
            return (hrRows, rrRows)
        }
    }

    /// Cuántas filas crudas hay guardadas, sumando todas las particiones.
    public func sampleCounts() async throws -> (hr: Int, rr: Int) {
        try syncRead { db in
            (hr: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample") ?? 0,
             rr: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval") ?? 0)
        }
    }

    /// «Verificar mis datos»: el chequeo de integridad de SQLite. Es un escaneo completo a propósito
    /// —lo dispara un gesto, no el arranque— y sólo es `true` si SQLite responde exactamente `ok`.
    public func integrityCheck() async throws -> Bool {
        try syncRead { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok"
        }
    }

    // MARK: - Lecturas

    /// Pulso crudo en `[from, to]` (ambos extremos incluidos), ascendente por `ts`. `limit` recorta a
    /// los PRIMEROS de ese orden. Una partición que nunca se escribió devuelve vacío.
    public func hrSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [HRSample] {
        guard let partition = try partitionId(deviceId, creating: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, bpm FROM hrSample WHERE deviceId = ? AND ts BETWEEN ? AND ?
                ORDER BY ts ASC
                LIMIT ?
                """, arguments: [partition, from, to, limit])
                .map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
        }
    }

    /// Pulso promediado por cubetas de `bucketSeconds`, agregado **en SQL**: un día a 1 Hz no cabe
    /// razonablemente en memoria para promediarlo aquí. La clave de cada cubeta es su inicio,
    /// `floor(ts / ancho) * ancho`; un ancho de 0 o negativo se trata como 1 en vez de reventar.
    public func hrBuckets(deviceId: String, from: Int, to: Int,
                          bucketSeconds: Int) async throws -> [HRBucket] {
        guard let partition = try partitionId(deviceId, creating: false) else { return [] }
        let width = max(1, bucketSeconds)
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT (ts / ?) * ? AS bucket, AVG(bpm) AS mean
                FROM hrSample WHERE deviceId = ? AND ts BETWEEN ? AND ?
                GROUP BY ts / ?
                ORDER BY bucket
                """, arguments: [width, width, partition, from, to, width])
                .map { HRBucket(ts: $0["bucket"], bpm: $0["mean"]) }
        }
    }

    /// Intervalos entre latidos en `[from, to]`. La clave natural admite varias filas por instante,
    /// así que el orden desempata por `rrMs` ascendente para que la lectura sea reproducible.
    public func rrIntervals(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RRInterval] {
        guard let partition = try partitionId(deviceId, creating: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, rrMs FROM rrInterval WHERE deviceId = ? AND ts BETWEEN ? AND ?
                ORDER BY ts ASC, rrMs ASC
                LIMIT ?
                """, arguments: [partition, from, to, limit])
                .map { RRInterval(ts: $0["ts"], rrMs: $0["rrMs"]) }
        }
    }

    /// El instante del último latido guardado de esa partición; `nil` si no hay ninguno. Es la prueba
    /// de que la fuente sigue entregando datos.
    public func latestHRSampleTs(deviceId: String) async throws -> Int? {
        guard let partition = try partitionId(deviceId, creating: false) else { return nil }
        return try syncRead { db in
            try Int.fetchOne(db, sql: "SELECT MAX(ts) FROM hrSample WHERE deviceId = ?",
                             arguments: [partition])
        }
    }
}
