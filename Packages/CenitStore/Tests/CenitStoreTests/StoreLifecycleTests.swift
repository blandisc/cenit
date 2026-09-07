import XCTest
import BiometricStreams
@testable import CenitStore

/// Apertura, forma del esquema recién instalado, los dos backends y el mantenimiento.
final class StoreLifecycleTests: XCTestCase {

    private func tmpPath(_ tag: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cenitstore-\(tag)-\(UUID().uuidString).sqlite").path
    }

    private func removeDatabase(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    // MARK: - Apertura

    func testAnInMemoryStoreComesUpMigrated() async throws {
        let tables = try await CenitStore.inMemory().tableNames()
        for expected in ["hrSample", "rrInterval", "cursors", "dailyMetric", "metricSeries"] {
            XCTAssertTrue(tables.contains(expected), "falta \(expected)")
        }
    }

    /// Las tablas de la etapa anterior que ya se habían eliminado no vuelven a nacer en una
    /// instalación nueva.
    func testTheRetiredTablesAreNotRecreated() async throws {
        let tables = try await CenitStore.inMemory().tableNames()
        for gone in ["device", "event", "battery", "rawBatch", "spo2Sample", "skinTempSample",
                     "respSample", "gravitySample", "stepSample", "circadianPhase"] {
            XCTAssertFalse(tables.contains(gone), "\(gone) no debe existir")
        }
    }

    func testOpeningAPathCreatesTheFile() async throws {
        let path = tmpPath("file-init")
        defer { removeDatabase(at: path) }
        let store = try await CenitStore(path: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let hasDailyMetric = try await store.tableNames().contains("dailyMetric")
        XCTAssertTrue(hasDailyMetric)
    }

    // MARK: - Forma

    func testTheBeatTablesKeepTheirNaturalKeys() async throws {
        let store = try await CenitStore.inMemory()
        let beatKey = try await store.primaryKeyColumns("hrSample")
        XCTAssertEqual(beatKey, ["deviceId", "ts"])
        let intervalKey = try await store.primaryKeyColumns("rrInterval")
        XCTAssertEqual(intervalKey, ["deviceId", "ts", "rrMs"])
        let markKey = try await store.primaryKeyColumns("cursors")
        XCTAssertEqual(markKey, ["name"])
    }

    /// La marca de subida de una función de servidor retirada no existe en las tablas de latido, y no
    /// se vuelve a crear: no hay a dónde subir nada.
    func testTheBeatTablesCarryNoUploadFlag() async throws {
        let store = try await CenitStore.inMemory()
        let beatHasFlag = try await store.columnNamesForTest(table: "hrSample").contains("synced")
        XCTAssertFalse(beatHasFlag)
        let intervalHasFlag = try await store.columnNamesForTest(table: "rrInterval").contains("synced")
        XCTAssertFalse(intervalHasFlag)
    }

    func testTheNamedIndexesAreInstalled() async throws {
        let store = try await CenitStore.inMemory()
        let seriesIndexes = try await store.indexNamesForTest(table: "metricSeries")
        XCTAssertTrue(seriesIndexes.contains("idx_metricSeries_device_key_day"))

        let setIndexes = try await store.indexNamesForTest(table: "setEntry")
        XCTAssertEqual(setIndexes.intersection(["idx_setEntry_session_pos",
                                                "idx_setEntry_exercise_ts"]).count, 2)
    }

    // MARK: - Backends

    /// Con el pool, los PRAGMAs de escritura corren también en las conexiones de sólo lectura si no se
    /// les guarda; entonces abrir un lector lanza y muere toda la lectura del tablero. Con la cola no
    /// se nota, así que la prueba tiene que ir por el pool.
    func testThePoolReadsAndWritesLikeTheQueue() async throws {
        let queuePath = tmpPath("queue"), poolPath = tmpPath("pool")
        defer { removeDatabase(at: queuePath); removeDatabase(at: poolPath) }

        let queueStore = try await CenitStore(path: queuePath)
        let poolStore = try await CenitStore(path: poolPath, backend: .pool(maxReaders: 2))
        let beats = Streams(hr: [HRSample(ts: 100, bpm: 60), HRSample(ts: 200, bpm: 61)])
        for store in [queueStore, poolStore] {
            _ = try await store.insert(beats, deviceId: "A")
            _ = try await store.upsertMetricSeries(
                [MetricPoint(day: "2026-05-01", key: "steps", value: 9000)], deviceId: "A")
        }
        let fromQueue = try await queueStore.hrSamples(deviceId: "A", from: 0, to: 1000, limit: 10)
        let fromPool = try await poolStore.hrSamples(deviceId: "A", from: 0, to: 1000, limit: 10)
        XCTAssertEqual(fromQueue, fromPool)
        let queueKeys = try await queueStore.metricKeys(deviceId: "A")
        let poolKeys = try await poolStore.metricKeys(deviceId: "A")
        XCTAssertEqual(queueKeys, poolKeys)
    }

    func testCheckpointRunsOnThePool() async throws {
        let path = tmpPath("checkpoint")
        defer { removeDatabase(at: path) }
        let store = try await CenitStore(path: path, backend: .pool(maxReaders: 2))
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1, bpm: 60)]), deviceId: "A")
        try await store.checkpointWAL()
    }

    // MARK: - Mantenimiento

    func testVacuumLeavesTheFileQueryable() async throws {
        let path = tmpPath("vacuum")
        defer { removeDatabase(at: path) }
        let store = try await CenitStore(path: path)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 1, bpm: 60)]), deviceId: "A")
        try await store.vacuum()
        let pages = try await store.pageCountForTest()
        XCTAssertGreaterThan(pages, 0)
    }
}
