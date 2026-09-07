import XCTest
import StrandModels
@testable import CenitStore

/// El panel de «qué alcanzó a traer la importación».
///
/// El contrato que más importa aquí no es un número sino una ausencia: una métrica sin un solo día NO
/// aparece en el diccionario. La interfaz dibuja «falta» por la clave ausente, y un `0` explícito
/// diría algo distinto —que se buscó y de verdad hubo cero— que no es lo mismo.
final class AppleCoverageTests: XCTestCase {

    private let partition = "apple-health"

    private func seededStore() async throws -> CenitStore {
        let store = try await CenitStore.inMemory()
        _ = try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-01", steps: 1000, activeKcal: 200, basalKcal: nil,
                       vo2max: nil, avgHr: 60, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-05-02", steps: 2000, activeKcal: nil, basalKcal: nil,
                       vo2max: nil, avgHr: 61, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: partition)
        _ = try await store.upsertDailyMetrics([
            DailyMetric(day: "2026-05-02", totalSleepMin: 420, efficiency: nil, deepMin: nil,
                        remMin: nil, lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 40,
                        recovery: nil, strain: nil, exerciseCount: nil, spo2Pct: 96),
            DailyMetric(day: "2026-05-03", totalSleepMin: 400, efficiency: nil, deepMin: nil,
                        remMin: nil, lightMin: nil, disturbances: nil, restingHr: 54, avgHrv: 42,
                        recovery: nil, strain: nil, exerciseCount: nil),
        ], deviceId: partition)
        return store
    }

    /// El tramo se mide sobre la UNIÓN de los días de las dos tablas, y un día presente en ambas
    /// cuenta una sola vez.
    func testTheSpanCoversBothTablesAndCountsEachDayOnce() async throws {
        let coverage = try await seededStore().appleHealthCoverage(deviceId: partition)
        XCTAssertEqual(coverage.firstDay, "2026-05-01")
        XCTAssertEqual(coverage.lastDay, "2026-05-03")
        XCTAssertEqual(coverage.totalDays, 3)
    }

    func testEachMetricCountsItsDaysWithARealValue() async throws {
        let coverage = try await seededStore().appleHealthCoverage(deviceId: partition)
        XCTAssertEqual(coverage.daysByMetric["steps"], 2)
        XCTAssertEqual(coverage.daysByMetric["avg_hr"], 2)
        XCTAssertEqual(coverage.daysByMetric["active_kcal"], 1)
        XCTAssertEqual(coverage.daysByMetric["hrv"], 2)
        XCTAssertEqual(coverage.daysByMetric["asleep_min"], 2)
        XCTAssertEqual(coverage.daysByMetric["resting_hr"], 2)
        XCTAssertEqual(coverage.daysByMetric["spo2"], 1)
    }

    func testAMetricWithoutDaysIsAbsentNotZero() async throws {
        let coverage = try await seededStore().appleHealthCoverage(deviceId: partition)
        XCTAssertNil(coverage.daysByMetric["resp_rate"])
        XCTAssertNil(coverage.daysByMetric["vo2max"])
        XCTAssertNil(coverage.daysByMetric["skin_temp"])
    }

    func testAnotherPartitionSeesNothing() async throws {
        let coverage = try await seededStore().appleHealthCoverage(deviceId: "otra-fuente")
        XCTAssertNil(coverage.firstDay)
        XCTAssertNil(coverage.lastDay)
        XCTAssertEqual(coverage.totalDays, 0)
        XCTAssertTrue(coverage.daysByMetric.isEmpty)
    }

    func testAnEmptyStoreReportsNothingImported() async throws {
        let store = try await CenitStore.inMemory()
        let coverage = try await store.appleHealthCoverage(deviceId: partition)
        XCTAssertNil(coverage.firstDay)
        XCTAssertNil(coverage.lastDay)
        XCTAssertEqual(coverage.totalDays, 0)
        XCTAssertTrue(coverage.daysByMetric.isEmpty)
    }
}
