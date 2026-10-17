import Foundation
import CenitTraining

// CEN-65 (barrido 2): el núcleo de `TrainingRegulation` vive en CenitTraining; la traducción del
// veredicto de recuperación (`Preparedness`) se queda aquí, del lado de análisis, hasta que el oráculo
// se retire. Desde la ola 1 la app ya no la usa para decidir subidas (`ComoAmaneciste`).

extension TrainingRegulation {
    /// Translate Hoy's verdict into Entrenar's advice. `isPending` has no default on purpose: every
    /// caller must state whether the verdict is merely late or genuinely absent (FER-82 gate round 1 —
    /// a defaulted parameter is how three surfaces silently kept the old oracle).
    public static func advice(verdict: Preparedness.Verdict?, isPending: Bool) -> Advice {
        if isPending { return .pending }
        switch verdict {
        case .full:      return .planAsIs
        case .caution:   return .lighter
        case .easy:      return .recover
        case .lowSignal: return .silent
        case nil:        return .silent
        }
    }

}
