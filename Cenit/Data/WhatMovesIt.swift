import Foundation
import CenitAnalytics
import CenitStore

// WhatMovesIt.swift — the app-layer adapter for the «Tu patrón» block. (FER-209 → FER-438)
//
// The engine — relationships, statistics, effective n, minority floor, Benjamini-Hochberg over the
// family — lives in `CenitAnalytics.WhatMovesItEngine` (pure, `swift test`). This file only (1) asks
// the family for one metric's findings off the repo's daily history and (2) resolves a finding's
// catalog key to its sentence. Nothing else: no pair selection, no copy switch.

extension WhatMovesItFinding {
    /// The «Tu patrón» sentence — the ONE home of the copy, resolved from the catalog by
    /// `copyKey` (`patron.<relationship>.<rises|falls>`), so every surface (summary sheet, metric detail,
    /// strain detail) reads the same string and none can drift. Two sentences, «se mueve con», never a
    /// cause. (FER-731 lesson; FER-438)
    var phrase: String {
        String(localized: String.LocalizationValue(copyKey))
    }
}

extension WhatMovesItEngine {
    /// The gated, directional findings for the metric `key` (`sleep`, `strain`, `sleep_efficiency`,
    /// `steps`, `rhr`, `hrv`), computed from the daily history. `today` is the device's local day key
    /// (`Repository.localDayKey`): rows after it are ignored and today's partial step count is dropped.
    /// `hrvNights` — the dense-night RMSSD partition (`repo.nightlyRmssd`) the two `hrv.*` relationships
    /// read; `[]` (the default) simply leaves them untestable, same as any caller that has none.
    /// `[]` when the metric carries no relationship or none clears the gate → the block stays hidden.
    static func findings(forMetricKey key: String, days: [DailyMetric], today: String,
                         hrvNights: [(day: String, rmssdMs: Double)] = []) -> [WhatMovesItFinding] {
        family(days: days, today: today, hrvNights: hrvNights)[key] ?? []
    }
}
