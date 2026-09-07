import SwiftUI

// MARK: - Strand Motion (§9.6)
//
// Physiological motion — breathe / pulse / flow, never a cartoon bounce. `LiquidMotion` is the live
// motion language; the three spring presets here are deprecated aliases of its equivalents (same
// values), kept only so existing call sites keep compiling while they migrate. `breathe` has no Liquid
// twin yet and stays live for loading/listening states.

public enum StrandMotion {

    // MARK: Spring presets

    /// Snappy, for direct manipulation (hover, press, sidebar slide).
    @available(*, deprecated, message: "use LiquidMotion.toque (same value)")
    public static let interactive = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.1)

    /// The house spring for value changes (ring draw-in, gauges).
    @available(*, deprecated, message: "use LiquidMotion.suave (same value)")
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Slower, more deliberate — hero transitions (first ring materialize).
    @available(*, deprecated, message: "use LiquidMotion.heroe (same value)")
    public static let hero = Animation.spring(response: 0.85, dampingFraction: 0.85)

    // MARK: Durations

    /// Standard transition (card appear, fades).
    public static let durationStandard: Double = 0.30
    /// Slow / draw-in (ring arc, waveform ignite).
    public static let durationSlow: Double = 0.9
    /// One breath cycle for ambient pulsing.
    public static let breathPeriod: Double = 3.2

    // MARK: Curves

    /// Ease for a ring/gauge draw-in when its value changes.
    public static let drawIn = Animation.easeOut(duration: durationSlow)

    /// Looping breathe animation for ambient glow/pulse states.
    public static var breathe: Animation {
        .easeInOut(duration: breathPeriod).repeatForever(autoreverses: true)
    }

    /// Standard fade.
    @available(*, deprecated, message: "use LiquidMotion.fundido (same value)")
    public static let fade = Animation.easeInOut(duration: durationStandard)

    /// A receipt's numerals counting up once, on save.
    @available(*, deprecated, message: "use LiquidMotion.conteo (same value)")
    public static let countUp = Animation.easeOut(duration: 0.75)
}

// MARK: - Entrance keyframes ("Detalle de Tendencias Final")
//
// Every trend-detail screen animates its entrance with exactly three keyframes: a bar/value GROWING
// from its start point, a hero numeral RISING into place, and a chart area FADING in. All three wait
// for a presenter-controlled "settled" gate so a detail that already has its data on the first frame
// doesn't have its entrance swallowed by the presenting sheet's own slide-in.

private struct EntranceSettledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Whether the presenting screen has finished arriving. `false` holds every entrance keyframe.
    var recEntranceSettled: Bool {
        get { self[EntranceSettledKey.self] }
        set { self[EntranceSettledKey.self] = newValue }
    }
}

/// Holds the environment's entrance gate closed for `settle` seconds after being inserted.
private struct EntranceGateModifier: ViewModifier {
    let settle: Double
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .environment(\.recEntranceSettled, settled)
            .task {
                try? await Task.sleep(for: .seconds(settle))
                settled = true
            }
    }
}

/// One of the three entrance keyframes, gated on `recEntranceSettled` and played exactly once.
private struct EntranceKeyframeModifier: ViewModifier {
    enum Motion { case grow(UnitPoint), rise, fade }

    let motion: Motion
    let delay: Double
    let duration: Double
    @State private var revealed = false
    @Environment(\.recEntranceSettled) private var settled

    func body(content: Content) -> some View {
        Group {
            switch motion {
            case .grow(let anchor):
                content.scaleEffect(x: revealed ? 1 : 0, y: 1, anchor: anchor)
            case .rise:
                content.opacity(revealed ? 1 : 0).offset(y: revealed ? 0 : 4)
            case .fade:
                content.opacity(revealed ? 1 : 0)
            }
        }
        .onAppear { reveal() }
        .onChange(of: settled) { _, _ in reveal() }
    }

    /// Whichever happens last — the view mounting, or the gate settling — starts the animation. Runs
    /// only once: a second trigger after `revealed` is already true is a no-op.
    private func reveal() {
        guard settled, !revealed else { return }
        withAnimation(.easeOut(duration: duration).delay(delay)) { revealed = true }
    }
}

public extension View {
    /// A data bar/value growing from its start point: scaleX 0→1, ease-out, staggered per index.
    /// `origin` is the growth anchor (`.leading`/`.trailing`).
    func recGrow(index: Int = 0, origin: UnitPoint = .leading) -> some View {
        modifier(EntranceKeyframeModifier(motion: .grow(origin), delay: 0.15 + 0.06 * Double(index), duration: 0.35))
    }

    /// A hero numeral rising 4pt into place. The second numeral of a paired hero passes `second: true`
    /// for a small extra delay so the two don't land in the same instant.
    func recRise(second: Bool = false) -> some View {
        modifier(EntranceKeyframeModifier(motion: .rise, delay: second ? 0.05 : 0, duration: 0.3))
    }

    /// A chart area fading in after the bar/numeral keyframes have started.
    func recFade() -> some View {
        modifier(EntranceKeyframeModifier(motion: .fade, delay: 0.25, duration: 0.4))
    }

    /// Holds the three entrance keyframes closed until the presenting screen has landed. Apply this on
    /// the PRESENTER's side (the sheet/layer root), where the arrival duration is actually known.
    func recEntranceGate(_ settle: Double = StrandMotion.durationStandard) -> some View {
        modifier(EntranceGateModifier(settle: settle))
    }
}

#if DEBUG
private struct MotionPreview: View {
    @State private var on = false
    @State private var breathing = false
    var body: some View {
        VStack(spacing: 32) {
            Circle()
                .fill(StrandPalette.accent)
                .frame(width: 60, height: 60)
                .offset(y: on ? -24 : 24)
                .animation(StrandMotion.gentle, value: on)
            Circle()
                .fill(StrandPalette.recovery100)
                .frame(width: 60, height: 60)
                .scaleEffect(breathing ? 1.12 : 0.9)
                .opacity(breathing ? 0.9 : 0.5)
                .onAppear { breathing = true }
                .animation(StrandMotion.breathe, value: breathing)
            Button("Toggle gentle spring") { on.toggle() }
                .foregroundStyle(InstrumentoTheme.base.ink)
        }
        .frame(width: 360, height: 320)
        .background(InstrumentoTheme.base.paper)
        .preferredColorScheme(.light)
    }
}

#Preview("Motion") { MotionPreview() }
#endif
