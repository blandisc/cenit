#if DEBUG && CENIT_SPIKE_SERIES12
#if os(iOS)
import SwiftUI
import CenitDesign

/// Pantalla DEBUG FER-523: mide densidad de FC + HRV de la última noche.
/// Entrada: Ajustes → Fuentes de datos → Spike Series 12 (densidad).
struct SpikeSeries12DensityView: View {
    @State private var probe = SpikeSeries12DensityProbe()
    @State private var phase: Phase = .idle
    @State private var report: SpikeSeries12DensityProbe.Report?
    @State private var errorText: String?

    private enum Phase {
        case idle, requesting, measuring
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                header
                actions
                if let errorText {
                    Text(verbatim: errorText)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.rojoClaro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let report {
                    verdictCard(report)
                    metricCard(title: "Frecuencia cardiaca", density: report.heartRate, unitHint: "intervalo mediano")
                    metricCard(title: "HRV (\(report.hrvKind.rawValue))", density: report.hrv, unitHint: "cadencia")
                    notesCard(report.notes)
                    windowCard(report)
                } else {
                    placeholder
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
        }
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .navigationTitle("Spike Series 12")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("Sonda de densidad HealthKit")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("FER-523 · desechable · solo lectura · DEBUG + CENIT_SPIKE_SERIES12")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
            Text("Mide si el Series 12 entrega FC ~cada 5 s y HRV denso en la noche. Si sí, GO para la capa densa del motor.")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidGlassButton(phase == .requesting ? "Pidiendo permiso…" : "Pedir / confirmar permiso",
                              variant: .glass) {
                Task { await requestAccess() }
            }
            .disabled(phase != .idle)
            .opacity(phase != .idle ? 0.6 : 1)

            LiquidGlassButton(phase == .measuring ? "Midiendo…" : "Medir última noche",
                              variant: .primary) {
                Task { await measure() }
            }
            .disabled(phase != .idle)
            .opacity(phase != .idle ? 0.6 : 1)
        }
        .liquidTarjetaSeccion()
    }

    private var placeholder: some View {
        Text("Duerme una noche con el Series 12 puesto y toca Medir última noche. Sin red. Sin escritura.")
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
            .liquidTarjetaSeccion()
    }

    private func verdictCard(_ report: SpikeSeries12DensityProbe.Report) -> some View {
        let tone: Color = switch report.verdict {
        case .highDensity: LiquidColor.verdePrimario
        case .normalDensity: LiquidColor.tinta700
        case .insufficientData: LiquidColor.rojoClaro
        }
        return VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("Veredicto")
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: report.verdict.rawValue)
                .font(LiquidType.tituloFila)
                .foregroundStyle(tone)
            Text(verbatim: baselineLine(report))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }

    private func metricCard(title: String, density: SpikeSeries12DensityProbe.MetricDensity, unitHint: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(verbatim: title)
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .foregroundStyle(LiquidColor.tinta500)
            row("Muestras", "\(density.sampleCount)")
            row("Intervalo mediano", formatInterval(density.medianIntervalSeconds), hint: unitHint)
            row("Cobertura horaria",
                "\(density.hoursCovered)/\(density.hoursInWindow) h (\(percent(density.hourCoverage)))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }

    private func notesCard(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("Notas")
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .foregroundStyle(LiquidColor.tinta500)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text(verbatim: "· \(note)")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }

    private func windowCard(_ report: SpikeSeries12DensityProbe.Report) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text("Ventana")
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: report.windowSource)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
            Text(verbatim: "\(formatDate(report.windowStart)) → \(formatDate(report.windowEnd))")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }

    private func row(_ label: String, _ value: String, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: LiquidSpace.s200)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: value)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                if let hint {
                    Text(verbatim: hint)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
        }
    }

    // MARK: - Actions

    private func requestAccess() async {
        phase = .requesting
        errorText = nil
        defer { phase = .idle }
        do {
            try await probe.requestReadAccess()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func measure() async {
        phase = .measuring
        errorText = nil
        defer { phase = .idle }
        do {
            try await probe.requestReadAccess()
            report = try await probe.measureLastNight()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Format

    private func formatInterval(_ seconds: Double?) -> String {
        guard let seconds else { return "n/d" }
        if seconds < 90 {
            return String(format: "%.1f s", seconds)
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private func percent(_ x: Double) -> String {
        String(format: "%.0f%%", x * 100)
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func baselineLine(_ report: SpikeSeries12DensityProbe.Report) -> String {
        let hr = report.heartRate.medianIntervalSeconds.map { String(format: "%.1f s", $0) } ?? "sin mediana"
        return "FC mediana \(hr) · HRV \(report.hrv.sampleCount) muestras · baseline normal ≈ minutos + ~1 HRV/noche"
    }
}
#endif
#endif
