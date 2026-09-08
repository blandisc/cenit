import XCTest
import CenitStore
@testable import Cenit

/// Fija la lectura de las zonas de FC guardadas por entrenamiento contra las formas que de verdad
/// están en disco: hay filas escritas con llaves «z1»…«z5» y filas escritas con «zone1»…«zone5» para
/// el mismo dato, y las dos tienen que pintar. Fija además la regla honesta: un dato inservible se
/// declara ausente en vez de dibujarse como cinco ceros.
final class WorkoutZonesTests: XCTestCase {

    // MARK: - Lectura de porcentajes

    func testReadsShortKeyShape() {
        XCTAssertEqual(WorkoutZones.percents(#"{"z1":12.5,"z5":4.5}"#), [12.5, 0, 0, 0, 4.5])
    }

    func testReadsLongKeyShape() {
        XCTAssertEqual(WorkoutZones.percents(#"{"zone1":10,"zone2":20,"zone3":30,"zone4":25,"zone5":15}"#),
                       [10, 20, 30, 25, 15])
    }

    func testShortKeyWinsWhenBothShapesArePresent() {
        XCTAssertEqual(WorkoutZones.percents(#"{"z1":40,"zone1":10}"#), [40, 0, 0, 0, 0])
    }

    func testPercentsAreClampedToTheirRange() {
        XCTAssertEqual(WorkoutZones.percents(#"{"z1":150,"z2":-20}"#), [100, 0, 0, 0, 0])
    }

    func testNonNumericValueCountsAsZero() {
        XCTAssertEqual(WorkoutZones.percents(#"{"z1":"mucho","z2":30}"#), [0, 30, 0, 0, 0])
    }

    func testUnusableInputReadsAsAbsent() {
        XCTAssertNil(WorkoutZones.percents(nil))
        XCTAssertNil(WorkoutZones.percents("{}"))
        XCTAssertNil(WorkoutZones.percents("no es json"))
        XCTAssertNil(WorkoutZones.percents("[1,2,3]"))          // JSON válido, pero no un objeto
        XCTAssertNil(WorkoutZones.percents(#"{"z1":0}"#))       // todo cero = sin dato, no cinco ceros
        XCTAssertNil(WorkoutZones.percents(#"{"z9":80}"#))      // sólo llaves que no conocemos
    }

    // MARK: - Agregado pesado por duración

    func testSummaryWeighsEachRowByItsDuration() {
        let summary = WorkoutZones.summary(from: [
            row(startTs: 0, durationS: 3600, zones: #"{"z1":100}"#),          // 60 min, todo Z1
            row(startTs: 10_000, durationS: 1800, zones: #"{"zone5":100}"#),  // 30 min, todo Z5
            row(startTs: 20_000, durationS: 1800, zones: nil),                // sin zonas: no cuenta
        ])
        XCTAssertEqual(summary?.sessionsWithZones, 2)
        XCTAssertEqual(summary?.minutes[0] ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(summary?.minutes[4] ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(summary?.totalMinutes ?? 0, 90, accuracy: 1e-9)
    }

    func testSummaryFallsBackToTheClockSpanWhenDurationIsMissing() {
        // 1200 s de lapso = 20 min; la mitad en Z3 son 10 min.
        let summary = WorkoutZones.summary(from: [
            row(startTs: 0, endTs: 1200, durationS: nil, zones: #"{"z3":50}"#)
        ])
        XCTAssertEqual(summary?.sessionsWithZones, 1)
        XCTAssertEqual(summary?.minutes[2] ?? 0, 10, accuracy: 1e-9)
    }

    func testSummaryIsAbsentWithoutUsableRows() {
        XCTAssertNil(WorkoutZones.summary(from: []))
        XCTAssertNil(WorkoutZones.summary(from: [row(startTs: 0, durationS: 1800, zones: nil)]))
        // Zonas sí, duración cero: no hay minutos que repartir.
        XCTAssertNil(WorkoutZones.summary(from: [
            row(startTs: 500, endTs: 500, durationS: nil, zones: #"{"z1":100}"#)
        ]))
    }

    // MARK: - Fixture

    private func row(startTs: Int, endTs: Int? = nil, durationS: Double?, zones: String?) -> WorkoutRow {
        WorkoutRow(startTs: startTs,
                   endTs: endTs ?? startTs + Int(durationS ?? 0),
                   sport: "Running", source: "apple-health",
                   durationS: durationS, energyKcal: nil, avgHr: nil, maxHr: nil,
                   strain: nil, distanceM: nil, zonesJSON: zones, notes: nil)
    }
}
