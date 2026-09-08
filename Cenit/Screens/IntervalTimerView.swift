import SwiftUI
import Foundation
import CenitDesign

// MARK: - La máquina, aparte de la pantalla

/// Los tres momentos de una sesión de intervalos.
private enum IntervalPhase: Equatable {
    case work, rest, done

    var label: String {
        switch self {
        case .work: String(localized: "WORK")
        case .rest: String(localized: "REST")
        case .done: String(localized: "DONE")
        }
    }

    /// Ámbar para el esfuerzo, cian para la calma, verde para el cierre.
    var hue: Color {
        switch self {
        case .work: LiquidColor.ambar
        case .rest: LiquidColor.cian
        case .done: LiquidColor.verdePrimario
        }
    }
}

/// Los cinco avisos que el teléfono da con vibración, cada uno con su número de pulsos.
///
/// Están juntos a propósito: la promesa de esta pantalla es entrenar sin mirar el teléfono, así que
/// el vocabulario háptico es la interfaz de verdad y tiene que poder leerse de un golpe.
private enum HapticCue: Equatable {
    /// Los últimos tres segundos de cualquier fase: 3… 2… 1.
    case countdown
    /// Entra el descanso: un solo pulso, para no confundirlo con el trabajo.
    case enterRest
    /// Abre un bloque de trabajo.
    case enterWork
    /// Arranca la sesión desde cero.
    case sessionStart
    /// Se acabó todo.
    case sessionEnd

    var loops: Int {
        switch self {
        case .countdown, .enterRest: 1
        case .enterWork, .sessionStart: 3
        case .sessionEnd: 5
        }
    }
}

/// Lo que la persona arma antes de empezar.
private struct IntervalPlan: Equatable {
    var work = 30
    var rest = 15
    var rounds = 8

    /// Segundos de una fase. Nunca cero: un intervalo de duración cero no avanzaría jamás.
    func seconds(of phase: IntervalPhase) -> Int {
        switch phase {
        case .work: max(1, work)
        case .rest: max(1, rest)
        case .done: 1
        }
    }

    /// Largo planeado: los bloques de trabajo más los descansos que van ENTRE ellos. El último
    /// bloque cierra la sesión, así que no hay descanso final que contar.
    var totalSeconds: Int {
        guard rounds > 0 else { return 0 }
        return work * rounds + rest * max(0, rounds - 1)
    }
}

/// Dónde va la sesión en curso.
///
/// Es un valor, no una maraña de `@State` sueltos, y por eso `advance` puede ser una transición
/// pura: **devuelve** el aviso que toca en vez de vibrar por su cuenta. Quien vibra es la vista.
private struct IntervalRun {
    var phase: IntervalPhase = .work
    var round = 1
    var remaining = 30
    var elapsed = 0
    var running = false

    /// Nadie la ha arrancado ni movido todavía.
    func isPristine(in plan: IntervalPlan) -> Bool {
        !running && phase == .work && round == 1
            && remaining == plan.seconds(of: phase) && elapsed == 0
    }

    /// Avance 0…1 dentro del intervalo en curso.
    func intervalProgress(in plan: IntervalPlan) -> Double {
        let duration = plan.seconds(of: phase)
        guard duration > 0 else { return 0 }
        return Self.clamped(Double(duration - remaining) / Double(duration))
    }

    func sessionProgress(in plan: IntervalPlan) -> Double {
        let planned = plan.totalSeconds
        guard planned > 0 else { return 0 }
        return Self.clamped(Double(elapsed) / Double(planned))
    }

    /// Vuelve al inicio de la ronda 1 con los ajustes vigentes.
    mutating func rewind(to plan: IntervalPlan) {
        phase = .work
        round = 1
        remaining = plan.seconds(of: .work)
        elapsed = 0
    }

    /// Se acabó el intervalo: pasa al siguiente y dice qué aviso corresponde.
    /// `nil` significa que ya no había a dónde ir.
    mutating func advance(in plan: IntervalPlan) -> HapticCue? {
        switch phase {
        case .work where round >= plan.rounds:
            // El último bloque de trabajo cierra la sesión: nunca hay descanso final.
            phase = .done
            remaining = 0
            running = false
            return .sessionEnd
        case .work:
            phase = .rest
            remaining = plan.seconds(of: .rest)
            return .enterRest
        case .rest:
            round += 1
            phase = .work
            remaining = plan.seconds(of: .work)
            return .enterWork
        case .done:
            return nil
        }
    }

    private static func clamped(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - La pantalla

/// Cronómetro de intervalos con aviso háptico.
///
/// La idea es entrenar sin mirar el teléfono: cada transición se siente. Tres pulsos abren cada
/// bloque de trabajo, uno solo anuncia el descanso, los últimos tres segundos de cualquier fase van
/// marcando 3-2-1, y el cierre de la sesión son cinco pulsos largos. Donde no hay hápticos (macOS)
/// queda como un temporizador grande y legible.
///
/// Régimen sobrio de «Liquid Glass · El Eje»: lienzo `.entrenarHojaFondo(.neutro)`, tarjetas
/// `.superficieSolida`. La cuenta regresiva manda en tinta; el color de la fase vive sólo en la
/// etiqueta, el anillo y las barras de ronda — nunca en el relleno de un botón. La pantalla no
/// dibuja su propia salida: el `NavigationStack` ambiente la aporta.
struct IntervalTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Los ajustes y la corrida, cada uno en un solo valor. Viven mientras la vista existe.
    @State private var plan = IntervalPlan()
    @State private var run = IntervalRun()
    /// `true` mientras se arma la sesión; `false` una vez que arrancó.
    @State private var configuring = true

    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Un tic por segundo.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: Derivados de lectura

    private var isFinished: Bool { run.phase == .done }
    private var isPristine: Bool { run.isPristine(in: plan) }

    private var primaryControlLabel: String {
        if run.running { return String(localized: "Pause") }
        if isFinished { return String(localized: "Restart") }
        return String(localized: "Start")
    }

    // MARK: Cuerpo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                if configuring {
                    planForm
                } else {
                    runHeader
                    stateChip
                    stageCard
                    summaryCard
                }
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .entrenarHojaFondo(tono: .neutro)
        .onReceive(ticker) { _ in tick() }
        .onChange(of: plan.work) { rewindIfIdle() }
        .onChange(of: plan.rest) { rewindIfIdle() }
        .onChange(of: plan.rounds) {
            run.round = min(run.round, plan.rounds)
            rewindIfIdle()
        }
        .onAppear { if run.remaining == 0 { run.rewind(to: plan) } }
        .enableInjection()
    }

    // MARK: Encabezado

    private var runHeader: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text("Interval Timer")
                .font(LiquidType.tituloHoja)
                .foregroundStyle(LiquidColor.tinta900)
            Text("Silent haptic HIIT: your phone buzzes the transitions")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }

    // MARK: Armado de la sesión

    private var planForm: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text("INTERVALS")
                    .liquidRegla()
                    .foregroundStyle(LiquidColor.tinta500)
                Text("Build your HIIT")
                    .font(LiquidType.displayL)
                    .tracking(LiquidType.displayLTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                settingRow(title: "Work", unit: "sec", value: $plan.work,
                           range: 5...600, step: 5, tint: LiquidColor.ambar)
                hairline
                settingRow(title: "Rest", unit: "sec", value: $plan.rest,
                           range: 5...600, step: 5, tint: LiquidColor.cian)
                hairline
                settingRow(title: "Rounds", unit: nil, value: $plan.rounds,
                           range: 1...30, step: 1, tint: LiquidColor.tinta900)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)

            HStack {
                Text("Total \(timeString(plan.totalSeconds))")
                    .font(LiquidType.valorM)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
            }

            LiquidGlassButton(String(localized: "Start"), variant: .primary, expands: true) {
                launchSession()
            }
        }
    }

    private var hairline: some View {
        Divider().overlay(LiquidColor.tinta10)
    }

    /// Una fila del formulario de armado: nombre + rango a la izquierda, valor y pasos a la derecha.
    private func settingRow(title: String, unit: String?, value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int, tint: Color) -> some View {
        // El literal inglés ES la clave del catálogo; VoiceOver necesita el String ya resuelto.
        let spokenName = String(localized: String.LocalizationValue(title))
        let suffix = unit.map { " \($0)" } ?? ""
        return HStack {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(LocalizedStringKey(title))
                    .font(LiquidType.tituloGemela)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("\(range.lowerBound)–\(range.upperBound)\(suffix) · step \(step)")
                    .font(LiquidType.unidad)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text("\(value.wrappedValue)")
                    .font(LiquidType.valorTileM)
                    .foregroundStyle(tint)
                    .frame(minWidth: 44, alignment: .trailing)
                if let unit {
                    Text(unit)
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            EntrenarStepper(
                valor: "\(value.wrappedValue)",
                puedeBajar: value.wrappedValue - step >= range.lowerBound,
                puedeSubir: value.wrappedValue + step <= range.upperBound,
                onBajar: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
                onSubir: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) })
                .accessibilityLabel(Text(verbatim: unit.map { "\(spokenName), \($0)" } ?? spokenName))
        }
    }

    // MARK: Fila de estado

    private var stateChip: some View {
        HStack(spacing: LiquidSpace.s250) {
            Spacer()
            if run.running {
                LiquidStatePill(String(localized: "Running"), dot: LiquidColor.ambar)
            } else if isFinished {
                LiquidStatePill(String(localized: "Complete"), dot: LiquidColor.verdePrimario)
            } else {
                LiquidStatePill(String(localized: "Paused"))
            }
        }
    }

    // MARK: Tarjeta escénica — la cara que se lee de un vistazo

    private var stageCard: some View {
        VStack(spacing: LiquidSpace.s400) {
            phaseLine
            roundBars

            ZStack {
                progressRing
                VStack(spacing: LiquidSpace.s050) {
                    // La cuenta es el dominante sobrio: tabular, en tinta, jamás en el hue de la fase.
                    Text(isFinished ? "✓" : "\(run.remaining)")
                        .font(LiquidType.displayXL)
                        .tracking(LiquidType.displayXLTracking)
                        .monospacedDigit()
                        .foregroundStyle(LiquidColor.tinta900)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .strandAnimation(.snappy, value: run.remaining)
                    Text(isFinished ? "SESSION DONE" : "SECONDS")
                        .liquidRegla()
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)

            controlRow
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }

    private var phaseLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(run.phase.label)
                .liquidKicker()
                .foregroundStyle(run.phase.hue)
            Spacer()
            HStack(spacing: LiquidSpace.s150) {
                Text("ROUND")
                    .liquidRegla()
                    .foregroundStyle(LiquidColor.tinta500)
                Text("\(min(run.round, plan.rounds))")
                    .font(LiquidType.valorL)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("/ \(plan.rounds)")
                    .font(LiquidType.valorL)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }

    /// Oculto a VoiceOver: la cuenta y el nombre de la fase ya dicen lo mismo en texto,
    /// así que el anillo es movimiento redundante, no información.
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(LiquidColor.tinta10, lineWidth: LiquidSpace.s400)
            Circle()
                .trim(from: 0, to: isFinished ? 1 : run.intervalProgress(in: plan))
                .stroke(run.phase.hue,
                        style: StrokeStyle(lineWidth: LiquidSpace.s400, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Con Reduce Motion `strandAnimation` se anula: el anillo salta, no interpola.
                .strandAnimation(.linear(duration: 0.9), value: run.intervalProgress(in: plan))
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }

    /// Una cápsula por ronda planeada, encima del anillo.
    private var roundBars: some View {
        HStack(spacing: LiquidSpace.s100) {
            ForEach(1...max(1, plan.rounds), id: \.self) { index in
                let pending = index > run.round && run.phase != .done
                LiquidBarraProgreso(
                    fraccion: 1,
                    tono: roundBarTone(index),
                    pista: roundBarTone(index),
                    altura: LiquidSpace.s150,
                    animada: false,
                    contorno: pending ? LiquidColor.tinta10 : nil)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Round \(min(run.round, plan.rounds)) of \(plan.rounds)"))
    }

    /// Ya vividas y la actual en su hue; las que faltan, en tinta apagada.
    private func roundBarTone(_ index: Int) -> Color {
        if run.phase == .done || index < run.round { return LiquidColor.ambar }
        if index == run.round { return run.phase == .rest ? LiquidColor.cian : LiquidColor.ambar }
        return LiquidColor.tinta10
    }

    private var controlRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(primaryControlLabel, variant: .primary, expands: true) {
                if isFinished { run.rewind(to: plan) }
                toggleRunning()
            }

            LiquidGlassButton(String(localized: "Reset"), variant: .glass, expands: true) {
                backToSetup()
            }
            .disabled(isPristine)
        }
    }

    // MARK: Tarjeta de resumen — transcurrido contra planeado

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session")
                    .liquidRegla()
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer()
                Text("\(timeString(run.elapsed)) / \(timeString(plan.totalSeconds))")
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            LiquidBarraProgreso(fraccion: run.sessionProgress(in: plan),
                                tono: LiquidColor.ambar,
                                altura: LiquidSpace.s200)

            HStack(spacing: .zero) {
                summaryStat("Work", "\(plan.work)s", LiquidColor.ambar)
                summaryStat("Rest", "\(plan.rest)s", LiquidColor.cian)
                summaryStat("Rounds", "\(plan.rounds)", LiquidColor.tinta900)
                summaryStat("Remaining", timeString(max(0, plan.totalSeconds - run.elapsed)),
                            LiquidColor.tinta700)
            }
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }

    private func summaryStat(_ label: LocalizedStringKey, _ value: String,
                             _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(label)
                .liquidRegla()
                .foregroundStyle(LiquidColor.tinta500)
            Text(value)
                .font(LiquidType.valorM)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: El reloj

    private func tick() {
        guard run.running, !isFinished else { return }

        // Marca 3-2-1 en los últimos segundos de la fase.
        if (1...3).contains(run.remaining) { buzz(.countdown) }

        run.elapsed += 1
        guard run.remaining > 1 else {
            advancePhase()
            return
        }
        run.remaining -= 1
    }

    /// El cambio de fase. El cierre necesita ir dentro de una animación —cambia toda la cara de la
    /// tarjeta a la vez—, los demás no.
    private func advancePhase() {
        var next = run
        let cue = next.advance(in: plan)
        if cue == .sessionEnd {
            withAnimation(LiquidMotion.condicionado(.snappy, reduceMotion)) { run = next }
        } else {
            run = next
        }
        if let cue { buzz(cue) }
    }

    // MARK: Mandos

    private func toggleRunning() {
        guard !isFinished else { return }
        if run.running {
            run.running = false
            return
        }
        // Sólo el arranque desde cero merece el aviso de apertura; reanudar a la mitad, no.
        let fromScratch = isPristine
        run.running = true
        if fromScratch { buzz(.sessionStart) }
    }

    /// Deja el armado atrás y echa a andar una sesión limpia.
    private func launchSession() {
        run.rewind(to: plan)
        configuring = false
        run.running = true
        buzz(.sessionStart)
    }

    private func backToSetup() {
        run.running = false
        run.rewind(to: plan)
        configuring = true
    }

    /// Un ajuste que se mueve mientras nadie corre rebobina la sesión; a media corrida, no la toca.
    private func rewindIfIdle() {
        guard !run.running else { return }
        run.rewind(to: plan)
    }

    private func buzz(_ cue: HapticCue) { model.buzz(loops: cue.loops) }

    // MARK: Formato

    private func timeString(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#if DEBUG
#Preview("Interval Timer · Liquid Glass") {
    IntervalTimerView()
        .environment(AppModel.preview)
        .frame(width: 720, height: 900)
}

#Preview("Interval Timer · xxxLarge (AX5)") {
    IntervalTimerView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 1100)
        .dynamicTypeSize(.accessibility5)
}
#endif
