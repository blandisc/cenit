import SwiftUI
// MARK: - Medidas compartidas
//
// Las cuatro medidas que más de una pieza necesita citar por nombre. Todo lo que solo usa un
// archivo se queda en ese archivo; esto es el mostrador común, no un cajón de sastre.
public enum CenitMetrics { // radios y respiraciones que cruzan archivos
    /// Radio de una tarjeta/pozo (`ChartWell`, el pozo de Instrumento).
    public static let cardRadius: CGFloat = 16
    /// Radio de la barra de acción en tinta (`CenitCTAButton`).
    public static let ctaRadius: CGFloat = 14
    /// Franja limpia que la escala Y reserva bajo el relleno de una gráfica, para que las etiquetas
    /// del eje X no queden detrás del relleno y se tiñan con él.
    public static let chartXLabelBand: CGFloat = 24
    /// Respiro al final de la escala X para que la última fecha se dibuje entera en vez de cortarse.
    public static let chartXTrailingInset: CGFloat = 38
}

// MARK: - Live Activity metrics ("Descanso" / rest-timer session)
//
// Geometry for `CenitWidgets/RestLiveActivity.swift`. Lives in the package (not a local enum in the
// widget extension) so the design-drift linter sees it as part of the system. Sizes are FIXED on
// purpose — Dynamic Island / Lock Screen geometry, exempt from Dynamic Type; a Live Activity is tighter
// than a screen and ActivityKit caps the Lock Screen at 160pt with no scroll.
//
// Height budget: the stacked zones + paddings must sum to ≤ 160pt or the actions row silently clips —
// 2·12 pad + 34 identity + 8 + 34 hero + 8 + 4 bar + 8 + 44 actions = 156pt. Re-check that sum before
// changing any value here.
public enum WidgetMetrics {
    public static let cardPadding: CGFloat = 12
    public static let hero: CGFloat = 28
    public static let heroSlot: CGFloat = 34
    public static let pulse: CGFloat = 17
    public static let name: CGFloat = 15
    public static let overline: CGFloat = 11
    public static let overlineTracking: CGFloat = 1.4
    public static let returnValue: CGFloat = 15
    public static let thumb: CGFloat = 34
    public static let control: CGFloat = 44
    public static let glyph: CGFloat = 19
    public static let pillLabel: CGFloat = 13
    public static let bar: CGFloat = 4
    public static let segmentGap: CGFloat = 3
    public static let headerGap: CGFloat = 10
    public static let heroTopGap: CGFloat = 8
    public static let barTopGap: CGFloat = 8
    public static let actionsTopGap: CGFloat = 8
    public static let pillGap: CGFloat = 8
    /// The one corner radius for any rectangular control-slab on the card.
    public static let controlRadius: CGFloat = 13
    public static let captionGap: CGFloat = 3
    public static let microGap: CGFloat = 2
    public static let pulseIconGap: CGFloat = 6
    /// Caps `Text(timerInterval:)`'s greedy width to roughly "10:00" — the worst case for a rest of up
    /// to 99:59 on tabular digits.
    public static let timerWidthMultiplier: CGFloat = 3
    public static let disabledOpacity: CGFloat = 0.4
    public static let thumbInitials: CGFloat = 13

    // Dynamic Island — ActivityKit's own fixed sizes, not `LiquidType`.
    public static let islandCompact: CGFloat = 13
    public static let islandCompactGlyph: CGFloat = 12
    public static let islandCompactHeart: CGFloat = 10
    public static let islandCompactTimer: CGFloat = 15
    public static let islandMinimal: CGFloat = 12
    public static let islandMinimalGlyph: CGFloat = 11
    public static let islandExpandedHero: CGFloat = 26
    public static let islandExpandedSecondary: CGFloat = 16
    public static let islandExpandedPause: CGFloat = 20
    public static let islandExpandedTarget: CGFloat = 15
    public static let islandExpandedHeart: CGFloat = 14
    public static let islandExpandedTimerGlyph: CGFloat = 13
    public static let islandExpandedPulse: CGFloat = 16
    public static let islandExpandedPulseGlyph: CGFloat = 13
    public static let islandCapLabel: CGFloat = 9
    public static let islandCapTimer: CGFloat = 14
    public static let islandBottomCaption: CGFloat = 12
}

// MARK: - Home-screen widget metrics
//
// `TrainTodayWidget` (.systemSmall) and `WeekWidget` (.systemMedium) — WidgetKit's own fixed canvases,
// deliberately NOT reflowing with Dynamic Type.
public enum HomeWidgetMetrics {
    public static let padding: CGFloat = 16
    public static let overline: CGFloat = 11
    public static let overlineTracking: CGFloat = 1.2
    public static let title: CGFloat = 20
    public static let cta: CGFloat = 13
    public static let verdict: CGFloat = 13
    public static let dayToken: CGFloat = 20
    public static let dayLabel: CGFloat = 10
    public static let rowGap: CGFloat = 6
    public static let weekGap: CGFloat = 10
    public static let microGap: CGFloat = 2
    public static let dayTokenGap: CGFloat = 4
    public static let ringToday: CGFloat = 2
    public static let ringUpcoming: CGFloat = 1.5
    public static let ringRest: CGFloat = 1
    public static let ringRestDash: [CGFloat] = [2, 3]
}

// MARK: - Watch geometry
//
// Names what the design audit found on the Watch companion screens — it does NOT unify the four
// different button heights below (that would be a real layout change past a geometry-naming pass).
public enum WatchMetrics {
    public static let ctaHeight: CGFloat = 38
    public static let pillHeight: CGFloat = 30
    public static let controlHeight: CGFloat = 40
    public static let summarySecondaryHeight: CGFloat = 40
    public static let summaryPrimaryHeight: CGFloat = 44

    public static let heroPulse: CGFloat = 52
    public static let heroRestCountdown: CGFloat = 44
    public static let heroReadiness: CGFloat = 36
    public static let heroSummaryDuration: CGFloat = 40
}

// MARK: - El único control segmentado
//
// Una ranura de vidrio con un botón por opción y un pulgar que viaja a la seleccionada. Es la única
// pieza del sistema para «elige uno de estos pocos»; nadie dibuja su propio segmentado a mano.
public struct SegmentedPillControl<T: Hashable>: View { // ranura + pulgar; una sola opción activa
    let items: [T], label: (T) -> String
    @Binding private var selection: T
    var inkThumb = false
    var tall: Bool = false
    var squared: Bool = false
    var thumbTint: Color? = nil
    var icon: (T) -> String? = { _ in nil }

    /// - Parameter theme: accepted for call-site compatibility, ignored for painting (LiquidColor owns
    ///   the surface now).
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme = .base,
                inkThumb: Bool = false, tall: Bool = false, squared: Bool = false,
                thumbTint: Color? = nil, icon: @escaping (T) -> String? = { _ in nil },
                label: @escaping (T) -> String) {
        self.items = items
        self._selection = selection
        _ = theme
        self.inkThumb = inkThumb
        self.tall = tall
        self.squared = squared
        self.thumbTint = thumbTint
        self.icon = icon
        self.label = label
    }

    public var body: some View { ranura }

    /// La ranura completa: un botón por opción, sobre el vidrio de pastilla sólida.
    private var ranura: some View {
        HStack(spacing: squared ? 3 : 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                boton(para: item)
            }
        }
        .padding(3)
        .liquidGlass(.pastillaSolida)
    }

    /// Un botón de la ranura. La selección viaja con el resorte de manipulación directa, y VoiceOver
    /// escucha el rasgo `.isSelected` solo en el activo.
    private func boton(para item: T) -> some View {
        let activo = item == selection
        return Button(action: { withAnimation(CenitMotion.interactive) { selection = item } },
                      label: { segment(item, activo) })
            .buttonStyle(InstrumentoPressStyle())
            .accessibilityAddTraits(activo ? [.isSelected] : [])
    }

    /// One segment: the active thumb hugs the label width but fills the track height, so it never
    /// floats small inside a taller groove.
    @ViewBuilder
    private func segment(_ item: T, _ isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            if let symbol = icon(item) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            Text(label(item))
                .font(InstrumentoType.grotesk(12, weight: isSelected ? .bold : .medium))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isSelected ? LiquidColor.papelTarjeta : LiquidColor.tinta500)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 44 : 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(thumbTint ?? LiquidColor.tinta900)
            }
        }
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("SegmentedPillControl") {
    struct Demo: View {
        @State private var choice = "Semana"
        var body: some View {
            SegmentedPillControl(["Semana", "Mes", "Año"], selection: $choice) { $0 }
                .padding(24)
        }
    }
    return Demo().background(LiquidColor.fondoAlto)
}
#endif
