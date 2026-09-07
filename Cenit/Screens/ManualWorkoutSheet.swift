import SwiftUI
import CenitDesign
import CenitStore

// MARK: - Hoja de entreno manual — Liquid Glass · El Eje
//
// Registra un entrenamiento que se midió en otro lado, o corrige uno ya guardado. Cinco
// entradas — deporte, inicio, duración, FC media y calorías — validadas por
// `WorkoutSource.buildManualRow`, las mismas reglas de fila honesta que usa el motor. Quien
// llama es quien persiste (`Repository.saveManualWorkout`); esta vista no toca la base.
//
// Al editar, los campos que la hoja NO expone (maxHr / esfuerzo / zonas) se arrastran con
// `WorkoutSource.preservingCaptured`, para que cambiarle el deporte o la duración a una
// sesión medida en vivo nunca le borre su esfuerzo real.
//
// `editing` no nulo = edición: sus valores pre-llenan el formulario y la fila vieja vuelve
// como `replacing:`, de modo que un cambio de clave natural la retira. Nulo = alta nueva.
//
// Dos salidas, ambas conservadas: «Cancel» vive en la cabecera y Guardar/Añadir es el CTA
// del pie. El lienzo lo pinta `.entrenarHojaFondo` — nada de papel opaco encima del vidrio —
// y el formulario ocupa el ancho de la hoja (sin el ancho fijo de la era macOS).

struct ManualWorkoutSheet: View {
    /// La fila que se está editando, o nil para un alta nueva.
    let editing: WorkoutRow?
    /// Recibe la fila ya validada (y la original, si se editaba) cuando el usuario guarda.
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sport: String
    @State private var start: Date
    @State private var durationMin: Int
    @State private var avgHrText: String
    @State private var kcalText: String

    init(editing: WorkoutRow? = nil,
         onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing
        self.onSave = onSave
        // Pre-llenado desde la fila editada. El deporte se muestra ya legible («detected»
        // sale como «Activity») para que re-etiquetarlo empiece en limpio.
        _sport = State(initialValue: editing.map { WorkoutSource.displaySport($0.sport) } ?? "")
        _start = State(initialValue: editing.map {
            Date(timeIntervalSince1970: TimeInterval($0.startTs))
        } ?? Date())
        _durationMin = State(initialValue: editing.map { row in
            let seconds = row.durationS ?? Double(row.endTs - row.startTs)
            return max(1, Int((seconds / 60).rounded()))
        } ?? 45)
        _avgHrText = State(initialValue: editing?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: editing?.energyKcal.map { String(Int($0.rounded())) } ?? "")
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                header
                formFields
                if let validationNote { noteRow(validationNote) }
                footer
            }
            .padding(LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .entrenarHojaFondo(tono: .neutro)
        .presentationDragIndicator(.visible)
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - Secciones

    /// `EntrenarHojaCabecera(.cancelar)` absorbe título, subtítulo y la salida de «Cancel»
    /// (misma cadena, misma acción). El CTA de Guardar/Añadir se queda abajo: no cabe en la
    /// salida única de la cabecera junto a Cancelar.
    private var header: some View {
        EntrenarHojaCabecera(
            titulo: editing == nil
                ? String(localized: "Add Workout")
                : String(localized: "Edit Workout"),
            subtitulo: editing == nil
                ? String(localized: "Log a session you tracked elsewhere.")
                : String(localized: "Adjust this session's details."),
            tono: .neutro,
            salida: .cancelar(String(localized: "Cancel")),
            onSalir: { dismiss() }
        )
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.bloqueAjuste) {
            LiquidCampoTexto(
                String(localized: "Sport"),
                texto: $sport,
                placeholder: String(localized: "e.g. Running"),
                a11y: String(localized: "Sport"),
                tipografia: LiquidType.tituloGemela)

            field("Start") {
                DatePicker("", selection: $start, in: ...Date(),
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(LiquidColor.tinta900)
                    .accessibilityLabel("Start date and time")
            }

            field("Duration") {
                EntrenarStepper(
                    valor: durationLabel,
                    tono: .neutro,
                    talla: .fila,
                    puedeBajar: durationMin > 1,
                    puedeSubir: durationMin < maxDurationMin,
                    onBajar: { durationMin = max(1, durationMin - 5) },
                    onSubir: { durationMin = min(maxDurationMin, durationMin + 5) }
                )
                .accessibilityLabel("Duration in minutes")
            }

            HStack(alignment: .top, spacing: LiquidSpace.bloqueAjuste) {
                field("Avg HR") {
                    numberInput(
                        String(localized: "optional"),
                        text: $avgHrText,
                        unit: String(localized: "bpm"),
                        a11y: String(localized: "Average heart rate in beats per minute, optional"))
                }
                field("Calories") {
                    numberInput(
                        String(localized: "optional"),
                        text: $kcalText,
                        unit: "kcal",
                        a11y: String(localized: "Calories in kilocalories, optional"))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            saveButton
        }
        .padding(.top, LiquidSpace.s100)
    }

    /// Primario prominente: cápsula verde de veredicto cuando las entradas hacen una fila
    /// honesta, superficie callada cuando no (el mismo Guardar deshabilitado de siempre,
    /// dicho en el lenguaje claro). El verde del CTA activo es color semántico; la cápsula
    /// apagada usa el recorte opaco compartido `.pastillaSolida`.
    private var saveButton: some View {
        let title: LocalizedStringKey = editing == nil ? "Add" : "Save"
        return Group {
            if builtRow != nil {
                OutlineCapsule(
                    size: .aMedida(
                        insets: EdgeInsets(top: LiquidSpace.s225,
                                           leading: LiquidSpace.pastillaHorizontal,
                                           bottom: LiquidSpace.s225,
                                           trailing: LiquidSpace.pastillaHorizontal),
                        minHeight: nil,
                        touchInset: .zero),
                    filled: true,
                    fill: LiquidColor.verdePrimario,
                    action: { save() }
                ) {
                    Text(title)
                        .font(LiquidType.boton)
                        .foregroundStyle(LiquidColor.papelTarjeta)
                }
            } else {
                Button { save() } label: {
                    Text(title)
                        .font(LiquidType.boton)
                        .foregroundStyle(LiquidColor.tinta500)
                        .padding(.horizontal, LiquidSpace.pastillaHorizontal)
                        .padding(.vertical, LiquidSpace.s225)
                        .liquidGlass(.pastillaSolida)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
        }
        .accessibilityLabel(editing == nil ? "Add workout" : "Save workout")
    }

    private func field<Content: View>(_ label: LocalizedStringKey,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(label).liquidKicker().foregroundStyle(LiquidColor.tinta500)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberInput(_ placeholder: String, text: Binding<String>,
                             unit: String, a11y: String) -> some View {
        LiquidCampoTexto(
            nil,
            texto: text,
            placeholder: placeholder,
            teclado: LiquidCampoTeclado.numberPad,
            a11y: a11y,
            sufijo: unit,
            tipografia: LiquidType.valorM)
    }

    private func noteRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LiquidType.unidad)
            .foregroundStyle(LiquidColor.atencionTexto)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Validación y armado

    /// Tope de la duración: un día entero.
    private var maxDurationMin: Int { 24 * 60 }

    private var durationLabel: String {
        let hours = durationMin / 60
        let minutes = durationMin % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    private var trimmedHrText: String { avgHrText.trimmingCharacters(in: .whitespaces) }
    private var trimmedKcalText: String { kcalText.trimmingCharacters(in: .whitespaces) }

    /// FC media escrita: nil si el campo está en blanco; fuera de banda lo atrapa `buildManualRow`.
    private var avgHr: Int? { Int(trimmedHrText) }

    // FER-428: `Double("nan"/"1e999")` da NaN/±∞, y toda comparación con NaN es false, así que «nan»
    // se colaba por la validación 0–20,000. Filtra a finito: un valor no finito cuenta como inválido.
    private var kcal: Double? {
        Double(trimmedKcalText).flatMap { $0.isFinite ? $0 : nil }
    }

    /// La fila ya validada, o nil cuando las entradas no dan una honesta (es lo que apaga
    /// Guardar y enciende la nota). Pasa por el mismo `WorkoutSource.buildManualRow` del motor.
    private var builtRow: WorkoutRow? {
        // Un número escrito pero ilegible («abc» en FC media) es inválido: se corta antes de armar.
        guard trimmedHrText.isEmpty || avgHr != nil else { return nil }
        guard trimmedKcalText.isEmpty || kcal != nil else { return nil }
        guard let base = WorkoutSource.buildManualRow(start: start, durationMin: durationMin,
                                                      sport: sport, avgHr: avgHr, energyKcal: kcal)
        else { return nil }
        // Al editar, se arrastra lo capturado que la hoja no expone.
        return WorkoutSource.preservingCaptured(base, from: editing)
    }

    private var validationNote: LocalizedStringKey? {
        guard builtRow == nil else { return nil }
        if sport.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a sport." }
        if start > Date() { return "Start can't be in the future." }
        if !trimmedHrText.isEmpty, !(25...250).contains(avgHr ?? -1) {
            return "Average HR must be 25–250 bpm."
        }
        if !trimmedKcalText.isEmpty, !(0...20_000).contains(kcal ?? -1) {
            return "Calories must be 0–20,000."
        }
        return "Check the values and try again."
    }

    private func save() {
        guard let row = builtRow else { return }
        onSave(row, editing)
        dismiss()
    }
}

#if DEBUG
#Preview("Add") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ManualWorkoutSheet { _, _ in }
    }
}

#Preview("Edit") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ManualWorkoutSheet(editing: WorkoutRow(
            startTs: Int(Date().timeIntervalSince1970) - 3600, endTs: Int(Date().timeIntervalSince1970),
            sport: "Running", source: "manual", durationS: 3600, energyKcal: 540,
            avgHr: 148, maxHr: 172, strain: 12.4, distanceM: nil, zonesJSON: nil, notes: nil)) { _, _ in }
    }
}
#endif
