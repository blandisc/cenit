#if DEBUG && CENIT_SPIKE_IALOCAL
import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

// FER-524 spike DESECHABLE. Foto → texto es-MX via Vision OCR on-device.
// Se mide aparte del LLM (latencia OCR vs latencia modelo).

struct SpikeOCRResult: Sendable {
    let text: String
    let latencyMs: Int
}

enum SpikeVisionOCR {
    enum OCRError: Error, LocalizedError {
        case noCGImage
        case visionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noCGImage: return "No se pudo leer la imagen."
            case .visionFailed(let m): return "Vision OCR fallo: \(m)"
            }
        }
    }

    #if canImport(UIKit)
    /// Reconoce texto en espanol (es-MX, es). On-device, sin red.
    static func recognizeText(in image: UIImage) throws -> SpikeOCRResult {
        guard let cgImage = image.cgImage else { throw OCRError.noCGImage }
        let t0 = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-MX", "es"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.visionFailed(error.localizedDescription)
        }
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        return SpikeOCRResult(text: lines.joined(separator: "\n"), latencyMs: max(ms, 0))
    }
    #endif
}

#endif
