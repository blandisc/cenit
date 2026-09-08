import XCTest
import GRDB
import CenitTraining
@testable import CenitStore

/// FER-393 · la red de la migración única.
///
/// El único dispositivo con datos reales es el de quien usa la app, y su ledger `grdb_migrations`
/// trae los 43 identificadores de la historia anterior. `legacy-fixture.sqlite` es exactamente esa
/// forma: una base creada y migrada por el código anterior, con al menos una fila en cada tabla viva.
/// Estas pruebas dicen, juntas, que esa base abre con el código de hoy **sin que se ejecute una sola
/// sentencia de esquema, sin que cambie una fila, y con sus datos legibles por la API pública**.
///
/// Si M2 falla, no se entrega: es la que demuestra que la migración no corrió.
final class LegacyFixtureTests: XCTestCase {

    // MARK: - Utilidades

    /// Copia la fixture a un archivo temporal. Abrirla en su sitio dejaría `-wal`/`-shm` junto al
    /// recurso y ensuciaría el árbol.
    private func fixtureCopy(_ tag: String) throws -> String {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "legacy-fixture", withExtension: "sqlite"),
                                   "falta el recurso legacy-fixture.sqlite")
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cenitstore-\(tag)-\(UUID().uuidString).sqlite").path
        try FileManager.default.copyItem(atPath: source.path, toPath: path)
        return path
    }

    private func removeDatabase(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    /// Mira el archivo directamente, sin pasar por el actor: estas pruebas comparan lo que hay EN EL
    /// DISCO antes y después de abrirlo. Es síncrona a propósito — dentro de una prueba `async`, la
    /// lectura de GRDB elegiría su variante asíncrona.
    private func inspect<T>(_ path: String, _ block: (Database) throws -> T) throws -> T {
        try DatabaseQueue(path: path).read(block)
    }

    /// El esquema, como tuplas ordenadas y comparables. Excluye el ledger de GRDB y su autoíndice:
    /// GRDB lo crea por su cuenta y M2 lo revisa aparte.
    private struct SchemaEntry: Equatable, Comparable, CustomStringConvertible {
        let type: String
        let name: String
        let tableName: String
        let sql: String?
        static func < (a: SchemaEntry, b: SchemaEntry) -> Bool {
            (a.type, a.name) < (b.type, b.name)
        }
        var description: String { "\(type) \(name) on \(tableName): \(sql ?? "<sin sql>")" }
    }

    private func schemaEntries(_ db: Database) throws -> [SchemaEntry] {
        try Row.fetchAll(db, sql: "SELECT type, name, tbl_name, sql FROM sqlite_master")
            .map { SchemaEntry(type: $0["type"], name: $0["name"], tableName: $0["tbl_name"], sql: $0["sql"]) }
            .filter { $0.tableName != "grdb_migrations" }
            .sorted()
    }

    private func userTableNames(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name <> 'grdb_migrations' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)
    }

    private func rowCounts(_ db: Database) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in try userTableNames(db) {
            counts[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table)\"") ?? 0
        }
        return counts
    }

    private func appliedIdentifiers(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
    }

    // MARK: - M1 · la base instalada abre sin cambiar

    func testOpeningTheLegacyDatabaseChangesNeitherSchemaNorRows() async throws {
        let path = try fixtureCopy("m1")
        defer { removeDatabase(at: path) }

        let before = try inspect(path) { db in
            (schema: try schemaEntries(db), counts: try rowCounts(db))
        }
        XCTAssertEqual(before.counts.count, 29, "la fixture debe traer las 29 tablas vivas")
        XCTAssertTrue(before.counts.values.allSatisfy { $0 > 0 },
                      "cada tabla viva debe traer al menos una fila: \(before.counts)")

        _ = try await CenitStore(path: path)   // el código de hoy abre y migra

        let after = try inspect(path) { db in
            (schema: try schemaEntries(db), counts: try rowCounts(db))
        }
        XCTAssertEqual(after.schema, before.schema, "abrir no puede tocar el esquema")
        XCTAssertEqual(after.counts, before.counts, "abrir no puede tocar una sola fila")
    }

    // MARK: - M2 · v43 (el esquema) NO re-corre; sólo v44 (renombre de datos) se aplica

    /// La prueba que protege los datos: en la base del dueño, `v43` está en el ledger y NO vuelve a
    /// correr (re-instalar el esquema es justo lo que borraría/reconstruiría sus tablas). La única
    /// migración nueva que se aplica es `v44`, que sólo reescribe datos (FER-479): el ledger gana
    /// exactamente ese identificador, ni uno más.
    func testOpeningTheLegacyDatabaseRunsOnlyTheDataRenameMigration() async throws {
        let path = try fixtureCopy("m2")
        defer { removeDatabase(at: path) }

        let before = try inspect(path) { try self.appliedIdentifiers($0) }
        XCTAssertEqual(before.count, 43)
        XCTAssertEqual(Set(before), Set((1...43).map { "v\($0)" }))

        _ = try await CenitStore(path: path)

        let after = try inspect(path) { try self.appliedIdentifiers($0) }
        XCTAssertEqual(Set(after), Set(before).union(["v44"]),
                       "sobre la base del dueño sólo corre v44: v43 se lee como aplicado y no re-instala")
        XCTAssertEqual(after.count, 44, "el ledger gana exactamente un identificador nuevo")
    }

    // MARK: - M3 · los datos se leen de vuelta

    func testLegacyDataReadsBackThroughThePublicAPI() async throws {
        let path = try fixtureCopy("m3")
        defer { removeDatabase(at: path) }
        let store = try await CenitStore(path: path)

        let days = try await store.dailyMetrics(deviceId: "apple-health",
                                                from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.totalSleepMin, 420)
        XCTAssertEqual(days.first?.restingHr, 55)
        XCTAssertEqual(days.first?.avgHrv, 40)
        XCTAssertEqual(days.first?.strain, 5.0)
        XCTAssertEqual(days.first?.spo2Pct, 96)
        XCTAssertEqual(days.first?.effortConfidence, "solid")

        let sleeps = try await store.sleepSessions(deviceId: "apple-health",
                                                   from: 1_700_000_000, to: 1_700_020_000, limit: 10)
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertEqual(sleeps.first?.endTs, 1_700_020_000)
        XCTAssertEqual(sleeps.first?.restingHr, 54)

        let series = try await store.metricSeries(deviceId: "apple-health", key: "steps_est",
                                                  from: "2026-05-01", to: "2026-05-02")
        XCTAssertEqual(series, [MetricPoint(day: "2026-05-01", key: "steps_est", value: 9000),
                                MetricPoint(day: "2026-05-02", key: "steps_est", value: 11000)])

        // La partición de journal quedó re-etiquetada por v44 (`noop-journal`→`journal`, FER-479):
        // se lee por el nombre NUEVO, que es lo que la app usa tras la migración.
        let journal = try await store.journalEntries(deviceId: "journal",
                                                     from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(journal, [JournalEntry(day: "2026-05-01", question: "cafe",
                                              answeredYes: true, notes: "nota")])

        let workouts = try await store.workouts(deviceId: "apple-health",
                                                from: 1_700_000_000, to: 1_700_000_000, limit: 10)
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.sport, "Run")
        XCTAssertEqual(workouts.first?.avgHr, 140)
        XCTAssertEqual(workouts.first?.distanceM, 10000)

        let apple = try await store.appleDaily(deviceId: "apple-health",
                                               from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(apple.count, 1)
        XCTAssertEqual(apple.first?.steps, 9000)
        XCTAssertEqual(apple.first?.vo2max, 48)

        let beats = try await store.hrSamples(deviceId: "apple-health", from: 0,
                                              to: 2_000_000_000, limit: 100)
        XCTAssertEqual(beats.map(\.bpm), [60, 62])
        let intervals = try await store.rrIntervals(deviceId: "apple-health", from: 0,
                                                    to: 2_000_000_000, limit: 100)
        XCTAssertEqual(intervals.map(\.rrMs), [800, 820])
        let beatCount = try await store.sampleCounts().hr
        XCTAssertEqual(beatCount, 2)

        let marker = try await store.cursor("fixture_cursor")
        XCTAssertEqual(marker, 4242)
        let mark = try await store.highwater("hr")
        XCTAssertEqual(mark, 1_700_000_060)

        let routines = try await store.routines()
        XCTAssertEqual(routines.map(\.id), ["routine-1"])
        let routineExercises = try await store.routineExercises(routineId: "routine-1")
        XCTAssertEqual(routineExercises.map(\.exerciseId), ["ex-custom"])
        let session = try await store.session(id: "sess-1")
        XCTAssertEqual(session?.strain, 8.0)
        XCTAssertEqual(session?.title, "Día A")
        let reps = try await store.setEntries(sessionId: "sess-1").map(\.reps)
        XCTAssertEqual(reps, [8])
        let programName = try await store.program()?.name
        XCTAssertEqual(programName, "Bloque")
        let inProgress = try await store.inProgressSession()?.id
        XCTAssertEqual(inProgress, "wip-1")
        let customIds = try await store.customExercises().map(\.id)
        XCTAssertEqual(customIds, ["ex-custom"])
        let dietPlan = try await store.activeDietPlan(deviceId: "apple-health")?.id
        XCTAssertEqual(dietPlan, "plan-1")
        let experiments = try await store.experiments(deviceId: "apple-health").map(\.id)
        XCTAssertEqual(experiments, ["exp-1"])
    }

    // MARK: - M4 · la forma del esquema en una instalación nueva

    /// Una instalación nueva crea las 29 tablas de la base de referencia, sin omitir ninguna: las
    /// diez tablas muertas de la etapa anterior ya no existían cuando se generó la fixture, y de las
    /// supervivientes todas siguen teniendo quién las lea o las escriba.
    func testFreshInstallSchemaMatchesTheReferenceDump() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cenitstore-m4-\(UUID().uuidString).sqlite").path
        defer { removeDatabase(at: path) }
        _ = try await CenitStore(path: path)

        let fresh = try inspect(path) { try self.schemaEntries($0) }

        let reference = try fixtureCopy("m4-ref")
        defer { removeDatabase(at: reference) }
        let expected = try inspect(reference) { try self.schemaEntries($0) }

        XCTAssertEqual(fresh, expected,
                       "el esquema de una instalación nueva debe ser idéntico al de la base de referencia")
    }

    /// El volcado `.schema` que se commiteó junto a la fixture no puede quedarse atrás: cada `CREATE`
    /// que instala la migración tiene que aparecer ahí, carácter por carácter.
    func testEveryInstalledObjectAppearsVerbatimInTheReferenceDump() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "legacy-schema", withExtension: "sql"),
                                "falta el recurso legacy-schema.sql")
        let dump = try String(contentsOf: url, encoding: .utf8)
        for object in CenitStore.schema {
            XCTAssertTrue(dump.contains(object.sql + ";"),
                          "el volcado de referencia no trae verbatim el CREATE de \(object.name)")
        }
        XCTAssertEqual(CenitStore.schema.count, 37, "29 tablas + 8 índices con nombre")
    }
}
