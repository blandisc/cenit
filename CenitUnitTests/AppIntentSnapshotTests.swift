import XCTest
@testable import Cenit

/// FER-522 — round-trip of the two App-Group snapshots that back Siri entity queries.
/// Same wire discipline as `TrainWidgetPublisherTests` / `RestActivityFER806Tests`.
final class AppIntentSnapshotTests: XCTestCase {

    func testRoutineCatalogRoundTripsThroughJSON() throws {
        let original = RoutineCatalogSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            routines: [
                .init(id: "push", name: "Empuje"),
                .init(id: "pull", name: "Tirón"),
            ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutineCatalogSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.routines.map(\.id), ["push", "pull"])
        XCTAssertEqual(decoded.routines.map(\.name), ["Empuje", "Tirón"])
    }

    func testRoutineCatalogEmptyRoundTrips() throws {
        let original = RoutineCatalogSnapshot(writtenAt: Date(timeIntervalSince1970: 0), routines: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutineCatalogSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.routines.isEmpty)
    }

    func testRoutineCatalogIsStaleTrasElHorizonte() {
        let ahora = Date(timeIntervalSince1970: 1_700_000_000)
        let fresco = RoutineCatalogSnapshot(writtenAt: ahora, routines: [])
        XCTAssertFalse(fresco.isStale(asOf: ahora.addingTimeInterval(60)))
        let rancio = RoutineCatalogSnapshot(
            writtenAt: ahora.addingTimeInterval(-RoutineCatalogSnapshot.staleAfter - 1),
            routines: [])
        XCTAssertTrue(rancio.isStale(asOf: ahora))
    }

    func testActiveSessionRoundTripsThroughJSON() throws {
        let original = ActiveSessionSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionId: "s1",
            exercises: [
                .init(id: "bench", name: "Press banca"),
                .init(id: "row", name: "Remo"),
            ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        // Language only — no weight/reps fields on the type (structural: Codable keys).
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(keys["weightKg"])
        XCTAssertNil(keys["reps"])
        XCTAssertEqual((keys["exercises"] as? [[String: Any]])?.first?.keys.sorted(), ["id", "name"])
    }

    func testActiveSessionEmptyExercisesRoundTrips() throws {
        let original = ActiveSessionSnapshot(
            writtenAt: Date(timeIntervalSince1970: 0), sessionId: "s0", exercises: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
