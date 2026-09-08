import XCTest
import GRDB
import CenitTraining
import BiometricStreams
@testable import CenitStore

/// Shape of the migrator itself, plus the round-trips through the public API that used to hang off a
/// per-step migration test. There is one migration now (FER-393), so «does column X appear at step N»
/// has no meaning: the schema's shape is pinned wholesale by `LegacyFixtureTests` (M4) and the upgrade
/// path by the real fixture (M1/M2/M3). What survives here is what those two can't say.
final class MigrationTests: XCTestCase {

    // MARK: - M5 · identifier, count and the flag that could erase the owner's database

    /// Exactly one registered migration, named `v43`. The name is load-bearing: the owner's ledger
    /// already lists `v1`…`v43`, so `v43` is reported as applied and nothing runs on their file.
    func testMigratorRegistersTheSingleMigration() {
        XCTAssertEqual(CenitStore.makeMigrator().migrations, ["v43"])
        XCTAssertEqual(CenitStoreInfo.schemaVersion, 1)
        XCTAssertEqual(CenitStoreInfo.latestMigration, "v43")
    }

    /// `eraseDatabaseOnSchemaChange` must stay off. With it on, GRDB sees 43 applied identifiers it
    /// doesn't know about, decides the schema changed, and wipes the file — every byte the owner has.
    func testMigratorNeverErasesOnSchemaChange() {
        XCTAssertFalse(CenitStore.makeMigrator().eraseDatabaseOnSchemaChange)
    }

    // MARK: - The house tool for v44 and beyond

    /// `addColumnIfMissing` is the guard every future `ADD COLUMN` goes through: it adds an absent
    /// column and stays silent on a second call, instead of throwing «duplicate column» against a
    /// database that already grew it.
    func testAddColumnIfMissingIsIdempotent() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.create(table: "t") { $0.column("id", .integer).primaryKey() }

            try CenitStore.addColumnIfMissing(db, "note", on: "t") { $0.add(column: "note", .text) }
            XCTAssertTrue(try db.columns(in: "t").contains { $0.name == "note" },
                          "the first call must add the column")

            try CenitStore.addColumnIfMissing(db, "note", on: "t") { $0.add(column: "note", .text) }
            XCTAssertEqual(try db.columns(in: "t").filter { $0.name == "note" }.count, 1,
                           "the second call is a no-op — one column, no throw")
        }
    }

    // MARK: - Maintenance

    /// `vacuum()` runs on a real file handle without throwing (VACUUM cannot run inside a transaction)
    /// and leaves the file queryable.
    func testVacuumRunsOnAFileStore() async throws {
        let path = NSTemporaryDirectory() + "cenitstore-vacuum-\(UUID().uuidString).sqlite"
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        let store = try await CenitStore(path: path)
        try await store.setCursor("anything", 1)
        try await store.vacuum()
        let pages = try await store.pageCountForTest()
        XCTAssertGreaterThan(pages, 0)
    }

    // MARK: - Round-trips through the public API

    /// Learned aliases round-trip, and re-mapping a name overwrites: one mapping per normalized name.
    func testLearnedAliasRoundTripsAndOverwrites() async throws {
        let store = try await CenitStore.inMemory()
        var aliases = try await store.learnedExerciseAliases()
        XCTAssertTrue(aliases.isEmpty)

        try await store.saveLearnedExerciseAlias(name: "press plano", exerciseId: "Some_Id", ts: 100)
        try await store.saveLearnedExerciseAlias(name: "sentadilla rara", exerciseId: "Squat_Id", ts: 100)
        aliases = try await store.learnedExerciseAliases()
        XCTAssertEqual(aliases["press plano"], "Some_Id")
        XCTAssertEqual(aliases["sentadilla rara"], "Squat_Id")

        try await store.saveLearnedExerciseAlias(name: "press plano", exerciseId: "Other_Id", ts: 200)
        aliases = try await store.learnedExerciseAliases()
        XCTAssertEqual(aliases["press plano"], "Other_Id")
        XCTAssertEqual(aliases.count, 2)
    }

    /// The chosen equivalent option round-trips; a mark without a specific option reads back nil.
    func testDietOptionIndexRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-06-01", mealId: "m1", status: .cumpli, optionIndex: 1),
            deviceId: "noop-journal")
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-06-01", mealId: "m2", status: .salte),
            deviceId: "noop-journal")
        let rows = try await store.dietAdherence(deviceId: "noop-journal", day: "2026-06-01")
        XCTAssertEqual(rows.first(where: { $0.mealId == "m1" })?.optionIndex, 1)
        XCTAssertNil(rows.first(where: { $0.mealId == "m2" })?.optionIndex)
    }

    /// Superset grouping round-trips in `position` order: `[1, 1, nil]` = a two-exercise superset
    /// followed by a standalone exercise.
    func testSupersetGroupRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let routine = Routine(id: "r1", name: "Empuje", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "r1", exerciseId: "ex1", position: 0, targetSets: 4, supersetGroup: 1),
            RoutineExercise(id: "b", routineId: "r1", exerciseId: "ex2", position: 1, targetSets: 4, supersetGroup: 1),
            RoutineExercise(id: "c", routineId: "r1", exerciseId: "ex3", position: 2, targetSets: 3, supersetGroup: nil),
        ]
        try await store.saveRoutine(routine, exercises: exs)
        let read = try await store.routineExercises(routineId: "r1")
        XCTAssertEqual(read.map(\.supersetGroup), [1, 1, nil])
    }

    /// The confidence tiers round-trip, and a later partial pass carrying nil preserves them —
    /// the same per-column monotonic rule every other `dailyMetric` column follows.
    func testConfidenceTiersRoundTripAndStayMonotonic() async throws {
        let store = try await CenitStore.inMemory()
        let day = DailyMetric(day: "2026-07-02", totalSleepMin: 420, efficiency: 0.9, deepMin: 70,
                              remMin: 90, lightMin: 200, disturbances: nil, restingHr: 52,
                              avgHrv: 65, recovery: 71, strain: 13.1, exerciseCount: 1,
                              effortConfidence: "solid", restConfidence: "building")
        _ = try await store.upsertDailyMetrics([day], deviceId: "dev1")

        var rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.effortConfidence, "solid")
        XCTAssertEqual(rows.first?.restConfidence, "building")

        let partial = day.with(effortConfidence: .set(nil), restConfidence: .set(nil))
        _ = try await store.upsertDailyMetrics([partial], deviceId: "dev1")
        rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.effortConfidence, "solid", "a nil upsert preserves, never blanks")
        XCTAssertEqual(rows.first?.restConfidence, "building", "a nil upsert preserves, never blanks")

        let updated = day.with(restConfidence: .set("solid"))
        _ = try await store.upsertDailyMetrics([updated], deviceId: "dev1")
        rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.restConfidence, "solid", "a non-nil upsert overwrites")
    }

    /// The set-mode storage contract: a standard set persists as NULL (never the literal string), a
    /// non-standard one as its raw value, and the session provenance columns survive the round-trip.
    func testSetModeAndSessionProvenanceRoundTrip() async throws {
        let store = try await CenitStore.inMemory()
        let routine = Routine(id: "r1", name: "Empuje", createdTs: 0, updatedTs: 0)
        let re = RoutineExercise(id: "re1", routineId: "r1", exerciseId: "bench-press", position: 0,
                                 targetSets: 3, sets: [
                                    RoutineSet(id: "a", position: 0, reps: 8, weightKg: 80),
                                    RoutineSet(id: "b", position: 1, reps: 8, weightKg: 80, mode: .amrap)
                                 ], progressionUseRPE: true)
        try await store.saveRoutine(routine, exercises: [re])
        let back = try await store.routineExercises(routineId: "r1")
        XCTAssertEqual(back.first?.progressionUseRPE, true)
        XCTAssertEqual(back.first?.sets.map(\.mode) ?? [], [SetMode.standard, .amrap])

        let session = StrengthSession(id: "s1", routineId: "r1", startTs: 1000, endTs: 4120, strain: 11.4,
                                      strainSource: .rpe, sessionRpe: 8, sessionRpeSource: .prefill,
                                      trimpPerAU: 0.29, source: "hevy", title: "Push Day",
                                      programWeek: 5, deload: true)
        let sets = [
            SetEntry(id: "e1", sessionId: "s1", exerciseId: "bench-press", position: 0, weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "e2", sessionId: "s1", exerciseId: "bench-press", position: 1, weightKg: 64, reps: 9, done: true, ts: 1200, mode: .drop)
        ]
        try await store.saveSession(session, sets: sets)
        let saved = try await store.session(id: "s1")
        XCTAssertEqual(saved?.strainSource, .rpe)
        XCTAssertEqual(saved?.sessionRpe, 8)
        XCTAssertEqual(saved?.sessionRpeSource, .prefill)
        XCTAssertEqual(saved?.trimpPerAU, 0.29)
        XCTAssertEqual(saved?.source, "hevy")
        XCTAssertEqual(saved?.title, "Push Day")
        XCTAssertEqual(saved?.programWeek, 5)
        XCTAssertEqual(saved?.deload, true)
        let savedSets = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(savedSets.map(\.mode), [SetMode.standard, .drop])
        let rawModes = try await store.dbWriter.read { db in
            try String?.fetchAll(db, sql: "SELECT mode FROM setEntry WHERE sessionId = 's1' ORDER BY position")
        }
        XCTAssertEqual(rawModes, [nil, "drop"])
    }
}
