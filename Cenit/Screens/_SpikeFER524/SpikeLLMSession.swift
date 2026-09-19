#if DEBUG && CENIT_SPIKE_IALOCAL
#if canImport(FoundationModels)
import Foundation
import FoundationModels

// FER-524 spike DESECHABLE. Sesion de una vuelta (NO chatbot) contra
// SystemLanguageModel.on-device. Firmas sujetas a verificacion del director
// al compilar con el SDK Foundation Models.

/// Resultado de una extraccion local: programa tipado + latencia en ms.
@available(iOS 26.0, *)
struct SpikeExtractionResult: Sendable {
    let program: SpikeProgram
    let latencyMs: Int
}

/// Motivo legible de por que el modelo no esta listo.
enum SpikeModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case sdkMissing
}

/// Arnes de extraccion on-device. Una entrada, una salida tipada.
@available(iOS 26.0, *)
enum SpikeLLMSession {
    /// Instrucciones de sistema (es-MX). El modelo solo estructura; no inventa.
    static let systemInstructions = """
        Extrae UNA rutina o programa de fuerza del texto del usuario como estructura tipada.
        No inventes ejercicios, series, reps, peso ni descanso.
        Si un dato no aparece en el texto, dejalo vacio (nil o cadena vacia).
        Parsear «80kg» a peso 80 es correcto; calcular o sugerir un peso NO lo es.
        No eres un chatbot: una entrada, una salida estructurada.
        idioma siempre «es». unidad «kg» salvo que el texto use lb/libras.
        """

    /// Chequea `SystemLanguageModel.default.availability` y reporta el motivo.
    static func availability() -> SpikeModelAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: describe(reason))
        @unknown default:
            return .unavailable(reason: "motivo desconocido del SDK")
        }
    }

    /// Una vuelta: prompt de usuario → `SpikeProgram` guiado + cronometro.
    ///
    /// Firma esperada (verificar contra SDK):
    /// `LanguageModelSession(instructions:).respond(to:generating:)`
    /// Alternativa documentada: `respond(to:generating:includeSchemaInPrompt:options:)`.
    static func extract(from text: String) async throws -> SpikeExtractionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpikeLLMError.emptyInput
        }
        guard case .available = availability() else {
            throw SpikeLLMError.modelUnavailable(availability())
        }

        let session = LanguageModelSession(instructions: systemInstructions)
        let t0 = Date()
        // Posible punto de falla de firma: overload `respond(to:generating:)`.
        // Si el SDK solo expone el overload con `includeSchemaInPrompt`/`options`
        // o el trailing-closure `prompt:`, el director ajusta al compilar.
        let response = try await session.respond(
            to: trimmed,
            generating: SpikeProgram.self
        )
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        return SpikeExtractionResult(program: response.content, latencyMs: max(ms, 0))
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "deviceNotEligible (dispositivo no elegible para Apple Intelligence)"
        case .appleIntelligenceNotEnabled:
            return "appleIntelligenceNotEnabled (Apple Intelligence apagado)"
        case .modelNotReady:
            return "modelNotReady (modelo descargando o no listo)"
        @unknown default:
            return String(describing: reason)
        }
    }
}

enum SpikeLLMError: Error, LocalizedError {
    case emptyInput
    case modelUnavailable(SpikeModelAvailability)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "El texto de entrada esta vacio."
        case .modelUnavailable(let a):
            if case .unavailable(let r) = a { return "Modelo no disponible: \(r)" }
            return "Modelo no disponible."
        }
    }
}

#endif
#endif
