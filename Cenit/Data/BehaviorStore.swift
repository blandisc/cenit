import Combine
import Foundation

/// Conductas que el usuario enciende o apaga a mano. Vive en `UserDefaults`, en el aparato, para un
/// solo usuario: no hay cuenta ni sincronización.
///
/// Historia: la automatización de la era del aparato externo se retiró en FER-1003. Sus llaves
/// quedaron huérfanas en `UserDefaults` a propósito — borrarlas no gana nada y arriesga tocar datos
/// de una instalación vieja.
@MainActor final class BehaviorStore: ObservableObject {
    /// Llaves de `UserDefaults`. Son valores persistidos: renombrarlas perdería la preferencia
    /// guardada en el teléfono de quien ya usa el app.
    private enum StoredKey {
        static let illnessWatch = "behavior.illnessWatch"
    }

    private let defaults: UserDefaults

    /// Aviso temprano de enfermedad. Apagado mientras nadie lo haya encendido.
    @Published var illnessWatch: Bool {
        didSet { defaults.set(illnessWatch, forKey: StoredKey.illnessWatch) }
    }

    init() {
        let store = UserDefaults.standard
        defaults = store
        // `object(forKey:)` distingue «nunca se guardó» de «se guardó false»; `bool(forKey:)` no.
        illnessWatch = (store.object(forKey: StoredKey.illnessWatch) as? Bool) ?? false
    }
}
