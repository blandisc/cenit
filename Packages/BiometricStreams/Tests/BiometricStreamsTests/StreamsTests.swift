import XCTest
@testable import BiometricStreams

final class StreamsTests: XCTestCase {
    func testHRSampleEquality() {
        XCTAssertEqual(HRSample(ts: 100, bpm: 60), HRSample(ts: 100, bpm: 60))
        XCTAssertNotEqual(HRSample(ts: 100, bpm: 60), HRSample(ts: 100, bpm: 61))
        XCTAssertNotEqual(HRSample(ts: 100, bpm: 60), HRSample(ts: 200, bpm: 60))
    }

    func testRRIntervalEquality() {
        XCTAssertEqual(RRInterval(ts: 100, rrMs: 800), RRInterval(ts: 100, rrMs: 800))
        XCTAssertNotEqual(RRInterval(ts: 100, rrMs: 800), RRInterval(ts: 100, rrMs: 810))
    }

    func testSkinTempSampleDefaultUnit() {
        let s = SkinTempSample(ts: 1, raw: 4200)
        XCTAssertEqual(s.unit, "raw_adc")
    }

    func testRespSampleDefaultUnit() {
        let r = RespSample(ts: 1, raw: 12)
        XCTAssertEqual(r.unit, "raw_adc")
    }

    func testGravitySampleDefaultUnit() {
        let g = GravitySample(ts: 1, x: 0.1, y: 0.2, z: 0.98)
        XCTAssertEqual(g.unit, "g")
    }

    func testStreamsHROnlyInitializerCompilesWithDefaults() {
        let s = Streams(hr: [HRSample(ts: 1, bpm: 60)])
        XCTAssertEqual(s.hr, [HRSample(ts: 1, bpm: 60)])
        XCTAssertTrue(s.rr.isEmpty)
        XCTAssertTrue(s.skinTemp.isEmpty)
        XCTAssertTrue(s.resp.isEmpty)
        XCTAssertTrue(s.gravity.isEmpty)
    }

    func testStreamsMemberwiseInitializer() {
        let s = Streams(
            hr: [HRSample(ts: 1, bpm: 60)],
            rr: [RRInterval(ts: 1, rrMs: 800)],
            skinTemp: [SkinTempSample(ts: 1, raw: 100)],
            resp: [RespSample(ts: 1, raw: 12)],
            gravity: [GravitySample(ts: 1, x: 0, y: 0, z: 1)])
        XCTAssertEqual(s.hr.count, 1)
        XCTAssertEqual(s.rr.count, 1)
        XCTAssertEqual(s.skinTemp.count, 1)
        XCTAssertEqual(s.resp.count, 1)
        XCTAssertEqual(s.gravity.count, 1)
    }

    func testStreamsIsEmptyOnlyWhenEveryStreamIsEmpty() {
        XCTAssertTrue(Streams().isEmpty)
        XCTAssertFalse(Streams(hr: [HRSample(ts: 1, bpm: 60)]).isEmpty)
        XCTAssertFalse(Streams(rr: [RRInterval(ts: 1, rrMs: 800)]).isEmpty)
        XCTAssertFalse(Streams(skinTemp: [SkinTempSample(ts: 1, raw: 1)]).isEmpty)
        XCTAssertFalse(Streams(resp: [RespSample(ts: 1, raw: 1)]).isEmpty)
        XCTAssertFalse(Streams(gravity: [GravitySample(ts: 1, x: 0, y: 0, z: 1)]).isEmpty)
    }

    func testStreamsEquality() {
        let a = Streams(hr: [HRSample(ts: 1, bpm: 60)], rr: [RRInterval(ts: 1, rrMs: 800)])
        let b = Streams(hr: [HRSample(ts: 1, bpm: 60)], rr: [RRInterval(ts: 1, rrMs: 800)])
        let c = Streams(hr: [HRSample(ts: 1, bpm: 61)], rr: [RRInterval(ts: 1, rrMs: 800)])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testStreamsCodableRoundTrips() throws {
        let s = Streams(
            hr: [HRSample(ts: 1, bpm: 60), HRSample(ts: 2, bpm: 61)],
            rr: [RRInterval(ts: 1, rrMs: 800)],
            skinTemp: [SkinTempSample(ts: 1, raw: 100)],
            resp: [RespSample(ts: 1, raw: 12)],
            gravity: [GravitySample(ts: 1, x: 0.1, y: 0.2, z: 0.98)])
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Streams.self, from: data)
        XCTAssertEqual(s, decoded)
    }
}
