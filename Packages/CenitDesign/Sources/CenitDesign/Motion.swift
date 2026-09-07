import SwiftUI
// MARK: - El ritmo del sistema
//
// El movimiento de Cénit es fisiológico —respirar, latir, fluir— y nunca un rebote de caricatura.
// `LiquidMotion` es el lenguaje vivo; lo que queda aquí es de dos clases:
//
//   · ALIAS DEPRECADOS de piezas de LiquidMotion, con el MISMO valor, para que los call sites que
//     todavía no migran sigan compilando (con su aviso).
//   · Las duraciones y curvas que aún no tienen gemelo en Liquid, `drawIn` y `breathe`, que siguen
//     vivas para los estados de carga y de escucha.
public enum StrandMotion {
    // MARK: Duraciones — la fuente de los números, citada por las curvas de abajo
    /// Transición estándar: aparecer una tarjeta, un fundido.
    public static let durationStandard: Double = 0.30
    /// Lenta, de trazado: el arco de un anillo, encender una onda.
    public static let durationSlow: Double = 0.9
    /// Un ciclo completo de respiración, para el pulso ambiental.
    public static let breathPeriod: Double = 3.2

    // MARK: Curvas vivas
    /// Trazado de un anillo o un medidor cuando su valor cambia.
    public static let drawIn = Animation.easeOut(duration: durationSlow)
    /// Respiración en bucle, para halos y estados de escucha. Es `var` y no `let` a propósito:
    /// `repeatForever` construye una animación nueva cada vez que se pide.
    public static var breathe: Animation { .easeInOut(duration: breathPeriod).repeatForever(autoreverses: true) }

    // MARK: Alias deprecados — mismo valor que su gemelo de Liquid
    /// Manipulación directa: presionar, arrastrar, deslizar un panel.
    @available(*, deprecated, message: "usa LiquidMotion.toque (mismo valor)")
    public static let interactive = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.1)
    /// El resorte de la casa para un cambio de valor: anillos, medidores.
    @available(*, deprecated, message: "usa LiquidMotion.suave (mismo valor)")
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Más lento y deliberado: la entrada de un héroe, el primer anillo que se materializa.
    @available(*, deprecated, message: "usa LiquidMotion.heroe (mismo valor)")
    public static let hero = Animation.spring(response: 0.85, dampingFraction: 0.85)
    /// Fundido estándar.
    @available(*, deprecated, message: "usa LiquidMotion.fundido (mismo valor)")
    public static let fade = Animation.easeInOut(duration: durationStandard)
    /// Los numerales de un recibo contando una sola vez, al guardar.
    @available(*, deprecated, message: "usa LiquidMotion.conteo (mismo valor)")
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
/// Una fila del muestrario: el nombre del ritmo y un disco que lo obedece.
private struct RitmoDemostrado: View {
    let rotulo: String
    let tinta: Color
    let ritmo: Animation
    /// `true` = el disco respira solo; `false` = se mueve cuando `disparo` cambia.
    let enBucle: Bool
    let disparo: Bool
    @State private var respirando = false

    var body: some View {
        HStack(spacing: 18) {
            Text(rotulo).font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkSecondary)
                .frame(width: 132, alignment: .leading)
            disco
        }
    }

    private var disco: some View {
        Circle().fill(tinta).frame(width: 44, height: 44)
            .scaleEffect(enBucle && respirando ? 1.12 : 0.9)
            .offset(x: enBucle ? 0 : (disparo ? 90 : 0))
            .onAppear { respirando = enBucle }
            .animation(ritmo, value: enBucle ? respirando : disparo)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MuestrarioDeRitmo: View {
    @State private var disparo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RitmoDemostrado(rotulo: "drawIn · \(StrandMotion.durationSlow)s", tinta: StrandPalette.accent,
                            ritmo: StrandMotion.drawIn, enBucle: false, disparo: disparo)
            RitmoDemostrado(rotulo: "breathe · \(StrandMotion.breathPeriod)s", tinta: StrandPalette.recovery100,
                            ritmo: StrandMotion.breathe, enBucle: true, disparo: disparo)
            Button("Disparar el trazado") { disparo.toggle() }
                .foregroundStyle(InstrumentoTheme.base.ink)
        }
        .padding(28)
        .frame(width: 420, height: 260, alignment: .leading)
        .background(InstrumentoTheme.base.paper).preferredColorScheme(.light)
    }
}

#Preview("Motion") { MuestrarioDeRitmo() }
#endif
