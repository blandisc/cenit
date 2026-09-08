import XCTest
@testable import CenitImport

// Pins FER-103: the pure stage-name → HKCategoryValueSleepAnalysis mapping. The sleep write-back path
// (and its `samples(...)` key generator) was retired with the band amputation and deleted in FER-479;
// what remains is the read-side stage vocabulary, tested on macOS without HealthKit via
// `swift test --package-path Packages/CenitImport`.
final class SleepHKEncoderTests: XCTestCase {

    // MARK: - Stage → HK value

    func testDeepMapsToAsleepDeep() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "deep"), SleepHKEncoder.asleepDeepValue)
    }
    func testRemMapsToAsleepREM() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "rem"), SleepHKEncoder.asleepREMValue)
    }
    func testWakeMapsToAwake() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "wake"), SleepHKEncoder.awakeValue)
    }
    func testLightMapsToAsleepCore() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "light"), SleepHKEncoder.asleepCoreValue)
    }
    func testUnknownStageFallsToAsleepCore() {
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: "unknown"), SleepHKEncoder.asleepCoreValue)
        XCTAssertEqual(SleepHKEncoder.hkValue(forStage: ""), SleepHKEncoder.asleepCoreValue)
    }
}
