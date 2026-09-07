import XCTest
import BiometricStreams
@testable import CenitStore

/// Los latidos crudos: alta idempotente por clave natural, aislamiento entre fuentes y lecturas por
/// ventana con ambos extremos incluidos.
final class BeatStoreTests: XCTestCase {

    private let beats = Streams(hr: [HRSample(ts: 100, bpm: 60),
                                     HRSample(ts: 200, bpm: 61),
                                     HRSample(ts: 300, bpm: 62)],
                                rr: [RRInterval(ts: 100, rrMs: 800),
                                     RRInterval(ts: 100, rrMs: 820)])

    // MARK: - Alta

    func testInsertCountsTheRowsItActuallyWrote() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.insert(beats, deviceId: "A")
        XCTAssertEqual(written.hr, 3)
        XCTAssertEqual(written.rr, 2)
    }

    func testReinsertingTheSameBeatsWritesNothing() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let again = try await store.insert(beats, deviceId: "A")
        XCTAssertEqual(again.hr, 0)
        XCTAssertEqual(again.rr, 0)
    }

    func testSampleCountsAddUpAcrossThePartitions() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        _ = try await store.insert(beats, deviceId: "A")
        let counts = try await store.sampleCounts()
        XCTAssertEqual(counts.hr, 3)
        XCTAssertEqual(counts.rr, 2)
    }

    func testTheSameBeatsInAnotherPartitionAreNewRows() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let other = try await store.insert(beats, deviceId: "B")
        XCTAssertEqual(other.hr, 3, "otra fuente, sin conflicto")
        XCTAssertEqual(other.rr, 2)

        let counts = try await store.sampleCounts()
        XCTAssertEqual(counts.hr, 6)
    }

    func testEmptyStreamsTouchNothing() async throws {
        let store = try await CenitStore.inMemory()
        let written = try await store.insert(Streams(), deviceId: "A")
        XCTAssertEqual(written.hr, 0)
        XCTAssertEqual(written.rr, 0)

        let counts = try await store.sampleCounts()
        XCTAssertEqual(counts.hr, 0)
    }

    /// Los flujos que `Streams` sigue cargando para motores dormidos no tienen tabla. Escribirlos
    /// lanzaría «no such table» y tumbaría la transacción entera, incluidos los latidos que sí viven:
    /// por eso se ignoran en silencio en vez de intentarse.
    func testDormantStreamsAreIgnoredInsteadOfThrowing() async throws {
        let store = try await CenitStore.inMemory()
        let mixed = Streams(hr: [HRSample(ts: 10, bpm: 55)],
                            rr: [],
                            skinTemp: [SkinTempSample(ts: 10, raw: 3000)],
                            resp: [RespSample(ts: 10, raw: 14)],
                            gravity: [GravitySample(ts: 10, x: 0, y: 0, z: 1)])
        let written = try await store.insert(mixed, deviceId: "A")
        XCTAssertEqual(written.hr, 1)
        XCTAssertEqual(written.rr, 0)
    }

    func testAnEmptyStoreCountsZero() async throws {
        let store = try await CenitStore.inMemory()
        let counts = try await store.sampleCounts()
        XCTAssertEqual(counts.hr, 0)
        XCTAssertEqual(counts.rr, 0)
    }

    // MARK: - Lecturas

    func testHRSamplesComeBackAscendingByTime() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let rows = try await store.hrSamples(deviceId: "A", from: 0, to: 1000, limit: 100)
        XCTAssertEqual(rows, [HRSample(ts: 100, bpm: 60), HRSample(ts: 200, bpm: 61),
                              HRSample(ts: 300, bpm: 62)])
    }

    func testTheWindowIncludesBothEnds() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let rows = try await store.hrSamples(deviceId: "A", from: 200, to: 300, limit: 100)
        XCTAssertEqual(rows, [HRSample(ts: 200, bpm: 61), HRSample(ts: 300, bpm: 62)])
    }

    func testTheLimitKeepsTheEarliestRows() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let rows = try await store.hrSamples(deviceId: "A", from: 0, to: 1000, limit: 2)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.ts, 100)
    }

    /// Preguntar por una fuente que nunca se escribió no es un error: responde vacío.
    func testAnUnknownPartitionReadsEmpty() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let rows = try await store.hrSamples(deviceId: "ZZZ", from: 0, to: 1000, limit: 100)
        XCTAssertTrue(rows.isEmpty)
    }

    func testBucketsAverageByTheBucketStart() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let buckets = try await store.hrBuckets(deviceId: "A", from: 0, to: 1000, bucketSeconds: 200)
        XCTAssertEqual(buckets, [HRBucket(ts: 0, bpm: 60.0), HRBucket(ts: 200, bpm: 61.5)])
    }

    /// Un ancho de 0 se comporta como 1: no divide entre cero ni lanza.
    func testAZeroWidthBucketBehavesAsOneSecond() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let buckets = try await store.hrBuckets(deviceId: "A", from: 0, to: 1000, bucketSeconds: 0)
        XCTAssertEqual(buckets, [HRBucket(ts: 100, bpm: 60), HRBucket(ts: 200, bpm: 61),
                                 HRBucket(ts: 300, bpm: 62)])
    }

    /// La clave natural admite varios intervalos en el mismo instante, así que el orden desempata por
    /// duración para que la lectura sea reproducible.
    func testIntervalsAtTheSameInstantAreOrderedByLength() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(beats, deviceId: "A")
        let rows = try await store.rrIntervals(deviceId: "A", from: 0, to: 1000, limit: 100)
        XCTAssertEqual(rows, [RRInterval(ts: 100, rrMs: 800), RRInterval(ts: 100, rrMs: 820)])
    }

    func testLatestBeatIsNilUntilSomethingIsWritten() async throws {
        let store = try await CenitStore.inMemory()
        let beforeAnything = try await store.latestHRSampleTs(deviceId: "A")
        XCTAssertNil(beforeAnything)

        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 60),
                                                HRSample(ts: 250, bpm: 61)]), deviceId: "A")
        let latest = try await store.latestHRSampleTs(deviceId: "A")
        XCTAssertEqual(latest, 250)
    }

    func testIntegrityCheckPassesOnAHealthyDatabase() async throws {
        let store = try await CenitStore.inMemory()
        let healthy = try await store.integrityCheck()
        XCTAssertTrue(healthy)
    }
}
