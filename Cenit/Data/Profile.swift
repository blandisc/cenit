import Combine
import Foundation

/// Quién es el usuario, en los números que el app necesita: edad, sexo, cuerpo y pulso máximo.
/// De aquí salen las zonas de pulso, las calorías y las líneas base de recuperación.
///
/// Todo vive en `UserDefaults`, en el aparato, para un solo usuario. Cada propiedad se guarda en el
/// momento en que cambia, así que no hay un «guardar» que alguien pueda olvidar.
@MainActor final class ProfileStore: ObservableObject {

    /// Llaves de `UserDefaults`. Son valores persistidos: renombrar una perdería el dato que ya está
    /// en el teléfono de quien usa el app.
    private enum StoredKey {
        static let age = "profile.age"
        static let sex = "profile.sex"
        static let weightKg = "profile.weightKg"
        static let heightCm = "profile.heightCm"
        static let hrMaxOverride = "profile.hrMaxOverride"
        static let stepTicksPerStep = "profile.stepTicksPerStep"
        static let baselineEpoch = "profile.baselineEpoch"
        static let previousBaselineEpoch = "profile.previousBaselineEpoch"
    }

    /// Rango en el que se acota el divisor de pasos, arriba y abajo.
    private static let stepTickRange: ClosedRange<Double> = 0.5...30.0

    private let defaults: UserDefaults

    // MARK: - Cuerpo

    @Published var age: Int {
        didSet { defaults.set(age, forKey: StoredKey.age) }
    }

    /// Uno de tres valores que entiende la capa de análisis: `"male"`, `"female"` o `"nonbinary"`.
    @Published var sex: String {
        didSet { defaults.set(sex, forKey: StoredKey.sex) }
    }

    @Published var weightKg: Double {
        didSet { defaults.set(weightKg, forKey: StoredKey.weightKg) }
    }

    @Published var heightCm: Double {
        didSet { defaults.set(heightCm, forKey: StoredKey.heightCm) }
    }

    /// Pulso máximo dictado a mano. `0` significa «estímalo por la edad».
    @Published var hrMaxOverride: Int {
        didSet { defaults.set(hrMaxOverride, forKey: StoredKey.hrMaxOverride) }
    }

    /// Divisor de calibración del contador de pasos **nativo** del aparato externo heredado
    /// (FER-665). Ese contador cuenta de más, así que el total del día se divide entre esta cifra
    /// antes de enseñarlo. `1.0` deja pasar el dato crudo.
    ///
    /// Se acota entre 0.5 y 30 — el sobreconteo observado llega a unas 24 veces, de ahí el techo tan
    /// alto. No confundir con los campos de *estimación* ya retirados: esto escala un conteo real.
    @Published var stepTicksPerStep: Double {
        didSet {
            defaults.set(Self.clampedStepTicks(stepTicksPerStep), forKey: StoredKey.stepTicksPerStep)
        }
    }

    // MARK: - Re-anclaje de la línea base (FER-677)

    /// Llave de día local (`"YYYY-MM-DD"`) desde la que cuenta la línea base. Cada plegado nocturno
    /// ignora las noches anteriores a este corte, así que la recuperación se re-ancla a partir de
    /// ahí. Vacío significa «usa todo el historial».
    @Published var baselineEpoch: String {
        didSet { defaults.set(baselineEpoch, forKey: StoredKey.baselineEpoch) }
    }

    /// El corte que estaba puesto antes de la última recalibración. Guarda exactamente un valor:
    /// «Deshacer» es un paso, no una pila. Vacío significa que no hay nada que restaurar.
    @Published var previousBaselineEpoch: String {
        didSet { defaults.set(previousBaselineEpoch, forKey: StoredKey.previousBaselineEpoch) }
    }

    // MARK: - Construcción

    init() {
        let store = UserDefaults.standard
        defaults = store

        // `object(forKey:)` distingue «nunca se guardó» de un cero legítimo; `string(forKey:)` ya
        // devuelve nil cuando falta.
        age = (store.object(forKey: StoredKey.age) as? Int) ?? 30
        sex = store.string(forKey: StoredKey.sex) ?? "male"
        weightKg = (store.object(forKey: StoredKey.weightKg) as? Double) ?? 75
        heightCm = (store.object(forKey: StoredKey.heightCm) as? Double) ?? 178
        hrMaxOverride = (store.object(forKey: StoredKey.hrMaxOverride) as? Int) ?? 0
        stepTicksPerStep = Self.clampedStepTicks(
            (store.object(forKey: StoredKey.stepTicksPerStep) as? Double) ?? 1.0
        )
        baselineEpoch = store.string(forKey: StoredKey.baselineEpoch) ?? ""
        previousBaselineEpoch = store.string(forKey: StoredKey.previousBaselineEpoch) ?? ""
    }

    private static func clampedStepTicks(_ raw: Double) -> Double {
        min(max(raw, stepTickRange.lowerBound), stepTickRange.upperBound)
    }

    // MARK: - Derivados

    /// El pulso máximo que usa el resto del app: el dictado a mano si lo hay, si no la estimación de
    /// Tanaka (`208 − 0.7 × edad`).
    var hrMax: Int {
        guard hrMaxOverride <= 0 else { return hrMaxOverride }
        return Int((208 - 0.7 * Double(age)).rounded())
    }

    /// El corte como lo quiere la capa de análisis: nada en vez de una cadena vacía.
    var baselineEpochOrNil: String? {
        baselineEpoch.isEmpty ? nil : baselineEpoch
    }

    /// Hay algo que deshacer mientras un corte esté puesto.
    var canUndoRecalibration: Bool {
        !baselineEpoch.isEmpty
    }

    // MARK: - Acciones

    /// Mueve el corte de la línea base a `day`, guardando el anterior para poder volver una vez.
    func recalibrate(to day: String) {
        previousBaselineEpoch = baselineEpoch
        baselineEpoch = day
    }

    /// Regresa al corte que estaba antes de la última recalibración, y se queda sin nada más que
    /// deshacer.
    func undoRecalibration() {
        baselineEpoch = previousBaselineEpoch
        previousBaselineEpoch = ""
    }
}
