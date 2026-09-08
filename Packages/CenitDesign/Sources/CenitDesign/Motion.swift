import SwiftUI
// MARK: - El ritmo del sistema
//   El movimiento de Cénit es fisiológico —respirar, latir, fluir— y nunca un rebote de caricatura.
//   `LiquidMotion` es el dialecto vivo y la fuente de los números; `CenitMotion` es el nombre viejo
//   que todavía usan las pantallas sin migrar, y aquí no vuelve a decidir nada: cada pieza reenvía a
//   su gemela de Liquid, así que un ajuste de tempo se hace en UN lugar y las dos superficies lo
//   heredan. Solo el trazado y la respiración siguen naciendo aquí: no tienen gemela todavía.

/// Los dos ritmos que este archivo aún origina, con su número a la vista.
private enum Compases {
    /// 900 ms: lo que tarda un anillo en dibujarse de cero a su valor.
    static let trazado: Double = 0.9
    /// 3.2 s: ida y vuelta completa de una respiración ambiental.
    static let respiracion: Double = 3.2
}

public enum CenitMotion {

    // MARK: Duraciones

    /// Transición estándar: aparecer una tarjeta, un fundido. Es la de Liquid, no una segunda cifra.
    public static let durationStandard = LiquidMotion.fundidoDuration
    /// Lenta, de trazado: el arco de un anillo, encender una onda.
    public static let durationSlow = Compases.trazado
    /// Un ciclo completo de respiración, para el pulso ambiental.
    public static let breathPeriod = Compases.respiracion

    // MARK: Curvas propias de este archivo

    /// Trazado de un anillo o un medidor cuando su valor cambia.
    public static let drawIn: Animation = .easeOut(duration: Compases.trazado)
    /// Respiración en bucle, para halos y estados de escucha. Es `var` y no `let` a propósito:
    /// `repeatForever` construye una animación nueva cada vez que se pide.
    public static var breathe: Animation {
        .easeInOut(duration: Compases.respiracion).repeatForever(autoreverses: true)
    }

    // MARK: Nombres viejos, valor de Liquid

    /// Manipulación directa: presionar, arrastrar, deslizar un panel. → `LiquidMotion.toque`.
    public static let interactive = LiquidMotion.toque
    /// El resorte de la casa para un cambio de valor: anillos, medidores. → `LiquidMotion.suave`.
    public static let gentle = LiquidMotion.suave
    /// Más lento y deliberado: la entrada de un héroe. → `LiquidMotion.heroe`.
    public static let hero = LiquidMotion.heroe
    /// Fundido estándar. → `LiquidMotion.fundido`.
    public static let fade = LiquidMotion.fundido
    /// Los numerales de un recibo contando una sola vez, al guardar. → `LiquidMotion.conteo`.
    public static let countUp = LiquidMotion.conteo
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
    func recEntranceGate(_ settle: Double = CenitMotion.durationStandard) -> some View {
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

    var body: some View { HStack(spacing: 18) { nombre; disco } }

    private var nombre: some View {
        Text(rotulo).font(CenitFont.caption).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            .frame(width: 132, alignment: .leading)
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

    var body: some View { filas }

    private var filas: some View {
        VStack(alignment: .leading, spacing: 22) {
            RitmoDemostrado(rotulo: "drawIn · \(CenitMotion.durationSlow)s", tinta: CenitPalette.accent,
                            ritmo: CenitMotion.drawIn, enBucle: false, disparo: disparo)
            RitmoDemostrado(rotulo: "breathe · \(CenitMotion.breathPeriod)s", tinta: CenitPalette.recovery100,
                            ritmo: CenitMotion.breathe, enBucle: true, disparo: disparo)
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
