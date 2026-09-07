import Combine
import Foundation

/// El catálogo de conductas de la bitácora: las preguntas de arranque más las que el usuario escribe.
///
/// La regla que gobierna este archivo: **la pregunta es dato, no texto de pantalla**. El motor de
/// ideas une un día registrado con un día importado comparando la pregunta carácter por carácter, así
/// que se guarda literal y se muestra literal. Traducirla partiría una conducta en dos. Lo que sí se
/// traduce es la etiqueta corta que ve el usuario, y eso pasa aparte, en `esLabel(for:)`.
///
/// Vive en `UserDefaults`, en el aparato, para un solo usuario.
@MainActor final class JournalCatalogStore: ObservableObject {
    // MARK: - Conductas de arranque (datos estables, jamás localizados)

    /// Las diez preguntas con las que empieza cualquier instalación. El texto y el orden son parte
    /// del contrato de datos: cada cadena viaja tal cual a la tabla de bitácora y a la exportación.
    nonisolated static let starterQuestions: [String] = [
        "Did you drink any alcohol?",
        "Did you have caffeine late in the day?",
        "Did you view a screen in bed?",
        "Did you eat close to bedtime?",
        "Did you feel stressed?",
        "Did you use a sauna?",
        "Did you share your bed?",
        "Did you feel sick or ill?",
        "Did you take magnesium?",
        "Did you read before bed?",
    ]

    /// La identidad de la conducta «seguiste tu dieta» del Coach (FER-385). Es una cadena estable en
    /// inglés, igual que las de arranque: llave de unión del motor y valor guardado en la fila de un
    /// experimento.
    ///
    /// Vive aparte de `starterQuestions` porque no se responde en la bitácora — sale de la serie
    /// `diet-adherence`. Su etiqueta visible sale por `esLabel(for:)`, como cualquier otra conducta.
    nonisolated static let dietBehaviorKey = "Did you follow your diet?"

    // MARK: - Preguntas propias

    /// Llaves de `UserDefaults`. Valor persistido: no renombrar.
    private enum StoredKey {
        static let customQuestions = "journal.customQuestions"
    }

    private let defaults: UserDefaults

    /// Las preguntas que el usuario agregó. Cada escritura se guarda de inmediato.
    @Published var customQuestions: [String] {
        didSet { defaults.set(customQuestions, forKey: StoredKey.customQuestions) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        self.customQuestions = defaults.stringArray(forKey: StoredKey.customQuestions) ?? []
    }

    // MARK: - Unión de las tres listas

    /// Junta las conductas importadas, las de arranque y las propias en una sola lista.
    ///
    /// Las importadas van al frente por una razón concreta: son las cadenas exactas que el motor de
    /// efectos ya usa como llave en el archivo que se importó. Si una de arranque dice lo mismo con
    /// otra grafía, la que sobrevive tiene que ser la importada, o el historial se rompe en dos.
    ///
    /// De ahí sale el resto de las reglas: se recortan los espacios de las orillas, lo que quede
    /// vacío se descarta, y la comparación para detectar repetidas ignora mayúsculas y minúsculas
    /// aunque la cadena se conserve con la grafía de quien llegó primero.
    nonisolated static func mergeCatalog(imported: [String], custom: [String]) -> [String] {
        var merged: [String] = []
        var claimed = Set<String>()

        for question in imported + starterQuestions + custom {
            let trimmed = question.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard claimed.insert(trimmed.lowercased()).inserted else { continue }
            merged.append(trimmed)
        }

        return merged
    }

    // MARK: - Etiqueta visible

    /// La etiqueta corta que se le enseña al usuario para una conducta conocida.
    ///
    /// La pregunta misma es la llave del catálogo de cadenas, así que el texto en español sigue el
    /// idioma del app y comparte una sola fuente con el motor de ideas (FER-312, FER-477). Una
    /// pregunta que nadie tradujo — propia o importada — se muestra tal como se escribió.
    nonisolated static func esLabel(for question: String) -> String {
        guard question != dietBehaviorKey else {
            return String(localized: "I followed my diet", bundle: .main)
        }
        return Bundle.main.localizedString(forKey: question, value: question, table: nil)
    }
}
