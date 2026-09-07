import SwiftUI

// MARK: - Sparkline (§9.4 Today / live-HR tile)
//
// A tiny inline line for a short numeric series (live HR, a compact tile trend). Gradient-stroked, with
// an optional glowing head dot at the latest sample and a faint area wash underneath.

public struct Sparkline: View {

    public var values: [Double]
    public var gradient: Gradient
    /// Explicit value range; otherwise auto-fit with padding.
    public var range: ClosedRange<Double>?
    /// An optional reference band (e.g. a typical p25–p75 range) drawn faintly BEHIND the line, in an
    /// ink tone — never a data hue, so today's value still reads in context rather than competing.
    public var referenceBand: ClosedRange<Double>?
    public var bandColor: Color
    /// An optional dashed mean/average rule across the chart, on the same axis as the line.
    public var meanLine: Double?
    public var meanLineColor: Color
    public var lineWidth: CGFloat
    public var showsArea: Bool
    public var showsHead: Bool
    public var showsScrub: Bool
    public var valueFormat: (Double) -> String
    /// Secondary label for a sample by index (e.g. a timestamp). Falls back to "sample N".
    public var indexLabel: ((Int) -> String)?

    public init(
        values: [Double],
        gradient: Gradient = StrandPalette.recoveryGradient,
        range: ClosedRange<Double>? = nil,
        referenceBand: ClosedRange<Double>? = nil,
        bandColor: Color = InstrumentoTheme.base.hairlineStrong,
        meanLine: Double? = nil,
        meanLineColor: Color = InstrumentoTheme.base.hairlineStrong,
        lineWidth: CGFloat = 2,
        showsArea: Bool = true,
        showsHead: Bool = true,
        showsScrub: Bool = true,
        valueFormat: @escaping (Double) -> String = { Sparkline.defaultValueString($0) },
        indexLabel: ((Int) -> String)? = nil
    ) {
        self.values = values
        self.gradient = gradient
        self.range = range
        self.referenceBand = referenceBand
        self.bandColor = bandColor
        self.meanLine = meanLine
        self.meanLineColor = meanLineColor
        self.lineWidth = lineWidth
        self.showsArea = showsArea
        self.showsHead = showsHead
        self.showsScrub = showsScrub
        self.valueFormat = valueFormat
        self.indexLabel = indexLabel
    }

    @State private var hoverX: CGFloat? = nil

    /// Flat (no glow/bloom) in the «Instrumento diurno» light language.
    @Environment(\.instrumentoFlat) private var flat

    /// Integer when the value is whole, else one decimal.
    public static func defaultValueString(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// The value extent the line is drawn against, folding `referenceBand` in so it never clips.
    private var bounds: (min: Double, max: Double) {
        if let range { return (range.lowerBound, range.upperBound) }

        var floor = values.min()
        var ceiling = values.max()
        if let band = referenceBand {
            floor = Swift.min(floor ?? band.lowerBound, band.lowerBound)
            ceiling = Swift.max(ceiling ?? band.upperBound, band.upperBound)
        }
        guard let floor, let ceiling else { return (0, 1) }
        guard floor != ceiling else { return (floor - 1, ceiling + 1) }

        let breathingRoom = (ceiling - floor) * 0.12
        return (floor - breathingRoom, ceiling + breathingRoom)
    }

    public var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            ZStack {
                if let band = referenceBand {
                    let yTop = y(for: band.upperBound, height: geo.size.height)
                    let yBottom = y(for: band.lowerBound, height: geo.size.height)
                    Rectangle()
                        .fill(bandColor.opacity(0.18))
                        .frame(height: Swift.max(1, yBottom - yTop))
                        .position(x: geo.size.width / 2, y: (yTop + yBottom) / 2)
                }
                if let mean = meanLine, points.count > 1 {
                    let meanY = y(for: mean, height: geo.size.height)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: meanY))
                        path.addLine(to: CGPoint(x: geo.size.width, y: meanY))
                    }
                    .stroke(meanLineColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if showsArea, points.count > 1 {
                    areaPath(points, in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    StrandPalette.sample(stops: gradient.stops, at: 0.7).opacity(0.22),
                                    Color.clear,
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
                if points.count > 1 {
                    linePath(points)
                        .stroke(
                            LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }
                if showsHead, let head = points.last {
                    let headColor = StrandPalette.sample(stops: gradient.stops, at: 1.0)
                    if flat {
                        Circle().fill(headColor).frame(width: lineWidth * 2.4, height: lineWidth * 2.4).position(head)
                    } else {
                        Circle().fill(headColor).frame(width: lineWidth * 3.2, height: lineWidth * 3.2)
                            .blur(radius: lineWidth * 1.2).opacity(0.8).blendMode(.plusLighter).position(head)
                        Circle().fill(Color.white).frame(width: lineWidth * 1.6, height: lineWidth * 1.6).position(head)
                    }
                }
                if showsScrub, !values.isEmpty, let hoverX,
                   let index = ChartScrubMath.nearestIndex(toX: hoverX, count: values.count, width: geo.size.width),
                   index < points.count {
                    let point = points[index]
                    let color = sampleColor(forIndex: index)
                    CrosshairRule(x: point.x, height: geo.size.height)
                    HighlightDot(color: color, diameter: max(7, lineWidth * 3)).position(point)
                    PositionedTooltip(
                        anchor: point,
                        container: geo.size,
                        tooltip: ChartTooltip(
                            value: valueFormat(values[index]),
                            label: indexLabel?(index) ?? String(localized: "sample \(index + 1)", bundle: .main),
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

    /// Gradient color at a sample's normalized position along the line.
    private func sampleColor(forIndex index: Int) -> Color {
        let position = values.count > 1 ? Double(index) / Double(values.count - 1) : 1.0
        return StrandPalette.sample(stops: gradient.stops, at: position)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let sampleCount = values.count
        return values.enumerated().map { offset, value in
            let x = sampleCount > 1
                ? CGFloat(offset) / CGFloat(sampleCount - 1) * size.width
                : size.width / 2
            return CGPoint(x: x, y: y(for: value, height: size.height))
        }
    }

    /// Y-coordinate for a value on the same axis as `points` — lets the reference band / mean line
    /// share the line's own vertical scale.
    private func y(for value: Double, height: CGFloat) -> CGFloat {
        let (floor, ceiling) = bounds
        let extent = Swift.max(ceiling - floor, 0.0001)
        let fraction = (value - floor) / extent
        return height - CGFloat(fraction) * height
    }

    private func linePath(_ vertices: [CGPoint]) -> Path {
        var path = Path()
        guard let start = vertices.first else { return path }
        path.move(to: start)
        vertices.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func areaPath(_ vertices: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(vertices)
        guard let start = vertices.first, let finish = vertices.last else { return path }
        path.addLine(to: CGPoint(x: finish.x, y: size.height))
        path.addLine(to: CGPoint(x: start.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
private func demoPulseTrack(samples: Int = 48) -> [Double] {
    (0..<samples).map { tick in
        let oscillation = 10 * sin(Double(tick) / 4.0)
        let noise = Double((tick * 13) % 7)
        return 58 + oscillation + noise
    }
}

#Preview("Sparkline") {
    let track = demoPulseTrack()
    return VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("64").font(StrandFont.number(34)).foregroundStyle(InstrumentoTheme.base.ink)
            Text("bpm").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            Spacer()
            Sparkline(values: track, valueFormat: { "\(Int($0.rounded())) bpm" }, indexLabel: { "\($0)s ago" })
                .frame(width: 160, height: 44)
        }
        Sparkline(values: track, gradient: StrandPalette.strainGradient)
            .frame(height: 60)
        Text("Hover a sparkline to read the sample under the cursor.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
    }
    .padding(24)
    .frame(width: 380, height: 220)
    .background(InstrumentoTheme.base.surface)
    .preferredColorScheme(.light)
}
#endif
