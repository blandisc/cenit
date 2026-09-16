#if os(iOS)
import SwiftUI
import CenitStore
import CenitDesign
import CenitAnalytics
import Foundation

extension MetricDetailScreen {

    // MARK: - Depth → visible blocks

    /// `.full` shows everything the spec declares; `.focus` shows only the day-photo subset.
    var visibleBlocks: BlockSet {
        switch depth {
        case .full:  return spec.blocks
        case .focus: return spec.blocks.intersection([.seriesChartBand, .normalRange, .method, .nightVitals, .intradayCurve, .hrZones])
        }
    }

    /// The default window: a short week in focus, a month at full depth.
    var defaultRange: ExploreRange { depth == .focus ? .week : .month }

    /// Resolve a `LocalizedStringKey` band label to a plain String for GraficaRangos lane copy.
    func plainLocalizedLabel(_ key: LocalizedStringKey) -> String {
        let mirror = Mirror(reflecting: key)
        for child in mirror.children {
            if child.label == "key", let s = child.value as? String {
                return String(localized: String.LocalizationValue(s))
            }
        }
        return ""
    }

    /// Colour of one population lane, keyed off the band's engine KEY — never its position in the
    /// array. Positional ramps were the TND-19 defect class: when SpO₂ and Respiration shrank to the
    /// engine's two bands, the stale index ramps painted SpO₂'s «low (< 95)» lane green (verdict) and
    /// «normal» amber — inverted — and Respiration's «elevated (≥ 20)» green. A band with no engine
    /// key (or an unmapped one) falls back to the caller's hue. Static (fallback injected) so the
    /// key→colour map is pinned by `MetricInfoEscaleraUnicaTests`.
    static func laneColor(metric: String, bandKey: String?, fallback: Color) -> Color {
        switch (metric, bandKey) {
        case ("spo2", "normal"):
            return LiquidColor.verdePrimario
        case ("spo2", "low"):
            // < 95% absorbs the retired «Borderline» stretch (90–95), so it reads warning, not the old
            // sub-90 critical: one band, one honest amber — same softening logic as rhr's FER-43.
            return LiquidColor.atencion
        // Athlete range / Low / Typical / Higher — lower is better. FER-43 (gate /cso): la banda
        // alta baja de `critical` a `warning`. Se suavizó la PALABRA («Higher», no «Elevated»)
        // porque >80 lpm sigue dentro del normal adulto de la AHA (60–100); dejar el rojo de
        // alarma hacía que el color siguiera gritando lo que el copy ya no afirma.
        case ("rhr", "rhrAthlete"):
            return LiquidColor.verdeProfundo
        case ("rhr", "rhrLow"):
            return LiquidColor.verdePrimario
        case ("rhr", "rhrTypical"):
            return LiquidColor.tinta700
        case ("rhr", "rhrHigher"):
            return LiquidColor.atencion
        case ("resp_rate", "normal"):
            return LiquidColor.verdePrimario
        case ("resp_rate", "elevated"):
            return LiquidColor.atencion
        default:
            return fallback
        }
    }

    var unit: String { spec.info.unit ?? "" }

    /// The three vitals the band and Apple measure with different instruments — folding both sources into
    /// one baseline/σ, CV or Δ% mixes two scales (FER-629). SpO₂/steps/skin-temp/VO₂max are single-source. (FER-635)
    var isCrossSource: Bool { ["hrv", "rhr", "resp_rate"].contains(spec.descriptor.key) }

    /// Whether a rise is good for this metric, from the catalog's `higherIsBetter` — drives the trend
    /// chip's colour in `TrendStatSummary`. HRV rises = good, resting HR rises = bad, respiration neutral.
    var trendPolarity: TrendStatSummary.Polarity {
        switch spec.descriptor.higherIsBetter {
        case .some(true):  return .higherIsBetter
        case .some(false): return .lowerIsBetter
        case .none:        return .neutral
        }
    }

    /// The category as a display word — the same labels the former four-band table used. (FER-833)
    func vo2maxCategoryWord(_ c: VO2maxReference.Category) -> String {
        switch c {
        case .low:       return String(localized: "Low")
        case .average:   return String(localized: "Average")
        case .good:      return String(localized: "Good")
        case .excellent: return String(localized: "Excellent")
        }
    }

    /// Format a value with the descriptor's own decimal precision. Integers get locale grouping so a
    /// four-figure step count reads "9,210", not "9210"; the vitals stay under 1,000 so they're
    /// visually unchanged. (FER-254)
    func fmt(_ v: Double) -> String {
        guard v.isFinite else { return "—" }   // FER-465: NaN/±Inf → «—», nunca `Int(nan)` (trap)
        guard spec.descriptor.decimals == 0 else {
            return CenitFormat.decimal(v, places: spec.descriptor.decimals)
        }
        return CenitFormat.groupedInt(v)
    }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter
}
#endif
