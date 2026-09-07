import SwiftUI

// MARK: - Strand Typography (§9.2)
//
// SF Pro (Display ≥20pt, Text <20pt), tabular/monospaced digits for every live value. Reading-text
// tokens are anchored to native text styles (`Font.system(.textStyle)`) so they scale with the user's
// Dynamic Type setting; the geometry-driven numeral tokens (`number`, `mono`, glyph sizes) stay FIXED
// on purpose — they size numerals embedded in a drawing (rings, dials, chart marks), which must not
// reflow with text size.

public enum StrandFont {

    // MARK: Reading scale (Dynamic Type)

    /// Relative to `.title`, 28pt bold at the default size.
    public static let title1 = Font.system(.title, weight: .bold)
    /// Relative to `.headline`, 17pt semibold at the default size.
    public static let headline = Font.system(.headline)
    /// Relative to `.subheadline`, 15pt at the default size.
    public static let body = Font.system(.subheadline)
    /// Relative to `.footnote`, 13pt at the default size.
    public static let subhead = Font.system(.footnote)
    /// Relative to `.caption`, 12pt at the default size.
    public static let caption = Font.system(.caption)
    /// Relative to `.caption2`, 11pt at the default size.
    public static let footnote = Font.system(.caption2)
    /// The small trailing unit next to a metric value (ms / bpm / %) — a step above `footnote` so it
    /// reads as part of the datum, not chrome. Relative to `.footnote`.
    public static let unit = Font.system(.footnote)
    /// Sparing ALL-CAPS label voice. Pair with `.tracking(overlineTracking)`, or just call
    /// `strandOverline()` which bakes both in.
    public static let overline = Font.system(.caption2, weight: .semibold)
    /// SF Mono — raw/log views, tabular by nature. Relative to `.footnote`.
    public static let mono = Font.system(.footnote, design: .monospaced)

    // MARK: Numeric variants (tabular digits, fixed size)

    /// A monospaced-digit numeral at an arbitrary size, for live values.
    public static func number(
        _ size: CGFloat, weight: Font.Weight = .semibold
    ) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    /// Monospaced-digit caption — small live values (sparklines, chips). Scales with Dynamic Type.
    public static let captionNumber = Font.system(.caption, weight: .medium).monospacedDigit()

    /// SF Mono at an arbitrary size.
    public static func mono(
        _ size: CGFloat, weight: Font.Weight = .regular
    ) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    public static let overlineTracking: CGFloat = 0.8 // applied by strandOverline()

    // MARK: SF Symbol glyph sizes (auditoría jul-2026, H1)
    //
    // Fixed steps absorbing the ad-hoc `.font(.system(size:))` glyph sizes screens used to invent —
    // chrome paired with non-scaling text, or geometry, so these never move with Dynamic Type.

    /// Semantic size for an SF Symbol glyph. Never pass a raw `CGFloat` at a call site.
    public enum GlyphSize: CGFloat {
        /// Navigation chevrons, disclosure marks (absorbs 10–14).
        case chevron = 12
        /// Icon beside body text (absorbs 14–17).
        case inline = 15
        /// A row/header's lead icon (absorbs 17–22).
        case lead = 18
        /// Empty-state glyph (absorbs 28–40).
        case empty = 34
    }

    /// An SF Symbol at a semantic size. FIXED — does not scale with Dynamic Type. `.regular` matches
    /// the native default of `.font(.system(size:))`, so migrating a bare-sized icon (the common case)
    /// doesn't change its weight unless the call site says otherwise.
    public static func glyph(_ size: GlyphSize, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight)
    }
}

// MARK: - Text helpers

public extension Text {
    /// Styles as an overline label: ALL-CAPS, semibold, tracked, tertiary ink.
    func strandOverline() -> some View {
        self
            .font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(InstrumentoTheme.base.inkSecondary)
    }
}

public extension View {
    /// Convenience: builds an overline-styled label straight from a plain string.
    static func strandOverline(_ text: String) -> some View {
        Text(text).strandOverline()
    }
}

#if DEBUG
private struct TypeSample: Identifiable {
    let id = UUID()
    let caption: String
    let font: Font
    let dim: Bool
}

#Preview("Typography") {
    let ink = InstrumentoTheme.base.ink
    let samples: [TypeSample] = [
        .init(caption: "Title1", font: StrandFont.title1, dim: false),
        .init(caption: "Headline", font: StrandFont.headline, dim: false),
        .init(caption: "Body", font: StrandFont.body, dim: false),
        .init(caption: "Subhead", font: StrandFont.subhead, dim: true),
        .init(caption: "Caption", font: StrandFont.caption, dim: true),
        .init(caption: "Footnote", font: StrandFont.footnote, dim: true),
        .init(caption: "Mono 0x1F 0x0A crc=91b2", font: StrandFont.mono, dim: true),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(samples) { sample in
                Text(sample.caption)
                    .font(sample.font)
                    .foregroundStyle(sample.dim ? InstrumentoTheme.base.inkSecondary : ink)
            }
            Text("Overline").strandOverline()
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkSecondary)
                Text("62").font(StrandFont.captionNumber).foregroundStyle(ink)
                Text("ms").font(StrandFont.unit).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 480, height: 520)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
