import SwiftUI
import Foundation
import CenitDesign

/// Marcapasos de respiración con aviso háptico.
///
/// Se elige un ritmo, se pulsa iniciar y se sigue el orbe: un reloj marca la inhalación y
/// la exhalación, con un pulso al inhalar y dos al exhalar. No hay biofeedback de HRV —
/// se retiró junto con la banda (FER-1003): respirar en solitario no tiene fuente de R-R
/// en vivo, así que lo único que se muestra es el ritmo que el propio marcapasos impone
/// (el copy tampoco promete respuesta de HRV — FER-242 / H-020).
///
/// Régimen sobrio de «Liquid Glass · El Eje»: lienzo `.entrenarHojaFondo(.neutro)`,
/// tarjetas opacas `.superficieSolida`, `LiquidColor.azul` como identidad de la respiración
/// y `LiquidGlassButton` en los CTAs. Reduce Motion congela el orbe.
struct BreathingView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Ritmos

    /// Los tres ritmos que ofrece la pantalla, con sus duraciones en segundos.
    private enum Pace: Hashable, CaseIterable {
        /// 4 s dentro / 6 s fuera.
        case relax
        /// 5.5 s parejos.
        case coherence
        /// 4 s parejos.
        case box

        var label: String {
            switch self {
            case .relax:
                String(localized: "breath.pace.relax", defaultValue: "Relax 4-6")
            case .coherence:
                String(localized: "breath.pace.coherence", defaultValue: "Coherence 5.5")
            case .box:
                String(localized: "breath.pace.box", defaultValue: "Box 4-4")
            }
        }

        var tagline: String {
            switch self {
            case .relax:
                String(localized: "breath.tag.relax",
                       defaultValue: "Long exhale · winds down")
            case .coherence:
                String(localized: "breath.tag.coherence",
                       defaultValue: "Even breathing · ~5.5/min")
            case .box:
                String(localized: "breath.tag.box",
                       defaultValue: "Square · steady focus")
            }
        }

        var inhale: Double {
            switch self {
            case .relax:     4.0
            case .coherence: 5.5
            case .box:       4.0
            }
        }

        var exhale: Double {
            switch self {
            case .relax:     6.0
            case .coherence: 5.5
            case .box:       4.0
            }
        }

        var cycle: Double { inhale + exhale }

        /// Respiraciones por minuto de este ritmo.
        var bpm: Double { 60.0 / cycle }

        func duration(of phase: Phase) -> Double {
            phase == .inhale ? inhale : exhale
        }
    }

    /// Los dos medios tiempos de una respiración.
    private enum Phase {
        case inhale, exhale

        var word: String {
            switch self {
            case .inhale: String(localized: "breath.phase.inhale", defaultValue: "Inhale…")
            case .exhale: String(localized: "breath.phase.exhale", defaultValue: "Exhale…")
            }
        }

        /// Un pulso al entrar, dos al salir.
        var cue: UInt8 { self == .inhale ? 1 : 2 }
    }

    // MARK: Estado

    @State private var pace: Pace = .coherence
    @State private var running = false

    @State private var phase: Phase = .inhale
    /// Reloj de pared del medio tiempo en curso; de aquí sale la escala del orbe.
    @State private var phaseStart: Date = .distantPast
    @State private var phaseDeadline: Date = .distantFuture

    @State private var sessionSeconds = 0
    @State private var breathCount = 0

    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Uno mueve la fase (rápido y suave), el otro cuenta los segundos de la sesión.
    /// Se detienen con la escena inactiva para no quemar 20 Hz en segundo plano.
    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    /// Los relojes sólo avanzan con la sesión viva y la escena al frente.
    private var timersActive: Bool { running && scenePhase == .active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                header
                statusRow
                if !running {
                    paceSelector
                }
                orbCard
                controlRow
                readoutRow
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Lienzo El Eje. La pantalla no dibuja su propia salida: el pop lo aporta el
        // NavigationStack ambiente (vía trainChrome), así que no hay cabecera propia.
        .entrenarHojaFondo(tono: .neutro)
        .onReceive(phaseTimer) { now in
            guard timersActive else { return }
            advanceIfDue(at: now)
        }
        .onReceive(secondTimer) { _ in
            guard timersActive else { return }
            sessionSeconds += 1
        }
        .onChange(of: pace) {
            // Cambiar de ritmo en caliente reinicia la inhalación, en silencio.
            if running { armPhase(.inhale, at: Date(), cue: false) }
        }
        .onDisappear { stop() }
        .enableInjection()
    }

    // MARK: - Encabezado

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(String(localized: "breath.title", defaultValue: "Breathe"))
                .font(LiquidType.displayL)
                .tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "breath.subtitle",
                        defaultValue: "Haptic-paced rhythm · follow the orb"))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }

    // MARK: - Fila de estado

    private var statusRow: some View {
        HStack(spacing: LiquidSpace.s250) {
            LiquidStatePill(
                running
                    ? String(localized: "breath.status.live", defaultValue: "Session live")
                    : String(localized: "breath.status.ready", defaultValue: "Ready"),
                dot: running ? LiquidStatePillMetrics.dotVivoDefault : nil)

            Spacer()

            HStack(spacing: LiquidSpace.s150) {
                Text(timeString(sessionSeconds))
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("·").foregroundStyle(LiquidColor.tinta500)
                Text("\(breathCount) " + String(localized: "breath.breaths",
                                                defaultValue: "breaths"))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        }
    }

    // MARK: - Elegir ritmo

    private var paceSelector: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(String(localized: "breath.kicker", defaultValue: "Breathe"))
                    .font(LiquidType.regla)
                    .tracking(LiquidType.reglaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(String(localized: "breath.choosePace", defaultValue: "Choose a pace"))
                    .font(LiquidType.displayS)
                    .tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            VStack(spacing: LiquidSpace.s300) {
                ForEach(Pace.allCases, id: \.self) { option in
                    paceRow(option)
                }
            }
        }
    }

    private func paceRow(_ option: Pace) -> some View {
        let chosen = option == pace
        let shape = RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
        return Button {
            pace = option
        } label: {
            HStack(alignment: .center, spacing: LiquidSpace.s300) {
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(verbatim: option.label)
                        .font(LiquidType.tituloGemela)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text(verbatim: option.tagline)
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta700)
                }
                Spacer(minLength: 0)
                Text(bpmString(option.bpm))
                    .font(LiquidType.caption)
                    .foregroundStyle(chosen ? LiquidColor.azul : LiquidColor.tinta700)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? LiquidColor.tonoCampo(LiquidColor.azul)
                               : LiquidColor.papelTarjeta,
                        in: shape)
            .overlay(
                shape.strokeBorder(
                    chosen
                        ? LiquidColor.azul.opacity(0.32)  // token-exempt(optico): borde de selección (preview)
                        : LiquidColor.vidrioCanto,
                    lineWidth: 1))
        }
        .buttonStyle(.liquidPress)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    // MARK: - El orbe

    private var orbCard: some View {
        VStack(spacing: LiquidSpace.s550) {
            HStack {
                Text(verbatim: pace.label)
                    .font(LiquidType.regla)
                    .tracking(LiquidType.reglaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer()
                Text(bpmString(pace.bpm))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta700)
            }

            breathingOrb
                .frame(height: 300)
                .frame(maxWidth: .infinity)

            Text(verbatim: running ? phase.word : pace.tagline)
                .font(LiquidType.cuerpo)
                .foregroundStyle(running ? LiquidColor.tinta900 : LiquidColor.tinta700)
                .strandAnimation(LiquidMotion.ambient(LiquidMotion.soft), value: phase.word)
                .strandAnimation(LiquidMotion.ambient(LiquidMotion.soft), value: running)
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous))
        .liquidGlass(.superficieSolida)
    }

    /// Sólo el orbe se re-evalúa por cuadro: el `TimelineView` acota el redibujo para que
    /// el resto de la pantalla no pague la animación (FER-876). Se pausa cuando la sesión
    /// no corre O cuando Reduce Motion está activo — congelado en reposo, nunca animado
    /// (mismo patrón que `OrbeVivo`). Oculto a VoiceOver: la palabra de fase ya dice
    /// en qué medio tiempo va, así que el orbe es movimiento redundante, no información.
    private var breathingOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running || reduceMotion)) { timeline in
            orbBody(progress: (running && !reduceMotion) ? easedProgress(at: timeline.date) : 0)
        }
        .accessibilityHidden(true)
    }

    /// Avance suavizado (cúbico, easeInOut — el mismo tacto que `easeInOut` de SwiftUI)
    /// del medio tiempo en curso: la inhalación va de 0 a 1 y la exhalación de 1 a 0.
    private func easedProgress(at date: Date) -> CGFloat {
        guard running else { return 0 }
        let t = max(0, min(1, date.timeIntervalSince(phaseStart) / pace.duration(of: phase)))
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        return CGFloat(phase == .inhale ? eased : 1 - eased)
    }

    private func orbBody(progress: CGFloat) -> some View {
        GeometryReader { geo in
            // El orbe respira entre un mínimo calmo y el cuadrado disponible.
            let span = min(geo.size.width, geo.size.height)
            let floorScale: CGFloat = 0.42
            let diameter = span * (floorScale + (1 - floorScale) * progress)
            let azul = LiquidColor.azul

            ZStack {
                // Aro guía fijo, en el tope de la inhalación.
                Circle()
                    .strokeBorder(LiquidColor.tinta900.opacity(0.14), lineWidth: 1)  // token-exempt(optico): aro guía
                    .frame(width: span, height: span)

                // Halo exterior — resplandor suave en el azul de la respiración.
                LiquidGlowDisco(
                    color: azul,  // token-exempt(dato): rampa decorativa (halo)
                    diametro: diameter * 1.35,
                    blur: LiquidSpace.s550,
                    opacidadCentro: 0.18)

                // Cuerpo del orbe — azul de identidad, no el cian de HRV.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [azul.opacity(0.32),  // token-exempt(dato): rampa decorativa (orbe)
                                     azul.opacity(0.14)],  // token-exempt(dato): rampa decorativa (orbe)
                            center: .init(x: 0.4, y: 0.35),
                            startRadius: LiquidSpace.s050,
                            endRadius: diameter * 0.62))
                    .overlay(
                        Circle().strokeBorder(azul.opacity(0.45), lineWidth: 1)  // token-exempt(optico): anillo decorativo (orbe)
                    )
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Controles

    private var controlRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            if running {
                LiquidGlassButton(
                    String(localized: "breath.stop", defaultValue: "End session"),
                    variant: .glass,
                    expands: true
                ) { stop() }
            } else {
                LiquidGlassButton(
                    String(localized: "breath.start", defaultValue: "Start · 3 min"),
                    variant: .primary,
                    expands: true
                ) { start() }
                LiquidGlassButton(
                    String(localized: "breath.testBuzz", defaultValue: "Test buzz"),
                    variant: .glass
                ) { model.buzz(loops: 1) }
            }
        }
    }

    // MARK: - Lectura

    // FER-1003: la lectura de HRV/RMSSD en vivo y la tarjeta de coherencia se retiraron con la
    // banda — respirar en solitario no tiene fuente de R-R (el espejo del reloj es sólo fuerza),
    // así que ambas vivían clavadas en «—» / «Sin datos». Queda el ritmo, que sí sale del pacer.
    private var readoutRow: some View {
        readoutTile(
            label: String(localized: "breath.readout.pace", defaultValue: "Pace"),
            value: String(format: "%.1f", pace.bpm),
            unit: String(localized: "breath.readout.unit", defaultValue: "br/min"),
            caption: String(format: "%.0f / %.0fs", pace.inhale, pace.exhale))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readoutTile(label: String, value: String, unit: String,
                             caption: String) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(verbatim: label)
                .font(LiquidType.regla)
                .tracking(LiquidType.reglaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: LiquidSpace.s150)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text(value)
                    .font(LiquidType.valorTileM)
                    .tracking(LiquidType.valorTileTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(verbatim: unit)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Text(verbatim: caption)
                .font(LiquidType.unidad)
                .foregroundStyle(LiquidColor.tinta500)
                .lineLimit(1)
                .padding(.top, LiquidSpace.s100)
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: LiquidControl.tileAltura)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous))
        .liquidGlass(.superficieSolida)
    }

    // MARK: - Sesión

    private func start() {
        running = true
        sessionSeconds = 0
        breathCount = 0
        armPhase(.inhale, at: Date(), cue: true)
    }

    private func stop() {
        running = false
        phaseDeadline = .distantFuture
        // El orbe cae a reposo (progreso 0) y se pausa: `breathingOrb` mira `running`.
    }

    /// Abre un medio tiempo: fija el objetivo, agenda su fin y, si toca, avisa al cuerpo.
    private func armPhase(_ next: Phase, at now: Date, cue: Bool) {
        phase = next
        phaseStart = now
        phaseDeadline = now.addingTimeInterval(pace.duration(of: next))
        if cue { model.buzz(loops: next.cue) }
    }

    /// Lo llama el reloj rápido: al vencer el medio tiempo, voltea al siguiente.
    private func advanceIfDue(at now: Date) {
        guard now >= phaseDeadline else { return }
        if phase == .exhale { breathCount += 1 }
        armPhase(phase == .inhale ? .exhale : .inhale, at: now, cue: true)
    }

    // MARK: - Formato

    private func timeString(_ total: Int) -> String {
        String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func bpmString(_ bpm: Double) -> String {
        String(format: "%.1f ", bpm)
            + String(localized: "breath.bpm.unit", defaultValue: "br/min")
    }
}

#if DEBUG
#Preview("Breathe · El Eje") {
    BreathingView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 900)
}

#Preview("Breathe · xxxLarge (AX5)") {
    BreathingView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 1100)
        .dynamicTypeSize(.accessibility5)
}
#endif
