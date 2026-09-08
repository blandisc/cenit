import XCTest
import GRDB
@testable import CenitStore

/// FER-479 · la red de seguridad de la migración `v44` (renombre de particiones con marca).
///
/// `v44` es la ÚNICA migración que TOCA la base real del dueño: reescribe los identificadores de
/// partición y de `source` que quedaron con sabor a la banda anterior / NOOP / WHOOP a nombres
/// neutros. Estas pruebas construyen una base con el esquema `v43` y filas bajo los valores VIEJOS en
/// CADA tabla afectada, corren el migrador hasta `v44` y aseveran, tabla por tabla, que:
///   (a) 0 filas quedan con valor viejo y todas aparecen con el nuevo;
///   (b) el conteo total de filas por tabla NO cambia (nada se pierde ni se duplica);
///   (c) hrSample/rrInterval siguen resolviendo por `deviceIdMap` al nombre nuevo;
///   (d) re-correr el migrador es un no-op;
///   (e) una base nueva y vacía abre sin error tras `v44`.
///
/// El mapa de renombre (viejo → nuevo), medido contra `Schema.swift`:
///   strap→primary · strap-noop→primary-computed · noop-journal→journal ·
///   apple-health-noop→apple-health-computed · (source) whoop→legacy · strap-noop→primary-computed.
/// `apple-health` se queda igual (ya es neutro) y sirve de testigo: NUNCA debe cambiar.
final class PartitionRenameMigrationTests: XCTestCase {

    // MARK: - Datos de la fixture

    /// Los cuatro identificadores de partición con marca que `v44` renombra, y su destino neutro.
    private static let deviceIdRenames: [(old: String, new: String)] = [
        ("strap", "primary"),
        ("strap-noop", "primary-computed"),
        ("noop-journal", "journal"),
        ("apple-health-noop", "apple-health-computed"),
    ]
    private static let cleanDeviceId = "apple-health"   // testigo: neutro, no se toca
    private static var oldDeviceIds: [String] { deviceIdRenames.map(\.old) }
    private static var newDeviceIds: [String] { deviceIdRenames.map(\.new) }
    /// Todos los deviceId sembrados en cada tabla de texto: los 4 viejos + el testigo limpio = 5.
    private static var seededDeviceIds: [String] { oldDeviceIds + [cleanDeviceId] }

    /// Las 10 tablas con columna `deviceId` TEXT (la lista sale del esquema, igual que en `v44`).
    private static let deviceIdTextTables = [
        "sleepSession", "dailyMetric", "journal", "workout", "appleDaily",
        "metricSeries", "experiment", "dietPlan", "dietAdherence", "strengthSession",
    ]

    // MARK: - Utilidades

    private func tempPath(_ tag: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cenitstore-\(tag)-\(UUID().uuidString).sqlite").path
    }

    private func removeDatabase(at path: String) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }

    /// Construye una base con el esquema `v43` (ledger = ["v43"]) y filas bajo los valores VIEJOS en
    /// cada tabla afectada, `deviceIdMap` y las tablas de latido. La cola se libera al volver, así que
    /// el archivo queda listo para que el migrador completo (v43+v44) lo abra y aplique SÓLO `v44`.
    private func seedV43Base(at path: String) throws {
        let dbQueue = try DatabaseQueue(path: path)
        // Instala el esquema exactamente como lo hace el paquete, y estampa el ledger con "v43".
        var v43only = DatabaseMigrator()
        v43only.registerMigration("v43") { db in
            for object in CenitStore.schema { try db.execute(sql: object.sql) }
        }
        try v43only.migrate(dbQueue)

        try dbQueue.write { db in
            // Una fila por deviceId (los 4 viejos + el testigo) en CADA tabla de texto.
            for (i, dev) in Self.seededDeviceIds.enumerated() {
                let n = i + 1
                try db.execute(sql: #"INSERT INTO "sleepSession" (deviceId, startTs, endTs) VALUES (?, ?, ?)"#,
                               arguments: [dev, 1_700_000_000, 1_700_020_000])
                try db.execute(sql: #"INSERT INTO "dailyMetric" (deviceId, day) VALUES (?, ?)"#,
                               arguments: [dev, "2026-05-01"])
                try db.execute(sql: #"INSERT INTO "journal" (deviceId, day, question, answeredYes) VALUES (?, ?, ?, ?)"#,
                               arguments: [dev, "2026-05-01", "cafe", 1])
                // El `source` en el bucle de deviceId es limpio ('apple-health'): las columnas source se
                // prueban aparte, para que un renombre no se cruce con el otro.
                try db.execute(sql: #"INSERT INTO "workout" (deviceId, startTs, endTs, sport, source) VALUES (?, ?, ?, ?, ?)"#,
                               arguments: [dev, 1_700_000_000, 1_700_003_600, "Run", "apple-health"])
                try db.execute(sql: #"INSERT INTO "appleDaily" (deviceId, day) VALUES (?, ?)"#,
                               arguments: [dev, "2026-05-01"])
                try db.execute(sql: #"INSERT INTO "metricSeries" (deviceId, day, key, value) VALUES (?, ?, ?, ?)"#,
                               arguments: [dev, "2026-05-01", "steps_est", 9000])
                try db.execute(sql: #"INSERT INTO "experiment" (id, deviceId, behavior, outcome, expectedSign, startDay, windowDays, status, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"#,
                               arguments: ["exp-\(n)", dev, "cafe", "recovery", 1, "2026-05-01", 14, "running", 0])
                try db.execute(sql: #"INSERT INTO "dietPlan" (id, deviceId, nombre, idioma, ciclo, payloadJSON, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?)"#,
                               arguments: ["plan-\(n)", dev, "Plan", "es", "semanal", "{}", 0])
                try db.execute(sql: #"INSERT INTO "dietAdherence" (deviceId, day, mealId, status) VALUES (?, ?, ?, ?)"#,
                               arguments: [dev, "2026-05-01", "m1", "cumpli"])
                // strengthSession.deviceId es nullable; su `source` se deja NULL en el bucle.
                try db.execute(sql: #"INSERT INTO "strengthSession" (id, startTs, deviceId) VALUES (?, ?, ?)"#,
                               arguments: ["ss-\(n)", 1_700_000_000, dev])
            }

            // Columnas `source`: filas dedicadas con la marca heredada y el sufijo derivado. deviceId
            // limpio ('apple-health'), startTs/id distintos para no chocar con las de arriba.
            try db.execute(sql: #"INSERT INTO "workout" (deviceId, startTs, endTs, sport, source) VALUES (?, ?, ?, ?, ?)"#,
                           arguments: ["apple-health", 1_700_100_000, 1_700_103_600, "Ride", "whoop"])
            try db.execute(sql: #"INSERT INTO "workout" (deviceId, startTs, endTs, sport, source) VALUES (?, ?, ?, ?, ?)"#,
                           arguments: ["apple-health", 1_700_200_000, 1_700_203_600, "detected", "strap-noop"])
            try db.execute(sql: #"INSERT INTO "strengthSession" (id, startTs, deviceId, source) VALUES (?, ?, ?, ?)"#,
                           arguments: ["ss-src-legacy", 1_700_300_000, "apple-health", "whoop"])
            try db.execute(sql: #"INSERT INTO "strengthSession" (id, startTs, deviceId, source) VALUES (?, ?, ?, ?)"#,
                           arguments: ["ss-src-computed", 1_700_400_000, "apple-health", "strap-noop"])

            // deviceIdMap: los 4 viejos con enteros distintos + el testigo. Los latidos guardan el
            // entero, así que renombrar el texto los re-etiqueta sin tocarlos.
            for (i, dev) in Self.seededDeviceIds.enumerated() {
                try db.execute(sql: "INSERT INTO deviceIdMap (deviceId, intId) VALUES (?, ?)",
                               arguments: [dev, i + 1])
            }
            // hrSample/rrInterval bajo el entero de 'strap' (1) y del testigo 'apple-health' (5).
            try db.execute(sql: #"INSERT INTO "hrSample" (deviceId, ts, bpm) VALUES (?, ?, ?)"#, arguments: [1, 1_700_000_000, 60])
            try db.execute(sql: #"INSERT INTO "hrSample" (deviceId, ts, bpm) VALUES (?, ?, ?)"#, arguments: [5, 1_700_000_001, 62])
            try db.execute(sql: #"INSERT INTO "rrInterval" (deviceId, ts, rrMs) VALUES (?, ?, ?)"#, arguments: [1, 1_700_000_000, 800])
            try db.execute(sql: #"INSERT INTO "rrInterval" (deviceId, ts, rrMs) VALUES (?, ?, ?)"#, arguments: [5, 1_700_000_001, 820])
        }
    }

    private func count(_ db: Database, _ sql: String, _ args: StatementArguments = []) throws -> Int {
        try Int.fetchOne(db, sql: sql, arguments: args) ?? -1
    }

    // MARK: - (a) + (b) · cada valor viejo desaparece, el nuevo aparece, el conteo total no cambia

    func testV44RenamesEveryBrandedPartitionWithoutLosingRows() throws {
        let path = tempPath("v44")
        defer { removeDatabase(at: path) }
        try seedV43Base(at: path)

        let dbQueue = try DatabaseQueue(path: path)
        // Conteos por tabla ANTES de v44 (la fixture ya está sembrada a v43).
        let before = try dbQueue.read { db -> [String: Int] in
            var m: [String: Int] = [:]
            for t in Self.deviceIdTextTables { m[t] = try self.count(db, #"SELECT COUNT(*) FROM "\#(t)""#) }
            m["deviceIdMap"] = try self.count(db, "SELECT COUNT(*) FROM deviceIdMap")
            m["hrSample"] = try self.count(db, #"SELECT COUNT(*) FROM "hrSample""#)
            m["rrInterval"] = try self.count(db, #"SELECT COUNT(*) FROM "rrInterval""#)
            return m
        }
        // Conteos derivados a mano: 5 filas por tabla de texto (4 viejos + testigo); workout suma 2
        // filas de source y strengthSession otras 2 → 7 cada una. deviceIdMap 5, latidos 2 y 2.
        XCTAssertEqual(before["dailyMetric"], 5)
        XCTAssertEqual(before["workout"], 7)
        XCTAssertEqual(before["strengthSession"], 7)
        XCTAssertEqual(before["deviceIdMap"], 5)
        XCTAssertEqual(before["hrSample"], 2)

        try CenitStore.makeMigrator().migrate(dbQueue)

        try dbQueue.read { db in
            for table in Self.deviceIdTextTables {
                // (a) ningún valor viejo sobrevive.
                for old in Self.oldDeviceIds {
                    XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE deviceId = ?"#, [old]),
                                   0, "\(table): quedó una fila bajo el deviceId viejo '\(old)'")
                }
                // (a) cada valor viejo reaparece bajo su nombre nuevo, misma cantidad (aquí, 1).
                for rename in Self.deviceIdRenames {
                    XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE deviceId = ?"#, [rename.new]),
                                   1, "\(table): falta la fila re-etiquetada a '\(rename.new)'")
                }
                // El testigo limpio nunca cambia.
                XCTAssertGreaterThanOrEqual(
                    try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE deviceId = ?"#, [Self.cleanDeviceId]),
                    1, "\(table): el testigo 'apple-health' desapareció")
                // (b) el conteo total por tabla no cambia.
                XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)""#),
                               before[table], "\(table): cambió el número de filas")
            }

            // Columna source: la marca y el sufijo se reescriben; el conteo total no cambia.
            for table in ["workout", "strengthSession"] {
                XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE source IN ('whoop','strap-noop')"#),
                               0, "\(table): quedó un source viejo")
                XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE source = 'legacy'"#),
                               1, "\(table): falta el source 'legacy'")
                XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE source = 'primary-computed'"#),
                               1, "\(table): falta el source 'primary-computed'")
                XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)""#), before[table])
            }

            // deviceIdMap: ningún texto viejo, cada nuevo con el MISMO entero que tenía el viejo.
            for old in Self.oldDeviceIds {
                XCTAssertEqual(try self.count(db, "SELECT COUNT(*) FROM deviceIdMap WHERE deviceId = ?", [old]), 0)
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'primary'"), 1,
                           "'primary' debe heredar el entero de 'strap'")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'primary-computed'"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'journal'"), 3)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'apple-health-computed'"), 4)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'apple-health'"), 5,
                           "el testigo conserva su entero")

            // (c) los latidos no se tocaron: siguen bajo el entero 1 (ahora 'primary') y 5 ('apple-health').
            XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "hrSample""#), before["hrSample"])
            XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "hrSample" WHERE deviceId = 1"#), 1)
            XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "rrInterval" WHERE deviceId = 1"#), 1)
        }
    }

    // MARK: - (d) · re-correr el migrador es un no-op

    func testV44IsIdempotent() throws {
        let path = tempPath("v44-idem")
        defer { removeDatabase(at: path) }
        try seedV43Base(at: path)

        let dbQueue = try DatabaseQueue(path: path)
        try CenitStore.makeMigrator().migrate(dbQueue)
        let firstPass = try dbQueue.read { db -> [Int] in
            try Self.deviceIdTextTables.map { try self.count(db, #"SELECT COUNT(*) FROM "\#($0)""#) }
        }
        // Segunda corrida: v44 ya está en el ledger → no ejecuta nada; el estado es idéntico.
        try CenitStore.makeMigrator().migrate(dbQueue)
        try dbQueue.read { db in
            for old in Self.oldDeviceIds {
                for table in Self.deviceIdTextTables {
                    XCTAssertEqual(try self.count(db, #"SELECT COUNT(*) FROM "\#(table)" WHERE deviceId = ?"#, [old]), 0)
                }
            }
            let secondPass = try Self.deviceIdTextTables.map { try self.count(db, #"SELECT COUNT(*) FROM "\#($0)""#) }
            XCTAssertEqual(secondPass, firstPass, "re-correr el migrador no cambia una sola fila")
        }
    }

    // MARK: - (c) + no-regresión · un read por el deviceId NUEVO devuelve lo sembrado bajo el viejo

    func testReadsByNewDeviceIdReturnTheMigratedData() async throws {
        let path = tempPath("v44-read")
        defer { removeDatabase(at: path) }
        try seedV43Base(at: path)

        // Abrir el store corre el migrador completo → aplica v44; luego se lee por el nombre NUEVO.
        let store = try await CenitStore(path: path)

        // journal: sembrado bajo 'noop-journal' → se lee por 'journal'.
        let journal = try await store.journalEntries(deviceId: "journal", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(journal.first?.question, "cafe")

        // metricSeries: sembrado bajo 'strap' → se lee por 'primary'.
        let series = try await store.metricSeries(deviceId: "primary", key: "steps_est", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(series.map(\.value), [9000])

        // dailyMetric bajo el computado 'strap-noop' → se lee por 'primary-computed'.
        let daily = try await store.dailyMetrics(deviceId: "primary-computed", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(daily.count, 1)

        // (c) los latidos sembrados bajo el entero de 'strap' se leen ahora por 'primary'.
        let beats = try await store.hrSamples(deviceId: "primary", from: 0, to: 2_000_000_000, limit: 100)
        XCTAssertEqual(beats.map(\.bpm), [60])
        let intervals = try await store.rrIntervals(deviceId: "primary", from: 0, to: 2_000_000_000, limit: 100)
        XCTAssertEqual(intervals.map(\.rrMs), [800])

        // El viejo nombre ya no devuelve nada (la partición se renombró de una vez).
        let empty = try await store.journalEntries(deviceId: "noop-journal", from: "2026-05-01", to: "2026-05-01")
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - (e) · una base nueva y vacía abre sin error tras v44

    func testFreshEmptyDatabaseOpensCleanlyAfterV44() async throws {
        let store = try await CenitStore.inMemory()
        XCTAssertTrue(CenitStore.makeMigrator().migrations.contains("v44"))
        // Sin filas viejas que migrar: cualquier read responde vacío, sin lanzar.
        let journal = try await store.journalEntries(deviceId: "journal", from: "2026-05-01", to: "2026-05-01")
        XCTAssertTrue(journal.isEmpty)
    }
}
