import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Chart scrub toolkit (shared across every chart in the package)
//
// On iOS there's no pointer hover, so a chart's "explore the data" affordance is a finger-drag that
// snaps to the nearest datum. This file is the one place that snapping math, the tooltip card, its
// placement, the crosshair rule and the highlighted dot live, so every chart (TrendChart, Sparkline,
// YearHeatStrip, and the LiquidGlass chart family) reads identically instead of reinventing its own.
// On macOS the same crosshair/tooltip is driven by pointer hover instead of drag.

// MARK: - Selection haptic

/// A light selection tick fired when the scrubbed finger snaps onto a NEW datum (iOS only — a no-op on
/// macOS/watchOS). One generator is prepared once and reused, per Apple's HIG guidance.
public enum ChartHaptics {
    #if canImport(UIKit) && os(iOS)
    @MainActor private static let generator = UISelectionFeedbackGenerator()
    #endif

    /// Call for a move onto a new (non-nil) datum — never for the finger lifting.
    @MainActor public static func datumChanged() {
        #if canImport(UIKit) && os(iOS)
        generator.selectionChanged()
        generator.prepare()
        #endif
    }
}

// MARK: - Tooltip card

/// A compact dark read-out shown near the scrubbed datum: a bold value line plus an optional secondary
/// label, and an optional leading accent dot naming the color the tooltip is explaining.
struct ChartTooltip: View {
    var value: String
    var label: String?
    var accent: Color?

    init(
        value: String,
        label: String? = nil,
        accent: Color? = nil
    ) {
        self.value = value
        self.label = label
        self.accent = accent
    }

    @Environment(\.instrumentoFlat) private var flat

    private var voiceOverText: String {
        guard let label else { return value }
        return "\(value), \(label)"
    }

    var body: some View {
        let card = HStack(alignment: .center, spacing: 8) {
            if let accent {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: flat ? .clear : accent.opacity(0.8), radius: flat ? 0 : 3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(StrandFont.captionNumber)
                    .fontWeight(.semibold)
                    .foregroundStyle(LiquidColor.tinta900)
                if let label {
                    Text(label)
                        .font(StrandFont.footnote)
                        .foregroundStyle(LiquidColor.tinta700)
                }
            }
        }
        return card
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LiquidColor.papelTarjeta))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(LiquidColor.tinta10, lineWidth: 1))
            .shadow(color: Color.black.opacity(flat ? 0.14 : 0.45), radius: flat ? 4 : 10, x: 0, y: flat ? 2 : 6)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverText)
    }
}

// MARK: - Tooltip placement

/// Positions a tooltip near an anchor point while keeping it fully inside a container.
enum ChartTooltipPlacement {

    /// Prefers sitting above-and-centred on the anchor, flipping below when the top edge would clip;
    /// always clamped fully inside `container`.
    static func position(
        anchor: CGPoint, tooltipSize size: CGSize, in container: CGSize, gap: CGFloat = 12
    ) -> CGPoint {
        let halfWidth = size.width / 2, halfHeight = size.height / 2

        var top = anchor.y - gap - halfHeight
        if top - halfHeight < 0 { top = anchor.y + gap + halfHeight }
        let clampedY = top.pinned(between: halfHeight, and: max(halfHeight, container.height - halfHeight))
        let clampedX = anchor.x.pinned(between: halfWidth, and: max(halfWidth, container.width - halfWidth))
        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Same contract as `position`, but pushed to ONE SIDE of the anchor so it never sits on top of the
    /// datum it names — centring on the anchor can otherwise cover the very point being explained.
    /// Prefers whichever side has more room, flips when that side doesn't fit, and falls back to
    /// `position` only when NEITHER side fits (a plot narrower than the tooltip itself).
    static func positionBeside(
        anchor: CGPoint, tooltipSize size: CGSize, in container: CGSize, gap: CGFloat = 12
    ) -> CGPoint {
        let halfWidth = size.width / 2, halfHeight = size.height / 2

        let candidateRight = anchor.x + gap + halfWidth
        let candidateLeft = anchor.x - gap - halfWidth
        let rightFits = candidateRight + halfWidth <= container.width
        let leftFits = candidateLeft - halfWidth >= 0
        guard rightFits || leftFits else {
            return position(anchor: anchor, tooltipSize: size, in: container, gap: gap)
        }

        let rightHasMoreAir = (container.width - anchor.x) >= anchor.x
        let resolvedX: CGFloat = (rightHasMoreAir && rightFits) || !leftFits ? candidateRight : candidateLeft

        var top = anchor.y - gap - halfHeight
        if top - halfHeight < 0 { top = anchor.y + gap + halfHeight }
        let resolvedY = top.pinned(between: halfHeight, and: max(halfHeight, container.height - halfHeight))

        return CGPoint(x: resolvedX, y: resolvedY)
    }
}

private extension CGFloat {
    func pinned(between lowerBound: CGFloat, and upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lowerBound), upperBound)
    }
}

// MARK: - Nearest-datum lookup

/// Geometry helpers mapping a scrub location to the nearest datum index.
enum ChartScrubMath {

    /// Nearest index among `count` samples evenly spaced across `width`. Clamps out-of-range x to the
    /// end samples; a single sample always resolves to 0.
    static func nearestIndex(toX x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1, width > 0 else { return 0 }
        let samplePitch = width / CGFloat(count - 1)
        let estimatedIndex = Int((x / samplePitch).rounded())
        return Swift.min(Swift.max(estimatedIndex, 0), count - 1)
    }

    /// Nearest index among arbitrary x-positions.
    static func nearestIndex(toX x: CGFloat, xs positions: [CGFloat]) -> Int? {
        guard !positions.isEmpty else { return nil }
        return positions.indices.min { lhs, rhs in
            abs(positions[lhs] - x) < abs(positions[rhs] - x)
        }
    }
}

// MARK: - Crosshair

/// A dashed vertical rule marking the scrubbed x — shared by every chart so the affordance reads
/// identically everywhere.
struct CrosshairRule: View {
    var x: CGFloat
    var height: CGFloat
    var color: Color = LiquidColor.tinta10

    init(
        x: CGFloat, height: CGFloat,
        color: Color = LiquidColor.tinta10
    ) {
        self.x = x
        self.height = height
        self.color = color
    }

    var body: some View {
        let verticalLine = Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        return verticalLine
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .allowsHitTesting(false)
    }
}

// MARK: - Highlighted datum

/// The dot marking the scrubbed sample on a line. Blooms in the dark system; on warm paper
/// (`\.instrumentoFlat`) it reads as an enlarged flat handle instead (no glow).
struct HighlightDot: View {
    var color: Color
    var diameter: CGFloat = 9

    @Environment(\.instrumentoFlat) private var flat

    init(
        color: Color,
        diameter: CGFloat = 9
    ) {
        self.color = color
        self.diameter = diameter
    }

    @ViewBuilder private var flatHandle: some View {
        let handleSize = Swift.max(diameter + 4, 13)
        ZStack {
            Circle().fill(LiquidColor.fondoAlto).frame(width: handleSize, height: handleSize)
            Circle().strokeBorder(color, lineWidth: 2.5).frame(width: handleSize, height: handleSize)
        }
    }

    @ViewBuilder private var bloomingDot: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: diameter * 1.8, height: diameter * 1.8)
                .blur(radius: diameter * 0.6)
                .opacity(0.7)
                .blendMode(.plusLighter)
            Circle().fill(LiquidColor.fondoAlto).frame(width: diameter, height: diameter)
            Circle().fill(color).frame(width: diameter - 3, height: diameter - 3)
        }
    }

    var body: some View {
        Group {
            if flat { flatHandle } else { bloomingDot }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tooltip overlay

/// Wraps a `ChartTooltip`, measures its own size, and positions itself near an anchor within a
/// container — so `ChartTooltipPlacement` always works off the tooltip's REAL size, not a guess.
struct PositionedTooltip: View {
    var anchor: CGPoint
    var container: CGSize
    var tooltip: ChartTooltip

    @State private var measuredSize: CGSize = .zero

    /// Placeholder size assumed before the first layout pass measures the real one.
    private static let unmeasuredGuess = CGSize(width: 90, height: 40)

    init(
        anchor: CGPoint,
        container: CGSize,
        tooltip: ChartTooltip
    ) {
        self.anchor = anchor
        self.container = container
        self.tooltip = tooltip
    }

    private var resolvedPosition: CGPoint {
        ChartTooltipPlacement.position(
            anchor: anchor,
            tooltipSize: measuredSize == .zero ? Self.unmeasuredGuess : measuredSize,
            in: container
        )
    }

    var body: some View {
        tooltip
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in measuredSize = newSize }
                }
            }
            .position(resolvedPosition)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

#if DEBUG
private struct ChartTooltipSample: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let accent: Color?
}

#Preview("ChartTooltip") {
    let rows: [ChartTooltipSample] = [
        .init(value: "Recovery 88", label: "Tue 3 Jun", accent: StrandPalette.recoveryColor(88)),
        .init(value: "62 ms", label: "HRV · sample 14", accent: nil),
        .init(value: "18.7", label: "STRAIN · all-out", accent: StrandPalette.strainColor(18.7)),
    ]
    return VStack(spacing: 24) {
        ForEach(rows) { row in
            ChartTooltip(value: row.value, label: row.label, accent: row.accent)
        }
    }
    .padding(40)
    .frame(width: 320, height: 240)
    .background(LiquidColor.fondoAlto)
    .preferredColorScheme(.light)
}
#endif
