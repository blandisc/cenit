#if os(iOS)
import CenitDesign
import CenitAnalytics
import Foundation

// MARK: - «Ventana de métrica»: la matemática de ventana compartida por cada detalle (FER-269)
//
// Every metric drill-down — the unified Detalle de Métrica (`MetricDetailScreen`), the sibling detail
// screens (Strain / Stress / Skin temp), Sleep, the Metric Explorer and the Hoy sheets — derives the SAME
// window from a W/M/3M/6M/1Y/ALL selection: the trailing-N-days slice, the Explorer auto-widen (FER-216)
// and the draw-time decimation (FER-219). This file owns that math ONCE so every screen windows the same:
//
//   • `MetricWindow` — one render's window (effective range, its rows/values, the auto-widen flag) plus
//     the shared `hasTrend` gate (≥2 points ⇒ there's a line to draw). Replaces the five identical
//     per-screen `Window` structs.
//   • `MetricWindowMath` — the window math (`slice` / `effectiveRange` / `make` / `decimatedPoints` /
//     `axisLabel`). Pure: it reads the screen's already-parsed series and never touches the database.
//
// The screen still owns `@State range` and its parsed series (each `day` string → `Date` once), computes
// the window ONCE in `body`, and draws it with the Liquid Glass chart (`LiquidGraficaNiveles`).
//
// A companion `MetricTrendChart` view once lived here too (FER-269, built on the legacy `TrendChart`),
// meant to share the selector + line as well. The Liquid Glass · El Eje migration re-based every
// drill-down on `LiquidGraficaNiveles`, which the legacy `TrendChart` could not be re-skinned into
// (docs/design-system/LIQUID-SHEET-CONTRACT.md), so that view was never adopted and was removed as dead
// code; only the design-agnostic math it was bundled with survived. The shared surface is this math (+
// `hasTrend`), not a view.

/// One render's window: the effective range, its rows/values, and whether it auto-widened because the
/// selected range held no points. Replaces the five identical per-screen `Window` structs. (FER-269)
struct MetricWindow {
    let range: ExploreRange
    let rows: [(day: String, value: Double)]
    let values: [Double]
    let fellBack: Bool

    /// The shared minimum-data gate every drill-down draws behind: a trend line needs ≥2 points, so a
    /// window holding 0–1 values shows the screen's own empty well instead of a chart. Centralised here —
    /// it was spelled `window.values.count > 1` inline in each screen — so the threshold can't silently
    /// drift between the sibling details.
    var hasTrend: Bool { values.count > 1 }
}

/// The shared W/M/3M/6M/1Y/ALL window math, lifted verbatim from the per-screen copies so every
/// drill-down derives its window identically (FER-216 auto-widen + FER-219 decimation). Pure: it reads
/// the screen's already-parsed series and never touches the database. (FER-269)
enum MetricWindowMath {
    /// One parsed series row: the `yyyy-MM-dd` key, its `Date` memoised once by the screen, and the value.
    typealias Parsed = [(day: String, date: Date?, value: Double)]

    /// Trailing-N-days slice for `r`, taken RELATIVE TO THE LATEST point (not "now"). Reads the memoized
    /// `date` from `parsed` — no `DateFormatter` work here.
    static func slice(_ parsed: Parsed, for r: ExploreRange) -> [(day: String, value: Double)] {
        guard let days = r.days else { return parsed.map { ($0.day, $0.value) } }
        guard let last = parsed.last?.date else { return [] }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return parsed.compactMap { row in
            guard let d = row.date, d >= cutoff else { return nil }
            return (row.day, row.value)
        }
    }

    /// The selected range, or the smallest larger range whose window holds ≥1 point (Explorer auto-widen).
    static func effectiveRange(_ parsed: Parsed, selected: ExploreRange) -> ExploreRange {
        guard !parsed.isEmpty else { return selected }
        for r in selected.widening where !slice(parsed, for: r).isEmpty { return r }
        return .all
    }

    /// Compute the whole window ONCE per render and hand it to the blocks.
    static func make(_ parsed: Parsed, selected: ExploreRange) -> MetricWindow {
        let eff = effectiveRange(parsed, selected: selected)
        let rows = slice(parsed, for: eff)
        return MetricWindow(range: eff, rows: rows, values: rows.map(\.value), fellBack: eff != selected)
    }

    /// Build the chart's `[TrendPoint]`, decimating long series to ≤`maxPoints` for DRAWING only (FER-219):
    /// the stats above the chart still read the full series; this only thins what the line strokes. Short
    /// ranges (≤`maxPoints`) pass through one point per day, unchanged. Both value and date are bucketed
    /// with the SAME `n*b/maxPoints` partition `SeriesShape.decimate` uses, so each averaged value keeps a
    /// representative (bucket-center) date.
    static func decimatedPoints(rows: [(day: String, value: Double)], values: [Double], maxPoints: Int) -> [TrendPoint] {
        let n = Swift.min(rows.count, values.count)
        guard n > maxPoints, maxPoints > 1 else {
            return zip(rows, values).compactMap { row, value in
                // Anchor each day to NOON UTC (matching TodayView.loadTrend) so the local-zone axis/scrub
                // label doesn't slip to the previous day west of UTC — a 22-jun point read "21 jun" in CDMX
                // (UTC−6) because midnight-UTC fell on the prior local day. (date-mismatch detail vs summary)
                Repository.parseDayKey(row.day).map { TrendPoint(date: $0.addingTimeInterval(12 * 3600), value: value) }
            }
        }
        let decimated = SeriesShape.decimate(Array(values.prefix(n)), maxPoints: maxPoints)
        var out: [TrendPoint] = []
        out.reserveCapacity(decimated.count)
        for b in 0..<decimated.count {
            let lo = (n * b) / maxPoints
            let hi = (n * (b + 1)) / maxPoints
            let mid = Swift.min(lo + (hi - lo) / 2, n - 1)
            if let date = Repository.parseDayKey(rows[mid].day) {
                out.append(TrendPoint(date: date.addingTimeInterval(12 * 3600), value: decimated[b]))   // noon-UTC anchor (see above)
            }
        }
        return out
    }

    /// «jun 6» for a day key, anchored to noon UTC so the local-zone label never slips to the previous
    /// day west of UTC (same fix as `decimatedPoints` above). Was duplicated between Recovery and Sleep
    /// (identical bodies) before promotion (FER-975).
    static func axisLabel(_ dayKey: String) -> String? {
        Repository.parseDayKey(dayKey).map { axisDateFmt.string(from: $0.addingTimeInterval(12 * 3600)) }
    }

    private static let axisDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()
}
#endif
