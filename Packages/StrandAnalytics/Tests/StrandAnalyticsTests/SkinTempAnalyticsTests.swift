import XCTest
@testable import StrandAnalytics

/// Skin temperature through the shared baseline machinery (`Baselines.foldHistory` /
/// `Baselines.deviation`) with the standard `skin_temp` configuration.
///
/// Two properties are pinned here: the honest cold start — too few nights and there is no baseline
/// to trust, so nothing is claimed — and the invariance that makes the displayed deviation
/// meaningful at all. All values APPROXIMATE.
final class SkinTempAnalyticsTests: XCTestCase {

    private var skinCfg: MetricCfg { Baselines.metricCfg["skin_temp"]! }

    /// Ten ordinary nights, in °C.
    private let nights: [Double?] = [33.8, 34.0, 33.9, 34.1, 33.7,
                                     34.0, 33.9, 34.2, 33.8, 34.0]

    func testTooFewNightsIsNotYetTrusted() {
        // Three nights is not a baseline. The state may exist, but nothing may be presented from it.
        let state = Baselines.foldHistory(Array(nights.prefix(3)), cfg: skinCfg)
        XCTAssertFalse(state.trusted,
                       "three nights must not produce a trusted skin-temperature baseline")
    }

    func testSeededBaselineSurfacesARealElevation() {
        // Once seeded, a night clearly above the person's own normal reads as a positive deviation.
        let state = Baselines.foldHistory(nights, cfg: skinCfg)
        XCTAssertTrue(state.usable, "ten nights must at least seed the baseline")
        XCTAssertGreaterThan(Baselines.deviation(35.4, state: state).delta, 0,
                             "a night above the personal normal must read positive")
    }

    func testConstantOffsetCancelsInDeviation() {
        // The UI shows deviation (nightly − baseline). A constant per-band offset added to BOTH the
        // night and the baseline cancels, so the displayed value is robust to the exact offset — its
        // only job is to clear the gate. The cancellation is linear (independent of magnitude); we use
        // a small in-band shift so both baselines stay inside foldHistory's plausibility band and are
        // seeded identically (a large shift like +28.5 would push the base nights to ~62 °C, outside
        // that band — a test artifact, not the production path, where the offset keeps nights ~33–35 °C).
        let tonight = 34.3
        let devNoOffset = Baselines.deviation(
            tonight, state: Baselines.foldHistory(nights, cfg: skinCfg)).delta
        let k = 0.5
        let devShifted = Baselines.deviation(
            tonight + k, state: Baselines.foldHistory(nights.map { $0.map { $0 + k } }, cfg: skinCfg)).delta
        XCTAssertEqual(devNoOffset, devShifted, accuracy: 1e-9,
                       "a constant offset must cancel in the baseline deviation")
    }
}
