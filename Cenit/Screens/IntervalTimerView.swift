import SwiftUI
import Foundation
import CenitDesign

/// Cronómetro de intervalos con aviso háptico.
///
/// La idea es entrenar sin mirar el teléfono: cada transición se siente. Tres pulsos
/// abren cada bloque de trabajo, uno solo anuncia el descanso, los últimos tres segundos
/// de cualquier fase van marcando 3-2-1, y el cierre de la sesión son cinco pulsos largos.
/// Donde no hay hápticos (macOS) queda como un temporizador grande y legible.
///
/// Régimen sobrio de «Liquid Glass · El Eje»: lienzo `.entrenarHojaFondo(.neutro)`,
/// tarjetas `.superficieSolida`. La cuenta regresiva manda en tinta; el color de la fase
/// vive sólo en la etiqueta, el anillo y las barras de ronda — nunca en el relleno de un
/// botón. La pantalla no dibuja su propia salida: el `NavigationStack` ambiente la aporta.
struct IntervalTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Ajustes (viven sólo mientras la vista existe)

    @State private var workSeconds = 30
    @State private var restSeconds = 15
    @State private var rounds = 8

    // MARK: Estado de la corrida

    /// Los tres momentos por los que pasa una sesión.
    private enum Phase {
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

    @State private var phase: Phase = .work
    @State private var currentRound = 1
    /// Segundos que le quedan a la fase en curso.
    @State private var remaining = 30
    @State private var running = false
    /// Segundos acumulados en toda la sesión.
    @State private var elapsed = 0
    /// `true` mientras se arma la sesión; `false` una vez que arrancó.
    @State private var configuring = true

    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Un tic por segundo.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: Derivados

    private var isFinished: Bool { phase == .done }

    private var phaseDuration: Int {
        switch phase {
        case .work: max(1, workSeconds)
        case .rest: max(1, restSeconds)
        case .done: 1
        }
    }

    /// Avance 0…1 dentro del intervalo en curso.
    private var intervalProgress: Double {
        let duration = phaseDuration
        guard duration > 0 else { return 0 }
        return clamped(Double(duration - remaining) / Double(duration))
    }

    /// Largo planeado de la sesión: los bloques de trabajo más los descansos intermedios.
    private var totalPlanned: Int {
        guard rounds > 0 else { return 0 }
        return workSeconds * rounds + restSeconds * max(0, rounds - 1)
    }

    private var sessionProgress: Double {
        guard totalPlanned > 0 else { return 0 }
        return clamped(Double(elapsed) / Double(totalPlanned))
    }

    /// La sesión sigue intacta: nadie la ha arrancado ni movido.
    private var isPristine: Bool {
        !running && phase == .work && currentRound == 1
            && remaining == phaseDuration && elapsed == 0
    }

    private var primaryControlLabel: String {
        if running { return String(localized: "Pause") }
        if isFinished { return String(localized: "Restart") }
        return String(localized: "Start")
    }

    private func clamped(_ value: Double) -> Double { min(1, max(0, value)) }

    // MARK: Cuerpo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                if configuring {
                    setupSection
                } else {
                    header
                    statusRow
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
        .onChange(of: workSeconds) { if !running { rewind() } }
        .onChange(of: restSeconds) { if !running { rewind() } }
        .onChange(of: rounds) {
            currentRound = min(currentRound, rounds)
            if !running { rewind() }
        }
        .onAppear { if remaining == 0 { rewind() } }
        .enableInjection()
    }

    // MARK: Encabezado

    private var header: some View {
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

    private var setupSection: some View {
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
                settingRow(title: "Work", unit: "sec", value: $workSeconds,
                           range: 5...600, step: 5, tint: LiquidColor.ambar)
                hairline
                settingRow(title: "Rest", unit: "sec", value: $restSeconds,
                           range: 5...600, step: 5, tint: LiquidColor.cian)
                hairline
                settingRow(title: "Rounds", unit: nil, value: $rounds,
                           range: 1...30, step: 1, tint: LiquidColor.tinta900)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)

            HStack {
                Text("Total \(timeString(totalPlanned))")
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

    private var statusRow: some View {
        HStack(spacing: LiquidSpace.s250) {
            Spacer()
            if running {
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
                    Text(isFinished ? "✓" : "\(remaining)")
                        .font(LiquidType.displayXL)
                        .tracking(LiquidType.displayXLTracking)
                        .monospacedDigit()
                        .foregroundStyle(LiquidColor.tinta900)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .strandAnimation(.snappy, value: remaining)
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
            Text(phase.label)
                .liquidKicker()
                .foregroundStyle(phase.hue)
            Spacer()
            HStack(spacing: LiquidSpace.s150) {
                Text("ROUND")
                    .liquidRegla()
                    .foregroundStyle(LiquidColor.tinta500)
                Text("\(min(currentRound, rounds))")
                    .font(LiquidType.valorL)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("/ \(rounds)")
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
                .trim(from: 0, to: isFinished ? 1 : intervalProgress)
                .stroke(phase.hue,
                        style: StrokeStyle(lineWidth: LiquidSpace.s400, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Con Reduce Motion `strandAnimation` se anula: el anillo salta, no interpola.
                .strandAnimation(.linear(duration: 0.9), value: intervalProgress)
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }

    /// Una cápsula por ronda planeada, encima del anillo.
    private var roundBars: some View {
        HStack(spacing: LiquidSpace.s100) {
            ForEach(1...max(1, rounds), id: \.self) { index in
                let pending = index > currentRound && phase != .done
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
        .accessibilityLabel(Text("Round \(min(currentRound, rounds)) of \(rounds)"))
    }

    private func roundBarTone(_ index: Int) -> Color {
        if phase == .done || index < currentRound { return LiquidColor.ambar }
        if index == currentRound { return phase == .rest ? LiquidColor.cian : LiquidColor.ambar }
        return LiquidColor.tinta10
    }

    private var controlRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(primaryControlLabel, variant: .primary, expands: true) {
                if isFinished { rewind() }
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
                Text("\(timeString(elapsed)) / \(timeString(totalPlanned))")
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            LiquidBarraProgreso(fraccion: sessionProgress,
                                tono: LiquidColor.ambar,
                                altura: LiquidSpace.s200)

            HStack(spacing: .zero) {
                summaryStat("Work", "\(workSeconds)s", LiquidColor.ambar)
                summaryStat("Rest", "\(restSeconds)s", LiquidColor.cian)
                summaryStat("Rounds", "\(rounds)", LiquidColor.tinta900)
                summaryStat("Remaining", timeString(max(0, totalPlanned - elapsed)),
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
        guard running, !isFinished else { return }

        // Marca 3-2-1 en los últimos segundos de la fase.
        if (1...3).contains(remaining) { model.buzz(loops: 1) }

        elapsed += 1
        if remaining > 1 {
            remaining -= 1
        } else {
            nextPhase()
        }
    }

    private func nextPhase() {
        switch phase {
        case .work where currentRound >= rounds:
            // El último bloque de trabajo cierra la sesión: nunca hay descanso final.
            finish()
        case .work:
            phase = .rest
            remaining = max(1, restSeconds)
            model.buzz(loops: 1)
        case .rest:
            currentRound += 1
            phase = .work
            remaining = max(1, workSeconds)
            model.buzz(loops: 3)
        case .done:
            break
        }
    }

    private func finish() {
        withAnimation(LiquidMotion.condicionado(.snappy, reduceMotion)) {
            phase = .done
            remaining = 0
            running = false
        }
        model.buzz(loops: 5)
    }

    private func toggleRunning() {
        guard !isFinished else { return }
        if running {
            running = false
        } else {
            // Sólo el arranque desde cero merece el aviso de apertura.
            let fromScratch = isPristine
            running = true
            if fromScratch { model.buzz(loops: 3) }
        }
    }

    /// Deja el armado atrás y echa a andar una sesión limpia.
    private func launchSession() {
        rewind()
        configuring = false
        running = true
        model.buzz(loops: 3)
    }

    private func backToSetup() {
        running = false
        rewind()
        configuring = true
    }

    /// Vuelve al inicio de la ronda 1 con los ajustes vigentes.
    private func rewind() {
        phase = .work
        currentRound = 1
        remaining = max(1, workSeconds)
        elapsed = 0
    }

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
