#if DEBUG && CENIT_SPIKE_IALOCAL
import SwiftUI
import CenitDesign
import CenitImport
import CenitTraining
#if canImport(UIKit)
import UIKit
import PhotosUI
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

// FER-524 spike DESECHABLE. Pantalla DEBUG: texto / foto → Extraer → JSON
// + estructura reconciliada + cronometro. Solo con el flag CENIT_SPIKE_IALOCAL.

struct SpikeFER524View: View {
    @State private var inputText = ""
    @State private var statusLine = "Listo."
    @State private var wireJSON = ""
    @State private var reconciledSummary = ""
    @State private var latencyLine = ""
    @State private var ocrLatencyLine = ""
    @State private var busy = false
    @State private var selectedCorpusId: String?
    #if canImport(UIKit)
    @State private var photoItem: PhotosPickerItem?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                header
                availabilityBlock
                corpusPicker
                inputBlock
                actionRow
                resultsBlock
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.vertical, LiquidSpace.s550)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .navigationTitle("Spike FER-524")
        #if canImport(UIKit)
        .onChange(of: photoItem) { _, new in
            guard let new else { return }
            Task { await loadPhoto(new) }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("IA local · desechable")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("Texto o foto → Foundation Models on-device → cenit.workout.v1 → importer real (solo muestra). Cero red. Cero DB.")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var availabilityBlock: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text("Disponibilidad del modelo")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(availabilityText)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
    }

    private var availabilityText: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SpikeLLMSession.availability() {
            case .available:
                return "available · SystemLanguageModel.default listo"
            case .unavailable(let reason):
                return "unavailable · \(reason)"
            case .sdkMissing:
                return "sdkMissing"
            }
        } else {
            return "Requiere iOS 26+ (Foundation Models)."
        }
        #else
        return "canImport(FoundationModels) = false. Compila con Xcode/SDK que traiga el framework."
        #endif
    }

    private var corpusPicker: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text("Corpus es-MX (\(SpikeCorpus.items.count))")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            ForEach(SpikeCorpus.items) { item in
                Button {
                    selectedCorpusId = item.id
                    inputText = item.text
                    statusLine = "Corpus: \(item.title) · \(item.tags.joined(separator: ", "))"
                } label: {
                    HStack {
                        Text(item.title)
                            .font(LiquidType.cuerpo)
                            .foregroundStyle(LiquidColor.tinta900)
                        Spacer(minLength: 0)
                        if selectedCorpusId == item.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(LiquidColor.verdePrimario)
                        }
                    }
                    .padding(.vertical, LiquidSpace.s100)
                }
                .buttonStyle(.plain)
                if item.id != SpikeCorpus.items.last?.id {
                    Divider().overlay(LiquidColor.tinta10)
                }
            }
        }
        .liquidTarjetaSeccion()
    }

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text("Entrada")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            TextEditor(text: $inputText)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta900)
                .frame(minHeight: 140)
                .padding(LiquidSpace.s200)
                .liquidGlass(.superficieSolida)
            #if canImport(UIKit)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Elegir foto (Vision OCR → texto)")
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.verdePrimario)
            }
            #endif
            if !ocrLatencyLine.isEmpty {
                Text(ocrLatencyLine)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .liquidTarjetaSeccion()
    }

    private var actionRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(busy ? "Extrayendo…" : "Extraer", variant: .primary) {
                Task { await extract() }
            }
            .disabled(busy || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(busy ? 0.6 : 1)
            Spacer(minLength: 0)
        }
    }

    private var resultsBlock: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text("Resultado")
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(statusLine)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            if !latencyLine.isEmpty {
                Text(latencyLine)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            if !wireJSON.isEmpty {
                Text("JSON wire (cenit.workout.v1)")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(wireJSON)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta900)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !reconciledSummary.isEmpty {
                Text("Estructura reconciliada (READ-ONLY)")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(reconciledSummary)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta900)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .liquidTarjetaSeccion()
    }

    @MainActor
    private func extract() async {
        busy = true
        defer { busy = false }
        wireJSON = ""
        reconciledSummary = ""
        latencyLine = ""
        statusLine = "Extrayendo…"

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let result = try await SpikeLLMSession.extract(from: inputText)
                latencyLine = "Latencia LLM local: \(result.latencyMs) ms"
                let preview = try SpikeProgramAdapter.preview(result.program)
                wireJSON = preview.wireJSON
                reconciledSummary = formatPreview(preview)
                statusLine = "OK · parse-valido · \(preview.program.routines.count) rutina(s) · \(preview.reconciled.count) slot(s) reconciliados · \(preview.unmatched.count) sin match"
            } catch {
                statusLine = "Error: \(error.localizedDescription)"
            }
            return
        }
        statusLine = "Requiere iOS 26+."
        #else
        statusLine = "FoundationModels no disponible en este SDK."
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func formatPreview(_ p: SpikeImportPreview) -> String {
        var lines: [String] = []
        lines.append("programa: \(p.program.name.isEmpty ? "(sin nombre)" : p.program.name)")
        lines.append("idioma: \(p.program.language.rawValue)")
        for (i, r) in p.program.routines.enumerated() {
            lines.append("- rutina[\(i)] \(r.name) · \(r.exercises.count) ej. · dia=\(r.planDay.map(String.init) ?? "nil")")
            for ex in r.exercises {
                let peso = ex.weightKg.map { String(format: "%.1f", $0) } ?? "nil"
                let reps = ex.reps.map(String.init) ?? "nil"
                let rest = ex.restSeconds.map(String.init) ?? "nil"
                lines.append("   · \(ex.name)  series=\(ex.sets) reps=\(reps) peso=\(peso) descanso=\(rest)")
            }
        }
        lines.append("")
        lines.append("matches (\(p.matches.count)):")
        for m in p.matches {
            lines.append("   \(m.importedName) → \(m.exerciseId) (\(m.exerciseName))\(m.auto ? " [auto]" : "")")
        }
        if !p.unmatched.isEmpty {
            lines.append("sin match: \(p.unmatched.joined(separator: ", "))")
        }
        lines.append("RoutineExercise[] en memoria: \(p.reconciled.count) (no persistidos)")
        return lines.joined(separator: "\n")
    }
    #endif

    #if canImport(UIKit)
    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        statusLine = "OCR…"
        ocrLatencyLine = ""
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                statusLine = "No se pudo cargar la foto."
                return
            }
            let ocr = try SpikeVisionOCR.recognizeText(in: image)
            inputText = ocr.text
            ocrLatencyLine = "Latencia OCR: \(ocr.latencyMs) ms · \(ocr.text.count) chars"
            statusLine = ocr.text.isEmpty ? "OCR sin texto." : "OCR listo. Revisa el texto y pulsa Extraer."
        } catch {
            statusLine = "OCR error: \(error.localizedDescription)"
        }
    }
    #endif
}

#endif
