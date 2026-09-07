import XCTest
@testable import CenitStore

/// La serie métrica larga: escritura reemplazante, lectura por rango de día lexicográfico y el orden
/// público «día y luego clave», que no es el del índice.
final class SeriesStoreTests: XCTestCase {

    private let twoDays = [MetricPoint(day: "2026-05-01", key: "steps", value: 9000),
                           MetricPoint(day: "2026-05-02", key: "steps", value: 11000)]

    func testWritingNewPointsCountsThem() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        XCTAssertEqual(written, 2)
    }

    /// El conteo es «filas cambiadas», insertadas MÁS actualizadas: reescribir N puntos idénticos
    /// devuelve N, no 0.
    func testRewritingTheSamePointsStillCountsThem() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        let rewritten = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        XCTAssertEqual(rewritten, 2)
    }

    func testTheIncomingValueWins() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        _ = try await store.upsertMetricSeries(
            [MetricPoint(day: "2026-05-01", key: "steps", value: 9500)], deviceId: "A")
        let rows = try await store.metricSeries(deviceId: "A", key: "steps",
                                                from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows.map(\.value), [9500])
    }

    func testTheRangeIsLexicographicAndOldestFirst() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        let rows = try await store.metricSeries(deviceId: "A", key: "steps",
                                                from: "2026-04-01", to: "2026-12-31")
        XCTAssertEqual(rows.map { ($0.day, $0.value) }.map { "\($0.0)=\($0.1)" },
                       ["2026-05-01=9000.0", "2026-05-02=11000.0"])
    }

    /// Quien arma 24 claves horarias no debe hacer 24 viajes, y el orden que recibe es día y luego
    /// clave — no el del índice, que va por clave primero.
    func testTheMultiKeyReadIsOrderedByDayThenKey() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries([
            MetricPoint(day: "2026-05-01", key: "b", value: 2),
            MetricPoint(day: "2026-05-01", key: "a", value: 1),
            MetricPoint(day: "2026-05-02", key: "a", value: 3),
        ], deviceId: "A")
        let rows = try await store.metricSeries(deviceId: "A", keys: ["a", "b"],
                                                from: "2026-05-01", to: "2026-05-02")
        XCTAssertEqual(rows, [MetricPoint(day: "2026-05-01", key: "a", value: 1),
                              MetricPoint(day: "2026-05-01", key: "b", value: 2),
                              MetricPoint(day: "2026-05-02", key: "a", value: 3)])
    }

    func testAskingForNoKeysReadsEmpty() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        let rows = try await store.metricSeries(deviceId: "A", keys: [],
                                                from: "2026-05-01", to: "2026-05-02")
        XCTAssertTrue(rows.isEmpty)
    }

    func testKeysComeBackDistinctAndSorted() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries([
            MetricPoint(day: "2026-05-01", key: "zeta", value: 1),
            MetricPoint(day: "2026-05-02", key: "alfa", value: 2),
            MetricPoint(day: "2026-05-03", key: "alfa", value: 3),
        ], deviceId: "A")
        let keys = try await store.metricKeys(deviceId: "A")
        XCTAssertEqual(keys, ["alfa", "zeta"])
        let noKeys = try await store.metricKeys(deviceId: "ZZZ")
        XCTAssertEqual(noKeys, [])
    }

    func testTheSpanOfAKeyIsItsFirstAndLastDay() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries([
            MetricPoint(day: "2026-03-09", key: "k", value: 1),
            MetricPoint(day: "2026-01-02", key: "k", value: 2),
            MetricPoint(day: "2026-02-14", key: "k", value: 3),
        ], deviceId: "A")
        let span = try await store.metricDays(deviceId: "A", key: "k")
        XCTAssertEqual(span?.earliest, "2026-01-02")
        XCTAssertEqual(span?.latest, "2026-03-09")
    }

    /// La agregación siempre devuelve una fila: sin puntos, el mínimo es nulo y la respuesta honesta
    /// es `nil`, no un rango inventado.
    func testTheSpanOfAKeyWithoutPointsIsNil() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries(twoDays, deviceId: "A")
        let span = try await store.metricDays(deviceId: "A", key: "no-existe")
        XCTAssertNil(span)
    }

    func testDeletingAKeyLeavesTheOthersAndTheOtherPartitions() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries([
            MetricPoint(day: "2026-05-01", key: "x", value: 1),
            MetricPoint(day: "2026-05-01", key: "y", value: 2),
        ], deviceId: "A")
        _ = try await store.upsertMetricSeries(
            [MetricPoint(day: "2026-05-01", key: "x", value: 9)], deviceId: "B")

        try await store.deleteMetricSeries(deviceId: "A", key: "x")

        let remaining = try await store.metricKeys(deviceId: "A")
        XCTAssertEqual(remaining, ["y"])
        let kept = try await store.metricSeries(deviceId: "B", key: "x",
                                                from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(kept.map(\.value), [9])
    }

    /// Mil puntos cruzan cualquier frontera de lote razonable: el comportamiento tiene que ser el
    /// mismo con uno o con miles.
    func testAThousandPointsSurviveTheBatching() async throws {
        let store = try await CenitStore.inMemory()
        var start = DateComponents(calendar: Calendar(identifier: .gregorian),
                                   timeZone: TimeZone(identifier: "UTC"),
                                   year: 2024, month: 1, day: 1).date!
        var points: [MetricPoint] = []
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        for i in 0..<1000 {
            points.append(MetricPoint(day: format.string(from: start), key: "k", value: Double(i)))
            start = start.addingTimeInterval(86_400)
        }
        let total = try await store.upsertMetricSeries(points, deviceId: "A")
        XCTAssertEqual(total, 1000)

        let read = try await store.metricSeries(deviceId: "A", key: "k",
                                                from: "2000-01-01", to: "2099-12-31")
        XCTAssertEqual(read.count, 1000)
        XCTAssertEqual(read.map(\.day), read.map(\.day).sorted())
        XCTAssertEqual(read.map(\.value), points.map(\.value))
    }

    /// SQLite se niega a resolver dos veces la misma clave de conflicto dentro de una sentencia. Un
    /// lote con el mismo día repetido no puede lanzar: se resuelve antes, y gana el último.
    func testARepeatedKeyInsideOneBatchKeepsTheLastValue() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertMetricSeries([
            MetricPoint(day: "2026-05-01", key: "k", value: 1),
            MetricPoint(day: "2026-05-01", key: "k", value: 7),
        ], deviceId: "A")
        let rows = try await store.metricSeries(deviceId: "A", key: "k",
                                                from: "2026-05-01", to: "2026-05-01")
        XCTAssertEqual(rows.map(\.value), [7])
    }

    func testAnEmptyBatchTouchesNothing() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.upsertMetricSeries([], deviceId: "A")
        XCTAssertEqual(written, 0)
    }
}
