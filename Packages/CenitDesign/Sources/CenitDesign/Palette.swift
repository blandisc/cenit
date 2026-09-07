import SwiftUI

// MARK: - Hex color parsing

public extension Color {
    /// Builds a color from a hex string such as `"#0B0D12"` (6-digit RGB) or `"AA0B0D12"` (8-digit
    /// RGBA). Anything outside `[0-9A-Fa-f]` (a leading `#`, stray spaces, …) is stripped first.
    init(
        hex: String
    ) {
        let digits = hex.trimmingCharacters(in: .alphanumerics.inverted)
        let packed = UInt64(digits, radix: 16) ?? 0
        func byte(shiftedBy shift: Int) -> Double { Double((packed >> shift) & 0xFF) / 255.0 }

        if digits.count == 8 {
            self.init(.sRGB, red: byte(shiftedBy: 24), green: byte(shiftedBy: 16),
                      blue: byte(shiftedBy: 8), opacity: byte(shiftedBy: 0))
        } else {
            // 6-digit RGB is the documented case; any other length falls back to the same reading
            // rather than crashing on a malformed literal.
            self.init(.sRGB, red: byte(shiftedBy: 16), green: byte(shiftedBy: 8),
                      blue: byte(shiftedBy: 0), opacity: 1.0)
        }
    }
}

// MARK: - Strand Palette — the data scales (§9.1)
//
// Every semantic color token the app paints a metric with: the recovery/strain gradients, sleep
// stages, HR zones, status words, and the shared accent. Hex values are exact per the design spec —
// never approximate them. The dark-system surface/text/hairline tokens this enum used to also carry
// were retired once «Instrumento diurno» became the only surface/text language (Instrumento.swift owns
// that now).

public enum StrandPalette {

    // MARK: Accent (chrome, not data)

    public static let accent = Color(hex: "#18C98B")
    /// Shared dimming for a disabled/inactive section, so screens don't invent their own value.
    public static let disabledOpacity: Double = 0.45 // == CenitOpacity.dim, kept for older call sites

    // MARK: Recovery gradient — red (depleted) rising through gold to mint (peak)

    public static let recovery000 = Color(hex: "#FF4F73") // depleted
    public static let recovery030 = Color(hex: "#F5A623") // low
    public static let recovery055 = Color(hex: "#E8C24B") // moderate
    public static let recovery078 = Color(hex: "#18C98B") // primed
    public static let recovery100 = Color(hex: "#2FE6A8") // peak

    public static let recoveryStops: [Gradient.Stop] = zip(
        [recovery000, recovery030, recovery055, recovery078, recovery100],
        [0.00, 0.30, 0.55, 0.78, 1.00]
    ).map { Gradient.Stop(color: $0, location: $1) }
    public static let recoveryGradient = Gradient(stops: recoveryStops) // recovery-tinted views sample this

    // MARK: Strain ramp — ember rising through orange/rose to magenta

    public static let strain000 = Color(hex: "#E8B04B") // ramp floor, warm amber
    public static let strain033 = Color(hex: "#E8743B") // second stop, burnt orange
    public static let strain066 = Color(hex: "#E0476B") // third stop, deep rose
    public static let strain100 = Color(hex: "#C13AC1") // ramp ceiling, magenta

    public static let strainStops: [Gradient.Stop] = zip(
        [strain000, strain033, strain066, strain100],
        [0.00, 0.33, 0.66, 1.00]
    ).map { Gradient.Stop(color: $0, location: $1) }
    public static let strainGradient = Gradient(stops: strainStops) // strain-tinted views sample this

    // MARK: Sleep stages

    public static let sleepAwake = Color(hex: "#E0476B") // awake segments of the night
    public static let sleepLight = Color(hex: "#5C6FB1") // light-sleep segments
    public static let sleepDeep  = Color(hex: "#2C3A7A") // deep-sleep segments
    public static let sleepREM   = Color(hex: "#3E9E8C") // REM segments

    // MARK: HR zones

    public static let zone1 = Color(hex: "#4FA9C9") // easy
    public static let zone2 = Color(hex: "#5BD3A0") // fat-burn
    public static let zone3 = Color(hex: "#E8C24B") // aerobic
    public static let zone4 = Color(hex: "#E8743B") // threshold
    public static let zone5 = Color(hex: "#E0476B") // max effort

    public static let hrZones: [Color] = [zone1, zone1, zone2, zone3, zone4, zone5] // 1-indexed, [0] mirrors [1]

    // MARK: Status — never reused as a recovery color

    public static let statusPositive = Color(hex: "#18C98B") // "all good" verdict
    public static let statusWarning  = Color(hex: "#F5A623") // "pay attention" verdict
    public static let statusCritical = Color(hex: "#FF4F73") // "something's wrong" verdict

    // MARK: Per-metric accents

    public static let metricCyan   = Color(hex: "#2FC7FF") // identifies Apple Health bar charts
    public static let metricPurple = Color(hex: "#A879FF") // identifies HRV / strain-shaped data
    public static let metricAmber  = Color(hex: "#F5A623") // identifies calorie / moderate-load data
    public static let metricRose   = Color(hex: "#FF4F73") // identifies risk / high-strain / low-recovery data

    // MARK: - Sampling

    /// Samples the recovery gradient at a score 0...100.
    static func recoveryColor(_ score: Double) -> Color { sample(stops: recoveryStops, at: score / 100.0) }

    /// Samples the strain gradient at a strain value on the 0...21 scale.
    static func strainColor(_ strain: Double) -> Color { sample(stops: strainStops, at: strain / 21.0) }

    /// The state word for a recovery score. Localized against the host app's own catalog — the
    /// package ships no strings of its own.
    static func recoveryState(_ reading: Double) -> String {
        let key: String.LocalizationValue
        switch reading {
        case ..<25: key = "DEPLETED"
        case ..<50: key = "LOW"
        case ..<70: key = "MODERATE"
        case ..<88: key = "PRIMED"
        default:    key = "PEAK"
        }
        return String(localized: key, bundle: .main)
    }

    /// Color for an HR-zone index (1...5, clamped).
    static func hrZoneColor(_ zone: Int) -> Color { hrZones[Swift.min(Swift.max(zone, 1), 5)] }

    /// Color for a sleep stage.
    static func sleepStageColor(_ kind: SleepStage) -> Color {
        switch kind {
        case .awake: sleepAwake
        case .light: sleepLight
        case .deep:  sleepDeep
        case .rem:   sleepREM
        }
    }

    // MARK: - Gradient-stop interpolation

    /// Interpolates a set of ordered gradient stops at a normalized position, clamping out-of-range
    /// positions to the end stops instead of extrapolating.
    public static func sample(
        stops: [Gradient.Stop],
        at position: Double
    ) -> Color {
        guard stops.count > 1 else { return stops.first?.color ?? .clear }
        let t = position.clamped(to: 0...1)

        let bracket = zip(stops, stops.dropFirst()).first { pair in
            t >= pair.0.location && t <= pair.1.location
        }
        let (lower, upper) = bracket ?? (stops[0], stops[stops.count - 1])
        let interval = upper.location - lower.location
        return interpolate(lower.color, upper.color, interval > 0 ? (t - lower.location) / interval : 0)
    }

    /// Linear color interpolation in sRGB space.
    static func interpolate(
        _ a: Color, _ b: Color,
        _ t: Double
    ) -> Color {
        let start = a.rgbaComponents, end = b.rgbaComponents
        let ratio = t.clamped(to: 0...1)
        func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * ratio }
        return Color(.sRGB, red: lerp(start.r, end.r), green: lerp(start.g, end.g),
                     blue: lerp(start.b, end.b), opacity: lerp(start.a, end.a))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Opacity scale (auditoría jul-2026, H4)
//
// The only sanctioned steps for modulating a color token by opacity — before this, screens invented
// ~15 magic opacities across tints/strokes/dimmed states. `dim` matches the pre-existing
// `StrandPalette.disabledOpacity` (0.45).
public enum CenitOpacity {
    public static let tintFill: Double = 0.10       // chip/badge tint fill (absorbs 0.10–0.12)
    public static let tintFillStrong: Double = 0.14 // emphasized tint (absorbs 0.14–0.18)
    public static let strokeSoft: Double = 0.30     // soft tinted stroke (absorbs 0.28–0.40)
    public static let dim: Double = 0.45            // dimmed value (absorbs 0.40–0.52)
    public static let muted: Double = 0.60          // secondary over color (absorbs 0.55–0.70)
}

// MARK: - Sleep stage (shared with the sleep-detail hipnograma)

public enum SleepStage: String, Sendable, CaseIterable {
    case awake, light, deep, rem

    /// Display label, localized against the host app's own catalog.
    public var label: String {
        let key: String.LocalizationValue
        switch self {
        case .awake: key = "Awake"
        case .light: key = "Light"
        case .deep:  key = "Deep"
        case .rem:   key = "REM"
        }
        return String(localized: key, bundle: .main)
    }
}

// MARK: - Color component extraction

extension Color {
    /// Resolves to sRGB RGBA components in 0...1, bridging through the platform color type.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(AppKit)
        return Color.sRGBComponents(of: NSColor(self))
        #elseif canImport(UIKit)
        return Color.sRGBComponents(of: UIColor(self))
        #else
        return (0, 0, 0, 1)
        #endif
    }

    /// Shared conversion so both platform branches below build the return tuple the same way.
    private static func asDoubles(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> (r: Double, g: Double, b: Double, a: Double) {
        (Double(r), Double(g), Double(b), Double(a))
    }

    #if canImport(AppKit)
    private static func sRGBComponents(of platformColor: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        let resolved = platformColor.usingColorSpace(.sRGB) ?? platformColor
        var r = CGFloat.zero, g = CGFloat.zero, b = CGFloat.zero, a = CGFloat.zero
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return asDoubles(r, g, b, a)
    }
    #elseif canImport(UIKit)
    private static func sRGBComponents(of platformColor: UIColor) -> (r: Double, g: Double, b: Double, a: Double) {
        var r = CGFloat.zero, g = CGFloat.zero, b = CGFloat.zero, a = CGFloat.zero
        platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return asDoubles(r, g, b, a)
    }
    #endif
}

#if DEBUG
private struct PaletteSwatch: View {
    let caption: String
    let tint: Color
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8).fill(tint).frame(width: 56, height: 44)
            Text(caption).font(.system(size: 9)).foregroundStyle(InstrumentoTheme.base.inkSecondary)
        }
    }
}

private struct PaletteRamp: View {
    let stops: Gradient
    var body: some View {
        Rectangle()
            .fill(LinearGradient(gradient: stops, startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(height: 32)
    }
}

#Preview("Palette") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            PaletteRamp(stops: StrandPalette.recoveryGradient)
            PaletteRamp(stops: StrandPalette.strainGradient)
            HStack(spacing: 10) {
                PaletteSwatch(caption: "awake", tint: StrandPalette.sleepAwake)
                PaletteSwatch(caption: "light", tint: StrandPalette.sleepLight)
                PaletteSwatch(caption: "deep", tint: StrandPalette.sleepDeep)
                PaletteSwatch(caption: "rem", tint: StrandPalette.sleepREM)
            }
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { zoneNumber in
                    PaletteSwatch(caption: "Z\(zoneNumber)", tint: StrandPalette.hrZoneColor(zoneNumber))
                }
            }
        }
        .padding(24)
    }
    .frame(width: 460, height: 340)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
