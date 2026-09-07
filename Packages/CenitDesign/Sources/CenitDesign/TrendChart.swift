import SwiftUI
import Charts

// MARK: - Trend Chart (§9.4 Trends)
//
// A line/area chart whose stroke is gradient-colored by value — reusable for recovery / HRV / RHR /
// strain trends. Defaults to the recovery scale, but any gradient + value range works.

/// One point on a trend line.
public struct TrendPoint: Identifiable, Sendable, Equatable {
    public var date: Date, value: Double
    public let id = UUID()

    public init(date: Date, value: Double) {
        (self.date, self.value) = (date, value)
    }
}

// MARK: - Classification bands

/// One classification band drawn behind a trend line (e.g. sleep "Optimal 7–9h"). Bounds form a
/// half-open interval `[lower, upper)`; `nil` on a side means open on that side, and BOTH `nil` means no
/// interval at all — such a band classifies NOTHING (an unbounded band must never silently swallow
/// every value a caller forgot to bound).
public struct TrendBand: Identifiable, Equatable {
    public let id = UUID()
    public var label: LocalizedStringKey
    public var lower: Double?
    public var upper: Double?
    public var isActive: Bool

    public init(label: LocalizedStringKey, lower: Double?, upper: Double?, isActive: Bool = false) {
        self.label = label
        self.lower = lower
        self.upper = upper
        self.isActive = isActive
    }

    /// Whether `value` falls in this band's half-open interval.
    public func contains(_ value: Double) -> Bool {
        guard lower != nil || upper != nil else { return false }
        return (lower == nil || value >= lower!) && (upper == nil || value < upper!)
    }
}

/// Pure band math (no SwiftUI), so it's unit-testable on its own.
public enum TrendBands {
    /// Index of the band containing `value`, or `nil` if none does.
    public static func index(containing value: Double, in bands: [TrendBand]) -> Int? {
        bands.firstIndex { $0.contains(value) }
    }

    /// The band the LAST value falls into, plus how many of `values` share that band.
    public static func activeBand(values: [Double], bands: [TrendBand]) -> (index: Int, count: Int)? {
        guard let last = values.last, let idx = index(containing: last, in: bands) else { return nil }
        let count = values.reduce(0) { $0 + (bands[idx].contains($1) ? 1 : 0) }
        return (idx, count)
    }

    /// Summarizes how `values` distribute across `bands`, and where `todayIndex` sits relative to the
    /// dominant one. Returns `nil` when there are no bands or no value lands in any of them.
    public static func summarize(values: [Double], bands: [TrendBand], todayIndex: Int?) -> BandTrendSummary? {
        guard !bands.isEmpty else { return nil }
        var counts = Array(repeating: 0, count: bands.count)
        var n = 0
        for value in values {
            if let i = index(containing: value, in: bands) { counts[i] += 1; n += 1 }
        }
        guard n > 0 else { return nil }

        // Ties break toward the LOWER band index, for a deterministic result.
        let ranked = counts.indices.sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
        let dominant = ranked[0]
        let second: Int? = (ranked.count > 1 && counts[ranked[1]] > 0) ? ranked[1] : nil
        let dominantCount = counts[dominant]
        let share = Double(dominantCount) / Double(n)

        let tier: BandTrendSummary.Tier
        if dominantCount == n {
            tier = .always
        } else if share >= 0.8 {
            tier = .almostAlways
        } else if share >= 0.5, second == nil || dominantCount > counts[second!] {
            tier = .mostly
        } else if let second, abs(dominant - second) == 1,
                  Double(dominantCount + counts[second]) / Double(n) >= 0.7 {
            tier = .alternating
        } else {
            tier = .scattered
        }

        let relation: BandTrendSummary.Relation?
        if let todayIndex {
            relation = todayIndex == dominant ? .same : (todayIndex < dominant ? .lower : .higher)
        } else {
            relation = nil
        }
        return BandTrendSummary(counts: counts, n: n, dominant: dominant, second: second,
                                 tier: tier, todayIndex: todayIndex, todayVsDominant: relation)
    }
}

/// A plain-language reading of how a windowed series sits across its bands, built by
/// `TrendBands.summarize`.
public struct BandTrendSummary: Equatable {
    public let counts: [Int]
    public let n: Int
    public let dominant: Int
    public let second: Int?
    public let tier: Tier
    public let todayIndex: Int?
    public let todayVsDominant: Relation?

    public init(counts: [Int], n: Int, dominant: Int, second: Int?, tier: Tier,
                todayIndex: Int?, todayVsDominant: Relation?) {
        self.counts = counts
        self.n = n
        self.dominant = dominant
        self.second = second
        self.tier = tier
        self.todayIndex = todayIndex
        self.todayVsDominant = todayVsDominant
    }

    /// How concentrated the window is in its dominant band.
    public enum Tier: Equatable {
        case always
        case almostAlways
        case mostly
        case alternating
        case scattered
    }

    /// Where today's reading sits relative to the dominant band, by band order.
    public enum Relation: Equatable { case same, lower, higher }
}

// MARK: - The chart

public struct TrendChart: View {

    public var points: [TrendPoint]
    public var gradient: Gradient
    public var valueRange: ClosedRange<Double>
    public var showsArea: Bool
    public var height: CGFloat
    public var showsScrub: Bool
    public var valueFormat: (Double) -> String
    public var dateFormat: (Date) -> String
    public var axisLabelColor: Color
    public var gridLineColor: Color
    public var bands: [TrendBand]
    public var bandColor: Color
    public var yAxisValues: [Double]?
    /// Points below this value are drawn in `alertColor` instead of the gradient (e.g. a low SpO₂ night).
    public var alertThreshold: Double?
    public var alertColor: Color
    /// A dashed horizontal reference line (e.g. the night's resting HR under an HR curve).
    public var referenceLine: Double?
    public var referenceLineColor: Color
    /// A single point emphasised with a larger dot (e.g. the day's peak).
    public var markedPoint: TrendPoint?
    /// Draws `markedPoint` as a hollow ring (a `markedPointRingFill`-filled centre) instead of solid, so
    /// it still reads as "today" even while a DIFFERENT band is highlighted.
    public var markedPointHollow: Bool
    public var markedPointRingFill: Color
    /// Draws bands (fill + edge lines) WITHOUT their right-aligned label, dropping the gutter it needs.
    public var bandLabelsHidden: Bool
    /// When true and there are no right-side band labels, the trailing inset shrinks to a thin breath so
    /// the curve reaches the edge.
    public var tightTrailing: Bool
    public var yTickCount: Int
    /// Appended to the scrub tooltip's value line (e.g. "avg 7d") — never shown on the Y-axis labels.
    public var valueSuffix: String?
    public var accessibilityLabel: LocalizedStringKey?
    public var accessibilityValueText: String?

    public init(
        points: [TrendPoint],
        gradient: Gradient = StrandPalette.recoveryGradient,
        valueRange: ClosedRange<Double> = 0...100,
        showsArea: Bool = true,
        height: CGFloat = 220,
        showsScrub: Bool = true,
        valueFormat: @escaping (Double) -> String = { String(Int($0.rounded())) },
        dateFormat: @escaping (Date) -> String = { TrendChart.defaultDateString($0) },
        axisLabelColor: Color = InstrumentoTheme.base.inkTertiary,
        gridLineColor: Color = InstrumentoTheme.base.hairline,
        bands: [TrendBand] = [],
        bandColor: Color = .clear,
        yAxisValues: [Double]? = nil,
        alertThreshold: Double? = nil,
        alertColor: Color = .clear,
        referenceLine: Double? = nil,
        referenceLineColor: Color = .clear,
        markedPoint: TrendPoint? = nil,
        markedPointHollow: Bool = false,
        markedPointRingFill: Color = .clear,
        bandLabelsHidden: Bool = false,
        tightTrailing: Bool = false,
        yTickCount: Int = 4,
        valueSuffix: String? = nil,
        accessibilityLabel: LocalizedStringKey? = nil,
        accessibilityValueText: String? = nil
    ) {
        self.points = points.sorted { $0.date < $1.date }
        self.gradient = gradient
        self.valueRange = valueRange
        self.showsArea = showsArea
        self.height = height
        self.showsScrub = showsScrub
        self.valueFormat = valueFormat
        self.dateFormat = dateFormat
        self.axisLabelColor = axisLabelColor
        self.gridLineColor = gridLineColor
        self.bands = bands
        self.bandColor = bandColor
        self.yAxisValues = yAxisValues
        self.alertThreshold = alertThreshold
        self.alertColor = alertColor
        self.referenceLine = referenceLine
        self.referenceLineColor = referenceLineColor
        self.markedPoint = markedPoint
        self.markedPointHollow = markedPointHollow
        self.markedPointRingFill = markedPointRingFill
        self.bandLabelsHidden = bandLabelsHidden
        self.tightTrailing = tightTrailing
        self.yTickCount = yTickCount
        self.valueSuffix = valueSuffix
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValueText = accessibilityValueText
    }

    /// Right inset on the X-scale: a wide gutter for a labelled band, else the default inset — or a thin
    /// breath when `tightTrailing` opts the curve into reaching the edge.
    private var trailingInset: CGFloat {
        if !(bands.isEmpty || bandLabelsHidden) { return 64 }
        return tightTrailing ? 8 : CenitMetrics.chartXTrailingInset
    }

    @State private var hoverX: CGFloat? = nil
    /// The point under the finger while scrubbing — drives the VoiceOver value.
    @State private var scrubbedPoint: TrendPoint? = nil

    private static let sharedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    private var resolvedAccessibilityValue: String {
        if let custom = accessibilityValueText { return custom }
        guard let reading = scrubbedPoint ?? points.last else { return "No data" }
        let valueText = valueSuffix.map { "\(valueFormat(reading.value)) · \($0)" } ?? valueFormat(reading.value)
        return "\(valueText), \(dateFormat(reading.date))"
    }

    /// Default tooltip/axis date format ("EEE d MMM").
    public static func defaultDateString(_ date: Date) -> String {
        sharedDateFormatter.string(from: date)
    }

    private func nearestPoint(toX x: CGFloat, proxy: ChartProxy, plot: CGRect) -> TrendPoint? {
        guard !points.isEmpty else { return nil }
        guard let hoveredDate: Date = proxy.value(atX: x - plot.minX) else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(hoveredDate)) < abs(rhs.date.timeIntervalSince(hoveredDate))
        }
    }

    /// Maps a raw value onto 0...1 within `valueRange`, clamped.
    private func unit(_ value: Double) -> Double {
        let domainFloor = valueRange.lowerBound, domainCeiling = valueRange.upperBound
        guard domainCeiling > domainFloor else { return 0 }
        let fraction = (value - domainFloor) / (domainCeiling - domainFloor)
        return Swift.min(Swift.max(fraction, 0), 1)
    }

    private var valueGradient: LinearGradient {
        LinearGradient(gradient: gradient, startPoint: .bottom, endPoint: .top)
    }

    public var body: some View {
        Chart {
            if let referenceLine {
                RuleMark(y: .value("Reference", referenceLine))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(referenceLineColor)
            }
            if showsArea {
                ForEach(points) { point in
                    // yStart pins to the domain floor, NOT an implicit zero baseline: with a tight
                    // domain (e.g. HR 64...145) zero sits below it, so a plain fill would bleed clear to
                    // the plot's bottom edge, straight behind the X-axis labels.
                    AreaMark(x: .value("Date", point.date),
                             yStart: .value("Floor", valueRange.lowerBound),
                             yEnd: .value("Value", point.value))
                        // monotone, not catmullRom — Catmull-Rom can overshoot past the data on a
                        // tightly-oscillating series, dipping the curve below the domain.
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    StrandPalette.sample(stops: gradient.toStops(), at: unit(averageValue)).opacity(0.28),
                                    Color.clear,
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(valueGradient)
            }
            // Per-point dots only on short series — a dense multi-month line skips them (clutter + cost).
            if points.count <= 60 {
                ForEach(points) { point in
                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .symbolSize(18)
                        .foregroundStyle(
                            (alertThreshold.map { point.value < $0 } ?? false)
                                ? alertColor
                                : StrandPalette.sample(stops: gradient.toStops(), at: unit(point.value))
                        )
                }
            }
            if let marked = markedPoint {
                let hue = StrandPalette.sample(stops: gradient.toStops(), at: unit(marked.value))
                if markedPointHollow {
                    PointMark(x: .value("Date", marked.date), y: .value("Value", marked.value))
                        .symbolSize(92).foregroundStyle(hue)
                    PointMark(x: .value("Date", marked.date), y: .value("Value", marked.value))
                        .symbolSize(34).foregroundStyle(markedPointRingFill)
                } else {
                    PointMark(x: .value("Date", marked.date), y: .value("Value", marked.value))
                        .symbolSize(70).foregroundStyle(hue)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? "Trend chart"))
        .accessibilityValue(Text(resolvedAccessibilityValue))
        // Switching the whole series (e.g. a period toggle) snaps in — no point-by-point draw-on morph.
        .animation(.none, value: points)
        .chartYScale(domain: valueRange, range: .plotDimension(startPadding: CenitMetrics.chartXLabelBand, endPadding: 0))
        .chartXScale(range: .plotDimension(startPadding: 0, endPadding: trailingInset))
        .chartXAxis {
            // Five ticks spread across the ACTUAL data span — `.automatic` snaps to calendar boundaries
            // and can bunch every tick into one side of a short window.
            AxisMarks(values: xAxisTicks) { value in
                AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                AxisValueLabel(anchor: xLabelAnchor(value.index, count: value.count)) {
                    if let date = value.as(Date.self) { Text(xAxisLabel(date)) }
                }
                .foregroundStyle(axisLabelColor)
                .font(StrandFont.footnote)
            }
        }
        .chartYAxis {
            if let yAxisValues {
                AxisMarks(position: .leading, values: yAxisValues) { value in
                    AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(valueFormat(v)) }
                    }
                    .foregroundStyle(axisLabelColor)
                    .font(StrandFont.footnote)
                }
            } else {
                AxisMarks(position: .leading, values: .automatic(desiredCount: yTickCount)) { _ in
                    AxisGridLine().foregroundStyle(gridLineColor.opacity(0.4))
                    AxisValueLabel().foregroundStyle(axisLabelColor).font(StrandFont.footnote)
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
                ZStack(alignment: .topLeading) {
                    ForEach(bands) { band in bandLayer(band, proxy: proxy, plot: plot) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
                let snappedIndex: Int? = (showsScrub ? hoverX : nil).flatMap { x in
                    nearestPoint(toX: x, proxy: proxy, plot: plot).flatMap { points.firstIndex(of: $0) }
                }
                ZStack(alignment: .topLeading) {
                    // A full-bleed transparent layer gives the scrub gesture a hittable area from the
                    // very first touch — without it this ZStack is 0×0 until a point is already scrubbed.
                    Color.clear
                        .onChange(of: snappedIndex) { _, idx in
                            if let idx {
                                ChartHaptics.datumChanged()
                                scrubbedPoint = points[idx]
                            } else {
                                scrubbedPoint = nil
                            }
                        }
                    if showsScrub, let x = hoverX,
                       let point = nearestPoint(toX: x, proxy: proxy, plot: plot),
                       let plotX = proxy.position(forX: point.date),
                       let plotY = proxy.position(forY: point.value) {
                        let anchorPoint = CGPoint(x: plotX + plot.minX, y: plotY + plot.minY)
                        let color = StrandPalette.sample(stops: gradient.toStops(), at: unit(point.value))
                        CrosshairRule(x: anchorPoint.x, height: geo.size.height)
                        HighlightDot(color: color).position(anchorPoint)
                        PositionedTooltip(
                            anchor: anchorPoint,
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: valueSuffix.map { "\(valueFormat(point.value)) · \($0)" } ?? valueFormat(point.value),
                                label: dateFormat(point.date),
                                accent: color
                            )
                        )
                    }
                }
                .animation(StrandMotion.fade, value: hoverX)
                .contentShape(Rectangle())
                .scrubGesture(enabled: showsScrub, hoverX: $hoverX)
            }
        }
        .frame(height: height)
    }

    private var averageValue: Double {
        guard !points.isEmpty else { return valueRange.lowerBound }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    /// Five tick dates at 0/25/50/75/100% of the data's ACTUAL time span — anchored to the data, not the
    /// calendar, so the labels always span the chart's full width.
    private var xAxisTicks: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return [first] }
        return [0.0, 0.25, 0.5, 0.75, 1.0].map { first.addingTimeInterval(span * $0) }
    }

    /// Keeps the first label leading-aligned and the last trailing-aligned so neither clips at the plot
    /// edge; the gridline still sits exactly on the tick.
    private func xLabelAnchor(_ index: Int, count: Int) -> UnitPoint {
        if index == 0 { return .topLeading }
        if index == count - 1 { return .topTrailing }
        return .top
    }

    /// Picks a label template by how wide the window is: intraday → hour, up to ~10 months → day+month,
    /// longer → month+year.
    private func xAxisLabel(_ date: Date) -> String {
        let span = (points.last?.date.timeIntervalSince(points.first?.date ?? date)) ?? 0
        let formatter = TrendChart.axisFormatter
        if span <= 36 * 3600 {
            formatter.setLocalizedDateFormatFromTemplate("ha")
        } else if span <= 300 * 86_400 {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMyy")
        }
        return formatter.string(from: date)
    }

    private static let axisFormatter = DateFormatter()

    /// Draws one classification band: the active band gets a soft fill + edge lines; any band tall
    /// enough gets a right-aligned label (the active one always does, even when geometrically thin — the
    /// one band you most need named shouldn't be the one that goes unlabelled).
    @ViewBuilder
    private func bandLayer(_ band: TrendBand, proxy: ChartProxy, plot: CGRect) -> some View {
        let top = min(band.upper ?? valueRange.upperBound, valueRange.upperBound)
        let bottom = max(band.lower ?? valueRange.lowerBound, valueRange.lowerBound)
        if let pTop = proxy.position(forY: top), let pBottom = proxy.position(forY: bottom) {
            let yTop = plot.minY + min(pTop, pBottom)
            let bandHeight = abs(pBottom - pTop)
            if band.isActive {
                Rectangle().fill(bandColor.opacity(0.16))
                    .frame(width: plot.width, height: bandHeight).offset(x: plot.minX, y: yTop)
                Rectangle().fill(bandColor.opacity(0.5))
                    .frame(width: plot.width, height: 1).offset(x: plot.minX, y: yTop)
                Rectangle().fill(bandColor.opacity(0.5))
                    .frame(width: plot.width, height: 1).offset(x: plot.minX, y: yTop + bandHeight - 1)
            }
            if !bandLabelsHidden, bandHeight >= 16 || band.isActive {
                Text(band.label)
                    .font(StrandFont.footnote)
                    .fontWeight(band.isActive ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(band.isActive ? bandColor : axisLabelColor.opacity(0.8))
                    .frame(width: plot.width - 6, alignment: .trailing)
                    .offset(x: plot.minX, y: yTop + bandHeight / 2 - 8)
            }
        }
    }
}

// MARK: - Platform scrub gesture
//
// Shared (module-internal, not file-private) so sibling charts in the package inherit the exact same
// finger-drag/hover affordance instead of re-implementing it.
extension View {
    /// Attaches the chart-scrub affordance: a `DragGesture` on iOS (no minimum distance, so the
    /// crosshair appears on first touch), pointer hover on macOS, a no-op on watchOS (which never
    /// renders a scrubbable chart from this package but must still build). Both platforms drive the same
    /// `hoverX` binding a caller's overlay reads to draw its crosshair + tooltip.
    ///
    /// `.highPriorityGesture` on iOS is deliberate: these charts live inside a ScrollView, and a plain
    /// `.gesture()` loses the touch to the parent's vertical pan.
    @ViewBuilder
    public func scrubGesture(enabled: Bool, hoverX: Binding<CGFloat?>) -> some View {
        #if os(iOS)
        self.highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard enabled else { return }
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { hoverX.wrappedValue = drag.location.x }
                }
                .onEnded { _ in
                    guard enabled else { return }
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { hoverX.wrappedValue = nil }
                }
        )
        #elseif os(macOS)
        self.onContinuousHover(coordinateSpace: .local) { phase in
            guard enabled else { return }
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) {
                switch phase {
                case .active(let location): hoverX.wrappedValue = location.x
                case .ended: hoverX.wrappedValue = nil
                }
            }
        }
        #else
        self
        #endif
    }
}

// MARK: - Gradient → stops bridge

extension Gradient {
    /// Reconstructs ordered stops from a `Gradient` for the sampler above.
    func toStops() -> [Gradient.Stop] { self.stops }
}

#if DEBUG
private struct SyntheticSeries {
    let base: Double, amplitude: Double
    func points(days: Int) -> [TrendPoint] {
        let today = Date()
        return stride(from: 0, to: days, by: 1).map { offset in
            let daysAgo = days - 1 - offset
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let wobble = amplitude * sin(Double(offset) / 3.0)
            let noise = Double((offset * 17) % 9) - 4.0
            return TrendPoint(date: date, value: Swift.max(0.0, base + wobble + noise))
        }
    }
}

private struct TrendChartPreviewCard<Extra: View>: View {
    let caption: String
    let series: [TrendPoint]
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var chart: () -> TrendChart

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption).strandOverline()
            extra()
            chart()
        }
        .padding(28)
        .frame(width: 720, height: 340)
        .background(InstrumentoTheme.base.paper)
        .preferredColorScheme(.light)
    }
}

#Preview("TrendChart — recovery") {
    let series = SyntheticSeries(base: 62, amplitude: 22).points(days: 30)
    return TrendChartPreviewCard(caption: "Recovery — 30 days", series: series) {
        Text("Hover the line: crosshair + dot + date/value tooltip.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
    } chart: {
        TrendChart(points: series)
    }
}

#Preview("TrendChart — HRV") {
    let series = SyntheticSeries(base: 58, amplitude: 14).points(days: 30)
    return TrendChartPreviewCard(caption: "HRV (ms) — 30 days", series: series) {
        EmptyView()
    } chart: {
        TrendChart(points: series, valueRange: 20...100, valueFormat: { "\(Int($0.rounded())) ms" })
    }
}
#endif
