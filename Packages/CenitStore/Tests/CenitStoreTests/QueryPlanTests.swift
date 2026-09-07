import XCTest
import GRDB
@testable import CenitStore

/// FER-29 — cada lectura caliente tiene que llegar a su tabla por índice, nunca barriéndola entera.
///
/// El diagnóstico original era que las claves primarias compuestas «probablemente ya» cubrían estas
/// consultas. Estas pruebas lo confirman con `EXPLAIN QUERY PLAN` y lo fijan: un cambio futuro a un
/// `WHERE` o a un `ORDER BY` que dejara caer el índice —y con él pusiera a barrer años de historia—
/// falla aquí.
///
/// El SQL de abajo espeja el de los métodos de lectura del paquete. El planificador elige el mismo
/// plan sin importar cuántas filas haya, así que una base vacía en memoria basta; los valores ligados
/// son de relleno, pero el NÚMERO de marcadores tiene que ser el de la consulta real.
final class QueryPlanTests: XCTestCase {

    /// Afirma que el plan llega a `table` por un paso con índice (`… USING …`) y nunca por un `SCAN
    /// <table>` pelado. Un `SCAN … USING COVERING INDEX` es un recorrido de índice y está bien.
    private func assertIndexed(_ plan: [String], table: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let joined = plan.joined(separator: " | ")
        let fullScan = plan.contains {
            $0.hasPrefix("SCAN") && $0.contains(table) && !$0.contains("USING")
        }
        XCTAssertFalse(fullScan, "\(table): barrido completo inesperado — plan: [\(joined)]",
                       file: file, line: line)
        let indexed = plan.contains {
            ($0.contains("SEARCH") || $0.contains("SCAN")) && $0.contains(table) && $0.contains("USING")
        }
        XCTAssertTrue(indexed, "\(table): se esperaba un acceso por índice — plan: [\(joined)]",
                      file: file, line: line)
    }

    // MARK: - metricSeries (idx_metricSeries_device_key_day)

    func testMetricSeriesRangeReadUsesIndex() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, key, value
            FROM metricSeries WHERE deviceId = ? AND key = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: ["d", "recovery", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "metricSeries")
    }

    func testMetricKeysDistinctUsesIndex() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT DISTINCT key FROM metricSeries WHERE deviceId = ? ORDER BY key ASC
            """, arguments: ["d"])
        assertIndexed(plan, table: "metricSeries")
    }

    func testMetricDaysMinMaxUsesIndex() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT MIN(day) AS earliest, MAX(day) AS latest
            FROM metricSeries WHERE deviceId = ? AND key = ?
            """, arguments: ["d", "recovery"])
        assertIndexed(plan, table: "metricSeries")
    }

    /// La lectura multi-clave (las 24 claves horarias `act_hNN`). El `ORDER BY` sigue al índice
    /// `(deviceId, key, day)` para que SQLite no construya un B-TREE temporal; el orden público —día y
    /// luego clave— se restablece en memoria.
    func testMetricSeriesMultiKeyRangeReadUsesIndexWithoutTempBTree() async throws {
        let store = try await CenitStore.inMemory()
        let keys = (0..<24).map { String(format: "act_h%02d", $0) }
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        var args: [DatabaseValueConvertible?] = ["d"]
        args.append(contentsOf: keys)
        args.append(contentsOf: ["2020-01-01", "2030-01-01"])
        let plan = try await store.queryPlanForTest("""
            SELECT day, key, value FROM metricSeries
            WHERE deviceId = ? AND key IN (\(placeholders)) AND day >= ? AND day <= ?
            ORDER BY key ASC, day ASC
            """, arguments: StatementArguments(args))
        assertIndexed(plan, table: "metricSeries")
        let joined = plan.joined(separator: " | ")
        let usesTempBTree = plan.contains {
            $0.localizedCaseInsensitiveContains("TEMP B-TREE")
                || $0.localizedCaseInsensitiveContains("USE TEMP B-TREE")
        }
        XCTAssertFalse(usesTempBTree,
                       "la lectura multi-clave no debe ordenar por B-TREE temporal — plan: [\(joined)]")
    }

    // MARK: - Las cachés por día (clave primaria compuesta)

    func testJournalRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, question, answeredYes, notes
            FROM journal WHERE deviceId = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC, question ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "journal")
    }

    func testWorkoutsRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT startTs, endTs, sport, source, durationS, energyKcal,
                   avgHr, maxHr, strain, distanceM, zonesJSON, notes
            FROM workout WHERE deviceId = ? AND startTs BETWEEN ? AND ?
            ORDER BY startTs ASC
            LIMIT ?
            """, arguments: ["d", 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "workout")
    }

    /// La clave primaria es `(deviceId, startTs, sport)`: se busca por fuente y rango de inicio, y el
    /// deporte se filtra después. Sigue siendo una búsqueda por índice, no un barrido.
    func testDeleteWorkoutsBySportUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            DELETE FROM workout WHERE deviceId = ? AND sport = ? AND startTs >= ? AND startTs <= ?
            """, arguments: ["d", "detected", 0, 9_999_999_999])
        assertIndexed(plan, table: "workout")
    }

    func testAppleDailyRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, steps, activeKcal, basalKcal, vo2max,
                   avgHr, maxHr, walkingHr, weightKg
            FROM appleDaily WHERE deviceId = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "appleDaily")
    }

    func testDailyMetricsRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin,
                   disturbances, restingHr, avgHrv, recovery, strain, exerciseCount,
                   spo2Pct, skinTempDevC, respRateBpm, steps, activeKcalEst,
                   effortConfidence, restConfidence
            FROM dailyMetric WHERE deviceId = ? AND day BETWEEN ? AND ?
            ORDER BY day ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "dailyMetric")
    }

    func testSleepSessionsRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON
            FROM sleepSession WHERE deviceId = ? AND startTs <= ? AND endTs >= ?
            ORDER BY startTs ASC
            LIMIT ?
            """, arguments: ["d", 9_999_999_999, 0, 100])
        assertIndexed(plan, table: "sleepSession")
    }

    // MARK: - Los latidos (WITHOUT ROWID: la clave primaria ES la tabla)

    func testHRSamplesRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT ts, bpm FROM hrSample WHERE deviceId = ? AND ts BETWEEN ? AND ?
            ORDER BY ts ASC
            LIMIT ?
            """, arguments: [1, 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "hrSample")
    }

    /// El `GROUP BY` puede agregar un b-tree temporal, pero el acceso a la tabla tiene que seguir
    /// siendo por índice.
    func testHRBucketsAggregateUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT (ts / ?) * ? AS bucket, AVG(bpm) AS mean
            FROM hrSample WHERE deviceId = ? AND ts BETWEEN ? AND ?
            GROUP BY ts / ?
            ORDER BY bucket
            """, arguments: [300, 300, 1, 0, 9_999_999_999, 300])
        assertIndexed(plan, table: "hrSample")
    }

    func testLatestHRSampleTsUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest(
            "SELECT MAX(ts) FROM hrSample WHERE deviceId = ?", arguments: [1])
        assertIndexed(plan, table: "hrSample")
    }

    /// La arriesgada: `rrInterval` tiene una clave de tres columnas `(deviceId, ts, rrMs)` y el rango
    /// tiene que seguir buscándola, no barrerla.
    func testRRIntervalsRangeReadUsesPrimaryKey() async throws {
        let store = try await CenitStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT ts, rrMs FROM rrInterval WHERE deviceId = ? AND ts BETWEEN ? AND ?
            ORDER BY ts ASC, rrMs ASC
            LIMIT ?
            """, arguments: [1, 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "rrInterval")
    }
}
