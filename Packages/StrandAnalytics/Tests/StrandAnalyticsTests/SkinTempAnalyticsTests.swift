/// Unit tests for the skin-temperature baseline flow (macOS parity with the Android
/// SkinTempAnalyticsTest): the seed→deviation flow over `Baselines.foldHistory` /
/// `Baselines.deviation` with the standard `skin_temp` config — pinning the honest cold-start
/// gate (<4 nights ⇒ no skinTempDevC) and that a real elevation surfaces as a positive deviation
/// once seeded. All values APPROXIMATE.

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
