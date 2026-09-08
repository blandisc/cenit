import XCTest
import CenitModels
@testable import CenitStore

/// Diario, entrenamientos y totales diarios de Apple: clave natural por partición, alta idempotente y
/// lectura por rango.
final class LogStoreTests: XCTestCase {

    // MARK: - Diario

    func testJournalEntriesComeBackByDayThenQuestion() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.upsertJournal([
            JournalEntry(day: "2026-05-01", question: "A", answeredYes: true, notes: nil),
            JournalEntry(day: "2026-05-01", question: "B", answeredYes: false, notes: nil),
        ], deviceId: "src1")
        XCTAssertEqual(written, 2)

        let rows = try await store.journalEntries(deviceId: "src1", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows.map(\.question), ["A", "B"])
        XCTAssertEqual(rows.map(\.answeredYes), [true, false])
    }

    func testChangingAnAnswerReplacesItInPlace() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertJournal(
            [JournalEntry(day: "2026-05-01", question: "A", answeredYes: true, notes: nil)],
            deviceId: "src1")
        _ = try await store.upsertJournal(
            [JournalEntry(day: "2026-05-01", question: "A", answeredYes: false, notes: "nota")],
            deviceId: "src1")

        let rows = try await store.journalEntries(deviceId: "src1", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows, [JournalEntry(day: "2026-05-01", question: "A",
                                           answeredYes: false, notes: "nota")])
    }

    /// La misma clave dos veces en un lote no puede lanzar: se resuelve antes y gana la última.
    func testARepeatedAnswerInsideOneBatchKeepsTheLastOne() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertJournal([
            JournalEntry(day: "2026-05-01", question: "A", answeredYes: true, notes: nil),
            JournalEntry(day: "2026-05-01", question: "A", answeredYes: false, notes: nil),
        ], deviceId: "src1")
        let rows = try await store.journalEntries(deviceId: "src1", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows.map(\.answeredYes), [false])
    }

    /// Limpiar una respuesta nativa nunca puede llevarse la fila idéntica que vino importada.
    func testDeletingOneAnswerLeavesTheOtherPartitionAlone() async throws {
        let store = try await CenitStore.inMemory()
        let entry = JournalEntry(day: "2026-05-01", question: "A", answeredYes: true, notes: nil)
        _ = try await store.upsertJournal([entry], deviceId: "src1")
        _ = try await store.upsertJournal([entry], deviceId: "src2")

        let deleted = try await store.deleteJournal(deviceId: "src1", day: "2026-05-01", question: "A")
        XCTAssertEqual(deleted, 1)
        let ownIsEmpty = try await store.journalEntries(deviceId: "src1", from: "2026-05-01", to: "2026-05-01").isEmpty
        XCTAssertTrue(ownIsEmpty)
        let otherCount = try await store.journalEntries(deviceId: "src2", from: "2026-05-01", to: "2026-05-01").count
        XCTAssertEqual(otherCount, 1)
    }

    func testStartingOverClearsOnlyItsOwnPartition() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertJournal((1...3).map {
            JournalEntry(day: "2026-05-0\($0)", question: "A", answeredYes: true, notes: nil)
        }, deviceId: "src1")
        _ = try await store.upsertJournal((1...2).map {
            JournalEntry(day: "2026-05-0\($0)", question: "A", answeredYes: true, notes: nil)
        }, deviceId: "src2")

        let cleared = try await store.deleteAllJournal(deviceId: "src1")
        XCTAssertEqual(cleared, 3)
        let ownIsEmpty = try await store.journalEntries(deviceId: "src1", from: "2026-01-01", to: "2026-12-31").isEmpty
        XCTAssertTrue(ownIsEmpty)
        let otherCount = try await store.journalEntries(deviceId: "src2", from: "2026-01-01", to: "2026-12-31").count
        XCTAssertEqual(otherCount, 2)
    }

    func testTheJournalRangeIsInclusive() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertJournal(["2026-04-30", "2026-05-01", "2026-05-02", "2026-05-03"].map {
            JournalEntry(day: $0, question: "A", answeredYes: true, notes: nil)
        }, deviceId: "src1")
        let rows = try await store.journalEntries(deviceId: "src1", from: "2026-05-01", to: "2026-05-02")
        XCTAssertEqual(rows.map(\.day), ["2026-05-01", "2026-05-02"])
    }

    func testThreeHundredAnswersSurviveTheBatching() async throws {
        let store = try await CenitStore.inMemory()
        let rows = (1...300).map {
            JournalEntry(day: String(format: "2026-05-%03d", $0), question: "A",
                         answeredYes: true, notes: nil)
        }
        let written = try await store.upsertJournal(rows, deviceId: "src1")
        XCTAssertEqual(written, 300)
        let readBack = try await store.journalEntries(deviceId: "src1",
                                                      from: "2026-05-000", to: "2026-05-999")
        XCTAssertEqual(readBack.count, 300)
    }

    // MARK: - Entrenamientos

    private func workout(_ startTs: Int, _ sport: String, avgHr: Int? = nil,
                         source: String = "apple") -> WorkoutRow {
        WorkoutRow(startTs: startTs, endTs: startTs + 100, sport: sport, source: source,
                   durationS: nil, energyKcal: nil, avgHr: avgHr, maxHr: nil, strain: nil,
                   distanceM: nil, zonesJSON: nil, notes: nil)
    }

    func testTwoSportsAtTheSameInstantAreTwoRows() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.upsertWorkouts([workout(1000, "Run"), workout(1000, "Bike")],
                                                     deviceId: "A")
        XCTAssertEqual(written, 2)
        let rows = try await store.workouts(deviceId: "A", from: 0, to: 2000, limit: 10)
        XCTAssertEqual(rows.count, 2)
    }

    func testRewritingAWorkoutReplacesItInPlace() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertWorkouts([workout(1000, "Run")], deviceId: "A")
        _ = try await store.upsertWorkouts([workout(1000, "Run", avgHr: 150)], deviceId: "A")

        let rows = try await store.workouts(deviceId: "A", from: 0, to: 2000, limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.avgHr, 150)
    }

    func testTheSameWorkoutInThreePartitionsIsThreeRows() async throws {
        let store = try await CenitStore.inMemory()
        for partition in ["A", "B", "C"] {
            _ = try await store.upsertWorkouts([workout(1000, "Run")], deviceId: partition)
        }
        for partition in ["A", "B", "C"] {
            let count = try await store.workouts(deviceId: partition, from: 0, to: 2000, limit: 10).count
            XCTAssertEqual(count, 1)
        }
    }

    /// El filtro es por INICIO, no por traslape: un entrenamiento que empezó fuera no entra aunque
    /// termine dentro.
    func testWorkoutsAreFilteredByTheirStart() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertWorkouts([workout(500, "Run"), workout(1000, "Run"),
                                            workout(5000, "Run")], deviceId: "A")
        let rows = try await store.workouts(deviceId: "A", from: 900, to: 1100, limit: 10)
        XCTAssertEqual(rows.map(\.startTs), [1000])
    }

    func testDeletingBySportSweepsOnlyThatSportInThatRange() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertWorkouts([workout(1000, "detected"), workout(9000, "detected"),
                                            workout(1000, "Run")], deviceId: "A")

        let swept = try await store.deleteWorkouts(deviceId: "A", sport: "detected", from: 0, to: 2000)
        XCTAssertEqual(swept, 1)
        let rows = try await store.workouts(deviceId: "A", from: 0, to: 10000, limit: 10)
        XCTAssertEqual(Set(rows.map { "\($0.sport)@\($0.startTs)" }), ["detected@9000", "Run@1000"])
    }

    /// Una métrica ausente se lee como ausente, nunca como un 0 que la interfaz mostraría como dato.
    func testMissingWorkoutMetricsReadBackAsMissing() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertWorkouts([workout(1000, "Run")], deviceId: "A")
        let row = try await store.workouts(deviceId: "A", from: 0, to: 2000, limit: 10).first
        XCTAssertNil(row?.durationS)
        XCTAssertNil(row?.energyKcal)
        XCTAssertNil(row?.avgHr)
        XCTAssertNil(row?.strain)
        XCTAssertNil(row?.distanceM)
        XCTAssertNil(row?.notes)
    }

    // MARK: - Totales diarios de Apple

    private func appleDay(_ day: String, steps: Int?) -> AppleDaily {
        AppleDaily(day: day, steps: steps, activeKcal: nil, basalKcal: nil, vo2max: nil,
                   avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
    }

    func testRewritingOneAppleDayLeavesTheOther() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertAppleDaily([appleDay("2026-05-01", steps: 1000),
                                              appleDay("2026-05-02", steps: 2000)], deviceId: "A")
        _ = try await store.upsertAppleDaily([appleDay("2026-05-01", steps: 1500)], deviceId: "A")

        let rows = try await store.appleDaily(deviceId: "A", from: "2026-05-01", to: "2026-05-02")
        XCTAssertEqual(rows.map(\.day), ["2026-05-01", "2026-05-02"])
        XCTAssertEqual(rows.map(\.steps), [1500, 2000])
    }

    func testOneHundredFiftyAppleDaysSurviveTheBatching() async throws {
        let store = try await CenitStore.inMemory()
        let rows = (1...150).map { appleDay(String(format: "2026-05-%03d", $0), steps: $0) }
        let written = try await store.upsertAppleDaily(rows, deviceId: "A")
        XCTAssertEqual(written, 150)
        let readBack = try await store.appleDaily(deviceId: "A",
                                                  from: "2026-05-000", to: "2026-05-999")
        XCTAssertEqual(readBack.count, 150)
    }

    func testARepeatedAppleDayInsideOneBatchKeepsTheLastOne() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertAppleDaily([appleDay("2026-05-01", steps: 1000),
                                              appleDay("2026-05-01", steps: 9000)], deviceId: "A")
        let rows = try await store.appleDaily(deviceId: "A", from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows.map(\.steps), [9000])
    }

    func testEmptyBatchesTouchNothing() async throws {
        let store = try await CenitStore.inMemory()
        let journalWritten = try await store.upsertJournal([], deviceId: "A")
        XCTAssertEqual(journalWritten, 0)
        let workoutsWritten = try await store.upsertWorkouts([], deviceId: "A")
        XCTAssertEqual(workoutsWritten, 0)
        let appleWritten = try await store.upsertAppleDaily([], deviceId: "A")
        XCTAssertEqual(appleWritten, 0)
    }
}
