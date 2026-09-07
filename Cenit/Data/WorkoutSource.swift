import Foundation
import CenitStore

/// Formato de fecha, hora y duración compartido por la lista de entrenamientos y el detalle, para que
/// las dos superficies no se separen y la lista no tenga que meter la mano en las estáticas privadas
/// del detalle. Fecha y hora salen en el locale del dispositivo (es-MX → «mié 18 jun», y 12 o 24 h
/// según la región).
enum WorkoutFormat {

    /// Duración en horas y minutos: «45m» por debajo de la hora, «1h 30m» de ahí en adelante.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func date(_ ts: Int) -> String { dayFormatter.string(from: instant(ts)) }

    static func time(_ ts: Int) -> String { clockFormatter.string(from: instant(ts)) }

    private static func instant(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    /// Plantillas localizadas, no formatos fijos: la región decide el orden y el reloj de 12/24 h.
    private static let dayFormatter = templateFormatter("EEE d MMM")
    private static let clockFormatter = templateFormatter("j:mm")

    private static func templateFormatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// De dónde viene una fila de entrenamiento, deducido de su columna `source`. El modelo de lectura
/// (`WorkoutRow`) no carga `deviceId`, así que el origen hay que recuperarlo de esa cadena.
///
/// Aquí vive además la lógica pura de la edición de una fila: qué se puede descartar, qué se
/// conserva al editar y qué entrada manual es honesta.
enum WorkoutSource: Equatable {
    /// Importación retirada desde un dispositivo de otra marca. Sigue existiendo porque hay filas suyas en disco.
    case legacyWearable
    /// Apple Health, ya sea del importador de archivo o de la sincronización viva.
    case apple
    /// Bout derivado en el teléfono por el análisis que ya se retiró.
    case detected
    /// Alta o edición hecha por la persona.
    case manual

    /// Cadenas heredadas que siguen escritas en la columna `source` de filas viejas: se conservan textuales.
    private enum Stored {
        static let legacyWearable = "whoop"
        static let derivedSuffix = "-noop"
        static let manual = "manual"
        static let applePrefixes = ["apple-health", "apple_health"]
        static let namedApplePrefix = "apple-health:"
    }

    /// Deportes ofrecidos al reetiquetar un bout derivado: cortos y honestos (después se afina en
    /// Editar). Los comparten el gesto de la lista y el menú del detalle.
    static let relabelSports = ["Running", "Walking", "Cycling", "Strength Training",
                                "Swimming", "Rowing", "Yoga", "HIIT"]

    /// El orden de estas pruebas ES el contrato; cada una de las dos primeras arregló un defecto real.
    static func classify(_ source: String) -> WorkoutSource {
        let s = source.lowercased()
        // 1) El sufijo del id derivado va PRIMERO: si no, un bout derivado cuyo id contuviera el
        //    nombre de la marca heredada caería a la rama de importación y quedaría imposible de
        //    descartar. Hoy es defensivo, y se queda para sobrevivir al próximo cambio de id.
        if s.hasSuffix(Stored.derivedSuffix) { return .detected }
        if s == Stored.manual { return .manual }
        // 2) El prefijo de Apple va ANTES de buscar la marca heredada: la sincronización viva escribe
        //    el nombre real de la app que grabó («apple-health:<nombre>»), y ese nombre puede ser el
        //    de la otra marca. Antes de esta precedencia, esa fila se clasificaba mal.
        if Stored.applePrefixes.contains(where: s.hasPrefix) { return .apple }
        if s.contains(Stored.legacyWearable) { return .legacyWearable }
        return .apple
    }

    /// El nombre de la app que escribió la sesión, cuando la sincronización viva lo trae después de
    /// «apple-health:» — por ejemplo «Strong». `nil` cuando la fuente no lleva nombre (una fila vieja
    /// sin él, o una fuente que no es Apple); quien llama pinta el honesto «Otra app».
    static func appleAppName(_ source: String) -> String? {
        guard source.hasPrefix(Stored.namedApplePrefix) else { return nil }
        let name = source.dropFirst(Stored.namedApplePrefix.count)
        return name.isEmpty ? nil : String(name)
    }

    /// El texto del deporte, con dos limpiezas antes de pintarlo:
    /// el detector guarda el token de máquina «detected» y se muestra como una actividad neutra
    /// (no afirmamos un deporte que nunca clasificamos); y Apple Health guarda el nombre crudo de
    /// HealthKit sin espacios, que hay que separar para que se lea como palabras (FER-76).
    static func displaySport(_ sport: String) -> String {
        sport == "detected" ? "Activity" : spacedActivityName(sport)
    }

    /// Mete un espacio en cada frontera camel-case (minúscula o dígito seguidos de mayúscula). Un
    /// nombre que YA trae espacio se devuelve intacto, así que esto sólo abre los nombres pegados.
    static func spacedActivityName(_ raw: String) -> String {
        guard !raw.contains(" ") else { return raw }
        var spaced = ""
        var previous: Character?
        for character in raw {
            if let previous, character.isUppercase, previous.isLowercase || previous.isNumber {
                spaced.append(" ")
            }
            spaced.append(character)
            previous = character
        }
        return spaced
    }

    /// El SF Symbol del deporte, buscado sobre el nombre en minúsculas. Lo comparten la lista y el
    /// detalle para que la misma sesión traiga el mismo glifo en todos lados. Gana la primera
    /// coincidencia; si nada pega, una figura de cardio mixto en vez de inventar disciplina.
    static func sfSymbol(for sport: String) -> String {
        let s = sport.lowercased()
        func any(_ needles: String...) -> Bool { needles.contains(where: s.contains) }

        if any("run")                          { return "figure.run" }
        if any("walk", "hike")                 { return "figure.walk" }
        if any("cycl", "bike", "ride")         { return "figure.outdoor.cycle" }
        if any("swim")                         { return "figure.pool.swim" }
        if any("row")                          { return "figure.rower" }
        if any("yoga")                         { return "figure.yoga" }
        if any("strength", "weight", "lift")   { return "dumbbell.fill" }
        if any("box")                          { return "figure.boxing" }
        if any("hiit", "functional")           { return "figure.highintensity.intervaltraining" }
        if any("elliptical")                   { return "figure.elliptical" }
        if any("ski")                          { return "figure.skiing.downhill" }
        if any("tennis")                       { return "figure.tennis" }
        if any("golf")                         { return "figure.golf" }
        if any("soccer", "football")           { return "figure.soccer" }
        if any("basketball")                   { return "figure.basketball" }
        if any("dance")                        { return "figure.dance" }
        if any("climb")                        { return "figure.climbing" }
        if any("pilates")                      { return "figure.pilates" }
        if any("meditat")                      { return "figure.mind.and.body" }
        return "figure.mixed.cardio"
    }

    // MARK: - Fuerza de terceros (FER-362 · C4)

    /// Llave de UserDefaults del interruptor «mostrar fuerza de otras apps» (encendido por omisión).
    /// El interruptor de Ajustes y la lista de «Fuerza» leen ESTA misma llave, para que no se separen.
    static let showThirdPartyStrengthKey = "workouts.showThirdPartyStrength"

    // MARK: - Bouts derivados descartados (#107)
    //
    // El motor borra y vuelve a derivar las filas detectadas en cada corrida, así que borrar una de
    // la tabla sólo la escondería hasta la siguiente derivación, que recrea la misma llave. El
    // registro durable de «esto no fue un entrenamiento» es una lista de lapsos en UserDefaults (la
    // fila vive en el archivo de bitácora de CenitStore, y esta capa no puede agregarle columnas).
    // Una fila derivada que traslape cualquier lapso descartado se queda oculta.

    /// Llave de UserDefaults con los lapsos descartados, como cadenas «inicio:fin».
    static let dismissedDefaultsKey = "workouts.dismissedDetected"

    /// Separador del token de lapso. También es el que parte la cadena al leerla.
    private static let spanSeparator: Character = ":"

    /// Lee los lapsos «inicio:fin». Lo malformado y lo de ancho no positivo se cae, para que un valor
    /// corrupto jamás pueda esconder la lista entera.
    static func parseDismissedSpans(_ raw: [String]) -> [(start: Int, end: Int)] {
        raw.compactMap { token in
            let parts = token.split(separator: spanSeparator)
            guard parts.count == 2,
                  let start = Int(parts[0]), let end = Int(parts[1]),
                  end > start
            else { return nil }
            return (start, end)
        }
    }

    /// El token que se guarda por una fila descartada; quien llama lo agrega a la lista de defaults.
    static func dismissedToken(for row: WorkoutRow) -> String {
        "\(row.startTs)\(spanSeparator)\(row.endTs)"
    }

    /// Filtro de lectura: una fila DERIVADA que traslape algún lapso descartado se oculta. Las filas
    /// importadas o manuales nunca se ocultan solas — ésas la persona las borra —, así que el
    /// descarte aplica únicamente a la fuente que se vuelve a derivar. Traslape medio abierto.
    static func isDismissed(_ row: WorkoutRow, spans: [(start: Int, end: Int)]) -> Bool {
        guard classify(row.source) == .detected else { return false }
        return spans.contains { row.startTs < $0.end && $0.start < row.endTs }
    }

    // MARK: - Armar y conservar filas

    /// Arrastra desde la fila que se está editando los campos capturados que la hoja NO expone
    /// (`maxHr`, `strain`, `distanceM`, `zonesJSON`, `notes`). Una sesión seguida en vivo trae
    /// esfuerzo y FC máxima reales: rearmar la fila sólo con lo que la hoja muestra los borraría en
    /// silencio. Con `old == nil` (alta nueva) no hace nada.
    static func preservingCaptured(_ row: WorkoutRow, from old: WorkoutRow?) -> WorkoutRow {
        guard let old else { return row }
        return WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: row.sport,
                          source: row.source, durationS: row.durationS,
                          energyKcal: row.energyKcal, avgHr: row.avgHr,
                          maxHr: old.maxHr, strain: old.strain, distanceM: old.distanceM,
                          zonesJSON: old.zonesJSON, notes: old.notes)
    }

    /// Arma un entrenamiento manual retroactivo. Devuelve `nil` cuando la entrada no da para una fila
    /// honesta. El esfuerzo se queda en `nil` a propósito: sin ventana de FC capturada, un esfuerzo
    /// aproximado sería un número inventado.
    static func buildManualRow(start: Date, durationMin: Int, sport: String,
                               avgHr: Int?, energyKcal: Double?, now: Date = Date()) -> WorkoutRow? {
        let minutesAllowed = 1...(24 * 60)
        let plausibleHr = 25...250
        let plausibleKcal = 0.0...20_000.0

        guard minutesAllowed.contains(durationMin), start <= now else { return nil }

        let name = sport.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let avgHr, !plausibleHr.contains(avgHr) { return nil }
        if let energyKcal, !plausibleKcal.contains(energyKcal) { return nil }

        let startTs = Int(start.timeIntervalSince1970)
        guard startTs > 0 else { return nil }

        let seconds = Double(durationMin) * 60
        return WorkoutRow(startTs: startTs, endTs: startTs + durationMin * 60,
                          sport: name, source: Stored.manual,
                          durationS: seconds, energyKcal: energyKcal, avgHr: avgHr,
                          maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil, notes: nil)
    }
}
