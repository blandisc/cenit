import Foundation
import CenitModels
@testable import CenitAnalytics

// DailyStressOracleInputs.swift — las entradas sintéticas detrás de `daily-stress-oracle.json`.
//
// El proxy diario de carga autonómica (0–3) es un número PERSISTIDO: se guarda en la serie `stress`,
// se relee días después como historia y alimenta la curva y el «tiempo en calma» que la persona ya
// vio. Moverlo medio punto no «mejora» nada: reescribe en silencio un pasado que la persona
// recuerda. Por eso este archivo fija un conjunto de historias sintéticas, y el archivo de recursos
// graba lo que el modelo respondió para cada una.
//
// Todo se construye con ARITMÉTICA ENTERA y claves de día calculadas por calendario civil, sin
// `Date()`, sin `DateFormatter` y sin azar: las entradas son idénticas bit a bit en cualquier
// máquina y en cualquier corrida. El generador que escribió el archivo la primera vez y la prueba
// que hoy lo lee arman sus entradas por AQUÍ, así que las entradas no pueden separarse de lo grabado.

// MARK: - Claves de día

enum StressOracleCalendar {

    /// Clave `YYYY-MM-DD` a `offset` días del 2026-01-01, por aritmética civil entera
    /// (algoritmo de días-desde-la-era: sin `Date`, sin zona horaria, sin formateador).
    static func dayKey(_ offset: Int) -> String {
        var z = 20_454 + offset          // 2026-01-01 en días desde 1970-01-01
        z += 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return String(format: "%04d-%02d-%02d", m <= 2 ? y + 1 : y, m, d)
    }
}

// MARK: - Las historias

enum StressOracleInputs {

    /// Una historia completa lista para pasarse al modelo.
    struct Escenario {
        let name: String
        let days: [DailyMetric]
        let stored: [(day: String, value: Double)]
        let todayKey: String
        let appleDays: Set<String>
    }

    /// Un día con lo único que el proxy mira: pulso en reposo y HRV. El resto va vacío a propósito.
    static func dia(_ key: String, rhr: Int? = nil, hrv: Double? = nil) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// Onda triangular entera: sube y baja con periodo `periodo` entre 0 y `amplitud`.
    private static func triangulo(_ i: Int, periodo: Int, amplitud: Int) -> Int {
        let fase = i % periodo
        let mitad = periodo / 2
        let subida = fase < mitad ? fase : periodo - fase
        return (subida * amplitud) / mitad
    }

    /// 60 noches seguidas con las dos señales. El pulso oscila 54–62 lpm y la HRV 40–64 ms, ambas en
    /// onda triangular de periodo distinto para que la dispersión de las dos bases sea real y
    /// distinta. Ninguna lectura se repite igual dos días seguidos.
    static func historiaCompleta(_ n: Int = 60) -> [DailyMetric] {
        (0..<n).map { i in
            dia(StressOracleCalendar.dayKey(i),
                rhr: 54 + triangulo(i, periodo: 8, amplitud: 8),
                hrv: Double(40 + triangulo(i, periodo: 10, amplitud: 24)))
        }
    }

    /// La misma historia sin ninguna señal: cada fila existe pero está vacía.
    static func historiaVacia(_ n: Int = 5) -> [DailyMetric] {
        (0..<n).map { dia(StressOracleCalendar.dayKey($0)) }
    }

    /// Todos los escenarios grabados, en orden fijo.
    static func escenarios() -> [Escenario] {
        var out: [Escenario] = []

        // 1 · Una sola fuente, 60 noches limpias. El caso de siempre.
        let completa = historiaCompleta()
        out.append(Escenario(name: "unaFuente", days: completa, stored: [],
                             todayKey: StressOracleCalendar.dayKey(59), appleDays: []))

        // 2 · Dos fuentes mezcladas: uno de cada tres días llegó de Apple Health, con el desfase real
        //     (FC despierta ~11 lpm más alta, HRV como SDNN y no RMSSD). Las dos bases deben partirse.
        let mezclada = (0..<60).map { i -> DailyMetric in
            let esApple = i % 3 == 0
            return dia(StressOracleCalendar.dayKey(i),
                       rhr: (esApple ? 65 : 54) + triangulo(i, periodo: 8, amplitud: 8),
                       hrv: Double((esApple ? 62 : 40) + triangulo(i, periodo: 10, amplitud: 24)))
        }
        let diasApple = Set((0..<60).filter { $0 % 3 == 0 }.map(StressOracleCalendar.dayKey))
        out.append(Escenario(name: "dosFuentes", days: mezclada, stored: [],
                             todayKey: StressOracleCalendar.dayKey(59), appleDays: diasApple))

        // 3 · Huecos: uno de cada cuatro días sin pulso, uno de cada siete sin HRV, y el día 30 sin
        //     nada. La curva debe saltarse sólo lo que de verdad no tiene con qué.
        let conHuecos = (0..<45).map { i -> DailyMetric in
            if i == 30 { return dia(StressOracleCalendar.dayKey(i)) }
            return dia(StressOracleCalendar.dayKey(i),
                       rhr: i % 4 == 0 ? nil : 54 + triangulo(i, periodo: 8, amplitud: 8),
                       hrv: i % 7 == 0 ? nil : Double(40 + triangulo(i, periodo: 10, amplitud: 24)))
        }
        out.append(Escenario(name: "conHuecos", days: conHuecos, stored: [],
                             todayKey: StressOracleCalendar.dayKey(44), appleDays: []))

        // 4 · Valores ya guardados, incluidos dos fuera del rango legal (deben recortarse a 0 y 3) y
        //     una clave repetida (debe ganar la última).
        let guardados: [(day: String, value: Double)] = [
            (StressOracleCalendar.dayKey(50), -0.75),
            (StressOracleCalendar.dayKey(52), 3.75),
            (StressOracleCalendar.dayKey(55), 0.25),
            (StressOracleCalendar.dayKey(57), 2.5),
            (StressOracleCalendar.dayKey(59), 1.25),
            (StressOracleCalendar.dayKey(59), 2.75),
        ]
        out.append(Escenario(name: "conGuardados", days: completa, stored: guardados,
                             todayKey: StressOracleCalendar.dayKey(59), appleDays: []))

        // 5 · El ancla es de ayer: hoy llegó vacío (frontera de medianoche antes de sincronizar).
        var ayer = historiaCompleta(59)
        ayer.append(dia(StressOracleCalendar.dayKey(59)))
        out.append(Escenario(name: "anclaAyer", days: ayer, stored: [],
                             todayKey: StressOracleCalendar.dayKey(59), appleDays: []))

        // 6 · El ancla es vieja: los últimos cinco días vinieron vacíos. La curva sigue, el héroe no.
        var vieja = historiaCompleta(55)
        vieja.append(contentsOf: (55..<60).map { dia(StressOracleCalendar.dayKey($0)) })
        out.append(Escenario(name: "anclaVieja", days: vieja, stored: [],
                             todayKey: StressOracleCalendar.dayKey(59), appleDays: []))

        // 7 · Base plana: 30 noches idénticas. Sin dispersión no hay z-score, y el proxy debe caer
        //     exactamente en el centro del rango en vez de convertir el ruido en alarma.
        let plana = (0..<31).map { dia(StressOracleCalendar.dayKey($0), rhr: 58, hrv: 50.0) }
        out.append(Escenario(name: "basePlana", days: plana, stored: [],
                             todayKey: StressOracleCalendar.dayKey(30), appleDays: []))

        // 8 · Arranque en frío: un solo día con señal y nada contra qué medirlo → sin modelo.
        out.append(Escenario(name: "arranqueFrio",
                             days: [dia(StressOracleCalendar.dayKey(0), rhr: 58, hrv: 50)],
                             stored: [], todayKey: StressOracleCalendar.dayKey(0), appleDays: []))

        // 9 · Filas fantasma con fecha futura (el bucketing en UTC): no pueden hacer de hoy.
        out.append(Escenario(name: "soloFuturo",
                             days: [dia(StressOracleCalendar.dayKey(70), rhr: 60, hrv: 50)],
                             stored: [], todayKey: StressOracleCalendar.dayKey(59), appleDays: []))

        // 10 · Filas sin ninguna señal → sin modelo, nunca un 1.5 inventado.
        out.append(Escenario(name: "sinSenal", days: historiaVacia(), stored: [],
                             todayKey: StressOracleCalendar.dayKey(4), appleDays: []))

        // 11 · Sin señal cruda pero con un valor guardado: el guardado manda y el ancla es su día.
        out.append(Escenario(name: "soloGuardado", days: historiaVacia(),
                             stored: [(StressOracleCalendar.dayKey(3), 2.2)],
                             todayKey: StressOracleCalendar.dayKey(4), appleDays: []))

        // 12 · Una sola señal: la historia trae HRV y ningún pulso. El resultado se apoya en la que sí
        //      llegó, no se anula por la que falta.
        let soloHRV = (0..<40).map { i in
            dia(StressOracleCalendar.dayKey(i), rhr: nil,
                hrv: Double(40 + triangulo(i, periodo: 10, amplitud: 24)))
        }
        out.append(Escenario(name: "soloHRV", days: soloHRV, stored: [],
                             todayKey: StressOracleCalendar.dayKey(39), appleDays: []))

        // 13 · La otra sola señal: puro pulso, sin HRV en toda la historia.
        let soloPulso = (0..<40).map { i in
            dia(StressOracleCalendar.dayKey(i),
                rhr: 54 + triangulo(i, periodo: 8, amplitud: 8), hrv: nil)
        }
        out.append(Escenario(name: "soloPulso", days: soloPulso, stored: [],
                             todayKey: StressOracleCalendar.dayKey(39), appleDays: []))

        // 14 · Historia larga: 400 noches. La ventana debe seguir siendo de 30 días y la curva debe
        //      dibujarse completa, sin que la base se estire con la historia.
        out.append(Escenario(name: "historiaLarga", days: historiaCompleta(400), stored: [],
                             todayKey: StressOracleCalendar.dayKey(399), appleDays: []))

        return out
    }

    // MARK: - Entradas de la aritmética suelta

    /// Series fijas para `mean`/`std`, incluidas las degeneradas.
    static let series: [(name: String, xs: [Double])] = [
        ("vacia", []),
        ("una", [58]),
        ("plana", [58, 58, 58, 58]),
        ("subiendo", [50, 52, 54, 56, 58, 60]),
        ("dispersa", [40, 75, 51, 68, 44, 90, 39]),
        ("negativa", [-3, -1, 0, 2, 5]),
    ]

    /// Combinaciones de `rawScore`: las dos señales, una sola, ninguna, y la base plana en cada lado.
    static let crudos: [(name: String, rhr: Double?, meanRHR: Double?, sdRHR: Double,
                         hrv: Double?, meanHRV: Double?, sdHRV: Double)] = [
        ("ambas", 62, 58, 2.5, 41, 50, 6),
        ("ambasAbajo", 54, 58, 2.5, 61, 50, 6),
        ("soloPulso", 62, 58, 2.5, nil, nil, 0),
        ("soloHRV", nil, nil, 0, 41, 50, 6),
        ("ninguna", nil, nil, 0, nil, nil, 0),
        ("pulsoSinCentro", 62, nil, 2.5, 41, 50, 6),
        ("hrvSinCentro", 62, 58, 2.5, 41, nil, 6),
        ("pulsoBasePlana", 62, 58, 0, 41, 50, 6),
        ("hrvBasePlana", 62, 58, 2.5, 41, 50, 0),
        ("pulsoBaseCasiPlana", 62, 58, 0.00005, 41, 50, 6),
        ("dosPlanas", 62, 58, 0, 41, 50, 0),
        ("extremo", 999, 58, 0.5, 1, 50, 0.5),
    ]

    /// Crudos que se aplastan contra el rango 0–3, incluidos los que saturan.
    static let paraAplastar: [Double] = [-40, -8, -3, -1, -0.5, 0, 0.5, 1, 3, 8, 40]

    /// Puntajes justo en los bordes de las bandas y a cada lado.
    static let puntajes: [Double] = [0, 0.5, 0.999_999, 1, 1.000_001, 1.5, 1.999_999, 2, 2.000_001, 3]
}

// MARK: - El archivo grabado

/// La tabla de respuestas del proxy diario, con la misma forma que la de esfuerzo/pulso: cada caso
/// guarda sus valores como el texto decimal más corto que vuelve a leerse idéntico, para que la
/// comparación sea bit a bit y no pase por un formateador.
struct StressOracleTable {
    private let rows: [String: [String]]

    init(rows: [String: [String]]) { self.rows = rows }

    enum Falla: Error { case sinArchivo, sinCaso(String) }

    /// Carga el archivo que viaja con el paquete de pruebas.
    static func load() throws -> StressOracleTable {
        guard let url = Bundle.module.url(forResource: "daily-stress-oracle", withExtension: "json") else {
            throw Falla.sinArchivo
        }
        return StressOracleTable(rows: try JSONDecoder().decode([String: [String]].self,
                                                               from: Data(contentsOf: url)))
    }

    var keys: [String] { rows.keys.sorted() }

    func tokens(_ key: String) throws -> [String] {
        guard let v = rows[key] else { throw Falla.sinCaso(key) }
        return v
    }
}

/// Cómo se escribe cada respuesta del modelo en la tabla. Un modelo que no existe se graba como una
/// sola marca: distinguir «no hay modelo» de «hay modelo en la base» es el punto de varios casos.
enum StressOracleRender {

    static func band(_ b: StressBand) -> String {
        switch b {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    /// Todas las salidas de un escenario, en un orden fijo.
    static func escalares(_ m: DailyStressModel?) -> [String] {
        guard let m else { return ["nil"] }
        return [
            OracleText.of(m.score),
            band(m.band),
            OracleText.of(m.rhrToday),
            OracleText.of(m.hrvToday),
            OracleText.of(m.rhrDelta),
            OracleText.of(m.hrvDelta),
            OracleText.of(m.usingStored),
            OracleText.of(m.calmDays),
            OracleText.of(m.calmWindow),
            m.anchorDayKey,
            OracleText.of(m.anchorIsToday),
            OracleText.of(m.heroIsFresh),
            OracleText.of(m.fullTrend.count),
        ]
    }

    /// La curva completa: día (en días desde la era) y valor, punto por punto.
    static func curva(_ m: DailyStressModel?) -> [String] {
        guard let m else { return ["nil"] }
        return m.fullTrend.flatMap {
            [OracleText.of(Int($0.date.timeIntervalSince1970) / 86_400), OracleText.of($0.value)]
        }
    }
}
