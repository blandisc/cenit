import XCTest
@testable import Cenit

/// FER-398 — the `HKMetadataKeyExternalUUID` that keeps one strength session from becoming two
/// workouts in Apple Health.
///
/// The key moved off its legacy prefix (`legacyKeyPrefix`) onto `cenit:strength:<id>`. That rename is only safe
/// because the delete-by-key that precedes every save accepts BOTH spellings: the workouts Cénit
/// already wrote carry the old prefix and live in the user's Health vault for good. If the dedupe
/// only knew the new prefix, re-saving one of those sessions — editing it, or the watch acking late —
/// would leave the old workout in place and add a second one beside it.
final class WorkoutExternalUUIDDedupeTests: XCTestCase {

    /// Dato en disco: el prefijo de la llave con la que quedaron escritos los `HKWorkout` viejos.
    private static let legacyKeyPrefix = "noop:strength:"

    private let sessionId = "5C1D5B0E-0000-4000-8000-000000000001"

    /// New writes carry the Cénit prefix.
    func testWritesUnderTheCenitPrefix() {
        XCTAssertEqual(WorkoutMirrorKey.externalUUID(for: sessionId), "cenit:strength:\(sessionId)")
    }

    /// The old spelling is still constructible — it is what the existing samples carry.
    func testLegacyKeyKeepsTheNoopPrefix() {
        XCTAssertEqual(WorkoutMirrorKey.legacyExternalUUID(for: sessionId), Self.legacyKeyPrefix + sessionId)
    }

    /// The dedupe set is both, new first, with no duplicates and nothing else.
    func testDedupeAcceptsBothPrefixes() {
        let keys = WorkoutMirrorKey.dedupeUUIDs(for: sessionId)

        XCTAssertEqual(keys, ["cenit:strength:\(sessionId)", Self.legacyKeyPrefix + sessionId])
        XCTAssertTrue(keys.contains(WorkoutMirrorKey.externalUUID(for: sessionId)))
        XCTAssertTrue(keys.contains(WorkoutMirrorKey.legacyExternalUUID(for: sessionId)),
                      "dropping the legacy prefix would duplicate every workout saved before FER-398")
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// The key is derived from the session id alone, so the iPhone and the watch always agree — that
    /// is the whole one-HKWorkout invariant of FER-740.
    func testKeysAreDeterministicPerSession() {
        XCTAssertEqual(WorkoutMirrorKey.externalUUID(for: sessionId),
                       WorkoutMirrorKey.externalUUID(for: sessionId))
        XCTAssertNotEqual(WorkoutMirrorKey.externalUUID(for: sessionId),
                          WorkoutMirrorKey.externalUUID(for: "another-session"))
    }
}
