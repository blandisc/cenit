import XCTest
@testable import CenitAnalytics

/// FER-60: pins the cold-start contract the Apple Health baseline prior relies on. Folding a handful
/// of seed nights (the capped seed prior injected from Apple Health history) must take the HRV
/// baseline from CALIBRATING — where there is nothing honest to say — to PROVISIONAL, where it is
/// usable but the FER-13 confidence shrinkage still damps whatever is built on it. A capped prior
/// must NOT vault straight to TRUSTED.
final class ColdStartPriorTests: XCTestCase {

    func testBelowSeedGateIsNotUsable() {
        // 3 nights < minNightsSeed (4): the baseline is still calibrating and nothing may be read
        // off it. Refusing to answer is the honest cold start.
        let seq: [Double?] = [55, 58, 56]
        let cold = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertFalse(cold.usable)
    }

    func testSeedNightPriorCrossesGateAsProvisional() {
        // 7 seeded nights — what a capped Apple Health prior (applePriorMaxNights) injects: the
        // baseline becomes PROVISIONAL — usable, yet below minNightsTrust (14) so it stays shrunk.
        let seq: [Double?] = [60, 58, 61, 59, 57, 62, 56]
        let seeded = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertTrue(seeded.usable, "7 seed nights must clear the seed gate")
        XCTAssertEqual(seeded.status, .provisional, "a capped prior stays provisional, not trusted")
        XCTAssertLessThan(seeded.nValid, Baselines.minNightsTrust)
        XCTAssertFalse(seeded.trusted)
        // Shrinkage is still on: a provisional baseline damps whatever is read against it.
        XCTAssertLessThan(Baselines.confidence(nValid: seeded.nValid), 1.0)
    }
}
