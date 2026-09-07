import XCTest
@testable import CenitStore

/// Los días y las noches puntuados. Aquí vive la regla más delicada del paquete: un recálculo parcial
/// no puede blanquear historia.
final class DayCacheStoreTests: XCTestCase {

    /// El día base del oráculo: sueño, pulso de reposo, variabilidad, recuperación y carga; el resto
    /// nulo.
    private func baseDay(_ day: String = "2026-05-01") -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 40, recovery: 66,
                    strain: 5.0, exerciseCount: nil)
    }

    /// Un día con TODO nulo salvo lo que se pase — la forma de una pasada parcial del motor.
    private func partialDay(_ day: String = "2026-05-01", restingHr: Int? = nil,
                            strain: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: restingHr, avgHrv: nil,
                    recovery: nil, strain: strain, exerciseCount: nil)
    }

    private func storedDay(_ store: CenitStore, _ day: String = "2026-05-01") async throws -> DailyMetric? {
        try await store.dailyMetrics(deviceId: "A", from: day, to: day).first
    }

    private func seeded(_ day: String = "2026-05-01") async throws -> CenitStore {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([baseDay(day)], deviceId: "A")
        return store
    }

    // MARK: - La regla monótona

    /// El motor re-puntúa cada noche de su ventana en cada pasada, y una noche cuya sesión de sueño
    /// aún no se detecta vuelve con nulos. Si el nulo pisara lo guardado, la pasada parcial borraría
    /// un día entero de historia.
    func testAPartialPassFillsWithoutBlanking() async throws {
        let store = try await seeded()
        _ = try await store.upsertDailyMetrics([partialDay(restingHr: 52)], deviceId: "A")

        let row = try await storedDay(store)
        XCTAssertEqual(row?.restingHr, 52, "lo entrante manda cuando trae algo")
        XCTAssertEqual(row?.totalSleepMin, 420, "lo guardado sobrevive cuando lo entrante es nulo")
        XCTAssertEqual(row?.avgHrv, 40)
        XCTAssertEqual(row?.recovery, 66)
        XCTAssertEqual(row?.strain, 5.0)
    }

    // MARK: - La carga, que NO es un COALESCE

    func testAScoredWorkoutAlwaysWins() async throws {
        let store = try await seeded()
        _ = try await store.upsertDailyMetrics([partialDay(strain: 9.0)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 9.0)
    }

    func testAPersistedLoadDoesNotDegradeToRest() async throws {
        let store = try await seeded()
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 5.0)
    }

    func testAPersistedLoadDoesNotDegradeToMissing() async throws {
        let store = try await seeded()
        _ = try await store.upsertDailyMetrics([partialDay(strain: nil)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 5.0)
    }

    /// El único caso que NO es `COALESCE`, y la razón de que la regla no se pueda escribir con uno: un
    /// 0 guardado casi siempre es un falso descanso de una pasada sin pulso, y volver a «falta el
    /// dato» es más honesto que sostenerlo.
    func testAStoredZeroCanGoBackToMissing() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        _ = try await store.upsertDailyMetrics([partialDay(strain: nil)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertNil(strain)
    }

    func testRestCanBeRecordedOverMissing() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([partialDay(strain: nil)], deviceId: "A")
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 0.0)
    }

    func testMissingStaysMissing() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([partialDay(strain: nil)], deviceId: "A")
        _ = try await store.upsertDailyMetrics([partialDay(strain: nil)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertNil(strain)
    }

    func testALoadOverAStoredZeroWins() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        _ = try await store.upsertDailyMetrics([partialDay(strain: 7.0)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 7.0)
    }

    func testRestStaysRest() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        _ = try await store.upsertDailyMetrics([partialDay(strain: 0.0)], deviceId: "A")
        let strain = try await storedDay(store)?.strain
        XCTAssertEqual(strain, 0.0)
    }

    /// El mismo día repetido dentro de UN lote se aplica en orden, no se colapsa quedándose con el
    /// último: colapsar perdería lo que sólo traía la primera aparición.
    func testARepeatedDayInsideOneBatchIsAppliedInOrder() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([baseDay(), partialDay(restingHr: 52)], deviceId: "A")
        let row = try await storedDay(store)
        XCTAssertEqual(row?.restingHr, 52)
        XCTAssertEqual(row?.totalSleepMin, 420, "lo que traía la primera aparición no se pierde")
        XCTAssertEqual(row?.strain, 5.0)
    }

    // MARK: - Lecturas y borrado

    func testWritingNewDaysCountsThem() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.upsertDailyMetrics([baseDay("2026-05-01"), baseDay("2026-05-02")],
                                                         deviceId: "A")
        XCTAssertEqual(written, 2)
    }

    func testTheRangeIsInclusiveAndAscending() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics(["2026-04-30", "2026-05-01", "2026-05-02", "2026-05-03"]
            .map { baseDay($0) }, deviceId: "A")
        let rows = try await store.dailyMetrics(deviceId: "A", from: "2026-05-01", to: "2026-05-02")
        XCTAssertEqual(rows.map(\.day), ["2026-05-01", "2026-05-02"])
    }

    func testTwoHundredDaysSurviveTheBatching() async throws {
        let store = try await CenitStore.inMemory()
        let days = (1...200).map { baseDay(String(format: "2026-05-%03d", $0)) }
        let written = try await store.upsertDailyMetrics(days, deviceId: "A")
        XCTAssertEqual(written, 200)
        let rows = try await store.dailyMetrics(deviceId: "A", from: "2026-05-000", to: "2026-05-999")
        XCTAssertEqual(rows.count, 200)
    }

    func testDeleteIsScopedToItsPartition() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertDailyMetrics([baseDay()], deviceId: "A")
        _ = try await store.upsertDailyMetrics([baseDay()], deviceId: "B")

        let deleted = try await store.deleteDailyMetrics(deviceId: "A", days: ["2026-05-01"])
        XCTAssertEqual(deleted, 1)
        let ownIsEmpty = try await store.dailyMetrics(deviceId: "A", from: "2026-05-01", to: "2026-05-01").isEmpty
        XCTAssertTrue(ownIsEmpty)
        let otherCount = try await store.dailyMetrics(deviceId: "B", from: "2026-05-01", to: "2026-05-01").count
        XCTAssertEqual(otherCount, 1)
    }

    func testDeletingNoDaysTouchesNothing() async throws {
        let store = try await seeded()
        let deleted = try await store.deleteDailyMetrics(deviceId: "A", days: [])
        XCTAssertEqual(deleted, 0)
        let stillThere = try await storedDay(store)
        XCTAssertNotNil(stillThere)
    }

    // MARK: - Noches

    private let night = CachedSleepSession(startTs: 1000, endTs: 2000, efficiency: 0.9,
                                           restingHr: 50, avgHrv: 44, stagesJSON: "[]")

    /// Filtrar por inicio dejaría fuera la noche de quien se durmió antes de la medianoche local. La
    /// ventana pregunta por traslape.
    func testANightThatStartedBeforeTheWindowStillShowsUp() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertSleepSessions([night], deviceId: "A")
        let rows = try await store.sleepSessions(deviceId: "A", from: 1500, to: 3000, limit: 10)
        XCTAssertEqual(rows, [night])
    }

    func testANightThatEndedBeforeTheWindowIsOut() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertSleepSessions([night], deviceId: "A")
        let rows = try await store.sleepSessions(deviceId: "A", from: 2500, to: 3000, limit: 10).isEmpty
        XCTAssertTrue(rows)
    }

    func testANightThatStartedAfterTheWindowIsOut() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertSleepSessions([night], deviceId: "A")
        let rows = try await store.sleepSessions(deviceId: "A", from: 0, to: 500, limit: 10).isEmpty
        XCTAssertTrue(rows)
    }

    func testRescoringANightReplacesItInPlace() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertSleepSessions([night], deviceId: "A")
        let rescored = CachedSleepSession(startTs: 1000, endTs: 2500, efficiency: 0.75,
                                          restingHr: 51, avgHrv: 41, stagesJSON: "[]")
        _ = try await store.upsertSleepSessions([rescored], deviceId: "A")

        let rows = try await store.sleepSessions(deviceId: "A", from: 0, to: 5000, limit: 10)
        XCTAssertEqual(rows, [rescored], "una fila, con los valores nuevos")
    }

    func testAnEmptyNightBatchTouchesNothing() async throws {
        let store = try await CenitStore.inMemory()
        let strain7 = try await store.upsertSleepSessions([], deviceId: "A")
        XCTAssertEqual(strain7, 0)
    }
}
