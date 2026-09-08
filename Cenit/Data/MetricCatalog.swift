import Foundation

/// Una métrica interrogable: de dónde se lee (llave + partición), cómo se etiqueta y se formatea, y
/// si más es mejor (eso tiñe los deltas). El explorador de métricas y la comparación se arman con
/// esta lista, así que agregar una métrica es agregar una fila del catálogo, no una pantalla.
struct MetricDescriptor: Identifiable, Hashable {
    /// La llave tal cual la escriben los importadores en `metricSeries`. Es valor persistido.
    let key: String
    /// El nombre largo. Es IDENTIDAD que leen otros consumidores; lo visible sale de `canonicalTitle`.
    let title: String
    /// Se queda en inglés a propósito: hay comparaciones sobre él. Lo visible sale de `localizedCategory`.
    let category: String
    let unit: String
    /// Id de la partición donde vive la fila. Es valor persistido.
    let source: String
    let icon: String
    let decimals: Int
    /// `nil` = la métrica no tiene una dirección buena; no se tiñe el delta.
    let higherIsBetter: Bool?

    var id: String { "\(source):\(key)" }

    var localizedCategory: String { MetricCatalog.localizedCategory(category) }

    /// El ÚNICO nombre canónico — el que ya muestra la pantalla principal, para que una métrica se
    /// llame igual en todas partes (FER-104 / HJ-13: «una métrica, un nombre»). El nombre largo sólo
    /// vive como expansión de la ⓘ; jamás como título (D4/C-18, HJ-12). Cuatro métricas tienen nombre
    /// corto propio; el resto se titula con su nombre de catálogo.
    var canonicalTitle: String {
        switch key {
        case "strain": return String(localized: "Effort")
        case "stress": return String(localized: "Stress")
        // D4/C-18: exactamente las cadenas cortas de la matriz de Hoy, no las largas del catálogo.
        case "hrv":    return String(localized: "HRV")
        case "rhr":    return String(localized: "Resting HR")
        default:       return title
        }
    }

    /// Número + unidad. Un valor no finito se declara ausente en vez de imprimir «inf» (FER-465).
    func format(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        let number = decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    /// Formato consciente del sistema de unidades. SÓLO las dos unidades que tienen forma imperial se
    /// convierten (masa en kg, temperatura en °C); el resto — %, bpm, ms, min, kcal, /21, /3 — es
    /// agnóstico y cae al formato llano, así que el interruptor imperial nunca toca lo que no debe.
    func format(_ v: Double, system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch convertibleUnit {
        case .mass:        return UnitFormatter.massFromKilograms(v, system: system)
        case .temperature: return UnitFormatter.temperatureFromCelsius(v, unit: temperature, decimals: decimals)
        case nil:          return format(v)
        }
    }

    /// Como `format`, pero para una DIFERENCIA entre dos valores. Un delta de temperatura escala por
    /// 9/5 y no lleva el corrimiento de +32. Quien llama entrega la magnitud; el signo lo pinta aparte.
    func formatDelta(_ v: Double, system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch convertibleUnit {
        case .mass:        return UnitFormatter.massFromKilograms(v, system: system)
        case .temperature: return UnitFormatter.temperatureDeltaFromCelsius(v, unit: temperature, decimals: decimals)
        case nil:          return format(v)
        }
    }

    /// La etiqueta de unidad como se pinta, ya mapeada al sistema activo.
    func displayUnit(system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch convertibleUnit {
        case .mass:        return UnitFormatter.massUnit(system)
        case .temperature: return UnitFormatter.temperatureUnit(temperature)
        case nil:          return unit
        }
    }

    /// Las únicas dos unidades del catálogo que se guardan en SI y tienen contraparte imperial.
    private enum ConvertibleUnit { case mass, temperature }

    private var convertibleUnit: ConvertibleUnit? {
        switch unit {
        case "kg": return .mass
        case "°C": return .temperature
        default:   return nil
        }
    }
}

/// El catálogo canónico de métricas. Las llaves son EXACTAMENTE las que los importadores escriben en
/// `metricSeries`, así que esta lista es a la vez el índice de la interfaz y el contrato con el disco.
enum MetricCatalog {

    /// El orden ES el orden de las secciones en pantalla. Inglés a propósito: es identidad.
    static let categories = ["Heart", "Recovery", "Sleep", "Strain", "Health"]

    /// Ids de partición, valores persistidos: así están escritos en las filas del disco.
    private enum Partition {
        static let legacy = "strap"
        static let apple = "apple-health"
    }

    // Los títulos se envuelven en `String(localized:)` EN el literal: la extracción de cadenas de
    // Xcode sólo ve el literal, y un `String` ya guardado en un campo nunca se localiza.
    static let all: [MetricDescriptor] = heart + recovery + sleep + strain + health

    // MARK: Corazón

    private static let heart: [MetricDescriptor] = [
        metric("avg_hr", String(localized: "Average Heart Rate"), "Heart",
               unit: String(localized: "bpm"), Partition.legacy, icon: "heart"),
        metric("max_hr", String(localized: "Max Heart Rate"), "Heart",
               unit: String(localized: "bpm"), Partition.legacy, icon: "bolt.heart"),
        metric("energy_kcal", String(localized: "Calories"), "Heart",
               unit: "kcal", Partition.legacy, icon: "flame"),
        metric("vo2max", String(localized: "VO₂ Max"), "Heart",
               unit: "", Partition.apple, icon: "lungs.fill", decimals: 1, higherIsBetter: true),
    ]

    // MARK: Recuperación

    private static let recovery: [MetricDescriptor] = [
        metric("recovery", String(localized: "Recovery"), "Recovery",
               unit: "%", Partition.legacy, icon: "heart.circle", higherIsBetter: true),
        metric("hrv", String(localized: "Heart Rate Variability"), "Recovery",
               unit: "ms", Partition.legacy, icon: "waveform.path.ecg", higherIsBetter: true),
        metric("rhr", String(localized: "Resting Heart Rate"), "Recovery",
               unit: String(localized: "bpm"), Partition.legacy, icon: "heart", higherIsBetter: false),
        metric("resp_rate", String(localized: "Respiratory Rate"), "Recovery",
               unit: "rpm", Partition.legacy, icon: "lungs", decimals: 1, higherIsBetter: false),
        metric("spo2", String(localized: "Blood Oxygen"), "Recovery",
               unit: "%", Partition.legacy, icon: "drop", higherIsBetter: true),
        // La temperatura de piel no tiene dirección buena: subir y bajar son ambos señal.
        metric("skin_temp", String(localized: "Skin Temperature"), "Recovery",
               unit: "°C", Partition.legacy, icon: "thermometer", decimals: 1),
    ]

    // MARK: Sueño

    private static let sleep: [MetricDescriptor] = [
        metric("sleep_performance", String(localized: "Sleep Performance"), "Sleep",
               unit: "%", Partition.legacy, icon: "moon.stars", higherIsBetter: true),
        metric("in_bed_min", String(localized: "Time in Bed"), "Sleep",
               unit: "min", Partition.legacy, icon: "bed.double"),
        metric("sleep_total_min", String(localized: "Asleep Time"), "Sleep",
               unit: "min", Partition.legacy, icon: "moon.zzz", higherIsBetter: true),
        metric("hours_vs_needed_pct", String(localized: "Hours vs Needed"), "Sleep",
               unit: "%", Partition.legacy, icon: "gauge.medium", higherIsBetter: true),
        metric("sleep_consistency", String(localized: "Sleep Consistency"), "Sleep",
               unit: "%", Partition.legacy, icon: "calendar", higherIsBetter: true),
        metric("restorative_pct", String(localized: "Restorative Sleep"), "Sleep",
               unit: "%", Partition.legacy, icon: "sparkles", higherIsBetter: true),
        metric("restorative_min", String(localized: "Restorative Sleep"), "Sleep",
               unit: "min", Partition.legacy, icon: "sparkles", higherIsBetter: true),
        metric("sleep_efficiency", String(localized: "Sleep Efficiency"), "Sleep",
               unit: "%", Partition.legacy, icon: "bed.double.fill", higherIsBetter: true),
        metric("sleep_deep_min", String(localized: "Deep (SWS) Sleep"), "Sleep",
               unit: "min", Partition.legacy, icon: "moon.fill", higherIsBetter: true),
        metric("sleep_rem_min", String(localized: "REM Sleep"), "Sleep",
               unit: "min", Partition.legacy, icon: "moon.haze", higherIsBetter: true),
        metric("sleep_light_min", String(localized: "Light Sleep"), "Sleep",
               unit: "min", Partition.legacy, icon: "moon"),
        metric("sleep_need_min", String(localized: "Sleep Need"), "Sleep",
               unit: "min", Partition.legacy, icon: "gauge"),
        metric("sleep_debt_min", String(localized: "Sleep Debt"), "Sleep",
               unit: "min", Partition.legacy, icon: "exclamationmark.circle", higherIsBetter: false),
    ]

    // MARK: Esfuerzo

    private static let strain: [MetricDescriptor] = [
        metric("strain", String(localized: "Day Strain"), "Strain",
               unit: "/21", Partition.legacy, icon: "flame", decimals: 1),
        metric("steps", String(localized: "Steps"), "Strain",
               unit: "", Partition.apple, icon: "figure.walk", higherIsBetter: true),
        metric("hr_zones13_min", String(localized: "HR Zones 1–3"), "Strain",
               unit: "min", Partition.legacy, icon: "heart"),
        metric("hr_zones45_min", String(localized: "HR Zones 4–5"), "Strain",
               unit: "min", Partition.legacy, icon: "heart.fill"),
        metric("hr_zones_all_min", String(localized: "HR Zones (All)"), "Strain",
               unit: "min", Partition.legacy, icon: "heart.text.square"),
        metric("strength_min", String(localized: "Strength Activity Time"), "Strain",
               unit: "min", Partition.legacy, icon: "dumbbell"),
        metric("active_kcal", String(localized: "Active Energy"), "Strain",
               unit: "kcal", Partition.apple, icon: "flame.fill"),
    ]

    // MARK: Cuerpo

    private static let health: [MetricDescriptor] = [
        metric("weight", String(localized: "Weight"), "Health",
               unit: "kg", Partition.apple, icon: "scalemass", decimals: 1),
        metric("body_fat", String(localized: "Body Fat"), "Health",
               unit: "%", Partition.apple, icon: "percent", decimals: 1, higherIsBetter: false),
        metric("lean_mass", String(localized: "Lean Body Mass"), "Health",
               unit: "kg", Partition.apple, icon: "figure.arms.open", decimals: 1, higherIsBetter: true),
        metric("bmi", String(localized: "BMI"), "Health",
               unit: "", Partition.apple, icon: "figure", decimals: 1),
        metric("stress", String(localized: "Day Stress"), "Health",
               unit: "/3", Partition.legacy, icon: "gauge.with.needle", decimals: 1, higherIsBetter: false),
    ]

    // MARK: Búsquedas

    static func inCategory(_ c: String) -> [MetricDescriptor] { all.filter { $0.category == c } }

    /// Las ÚNICAS dos llaves donde la convención de ingesta y la del catálogo se separan.
    private static let ingestAliases = ["resting_hr": "rhr", "asleep_min": "sleep_total_min"]

    /// La ÚNICA normalización entre la llave de INGESTA — la que hablan el camino de HealthKit y las
    /// dos pantallas de Apple Health — y la llave de CATÁLOGO por la que están indexados este archivo,
    /// `MetricIdentity` (tono y glifo) y `canonicalTitle`. Toda llave que no sea una de las dos
    /// excepciones ya ES llave de catálogo y pasa igual. Se acuñó aquí (FER-108) para que las
    /// pantallas de Apple Health reusaran la ÚNICA fuente de identidad en vez de inventar una tercera
    /// convención para la misma métrica. Ver `MetricIdentity.identity(forIngestKey:)`.
    static func catalogKey(forIngestKey key: String) -> String {
        ingestAliases[key] ?? key
    }

    /// El descriptor de una llave de ingesta o de catálogo (normaliza primero). `nil` sólo cuando la
    /// llave no existe en ninguna de las dos convenciones.
    static func descriptor(forIngestKey key: String) -> MetricDescriptor? {
        let normalized = catalogKey(forIngestKey: key)
        return all.first { $0.key == normalized }
    }

    /// El nombre visible de una categoría. Las cinco conocidas se traducen; cualquier otra cadena
    /// regresa tal cual.
    static func localizedCategory(_ c: String) -> String {
        switch c {
        case "Heart":    return String(localized: "Heart")
        case "Recovery": return String(localized: "Recovery")
        case "Sleep":    return String(localized: "Sleep")
        case "Strain":   return String(localized: "Strain")
        case "Health":   return String(localized: "Health")
        default:         return c
        }
    }

    /// Constructor corto del catálogo: los valores más comunes (0 decimales, sin dirección buena) van
    /// por omisión, así cada fila sólo dice lo que la distingue.
    private static func metric(_ key: String, _ title: String, _ category: String,
                               unit: String, _ source: String, icon: String,
                               decimals: Int = 0, higherIsBetter: Bool? = nil) -> MetricDescriptor {
        MetricDescriptor(key: key, title: title, category: category, unit: unit,
                         source: source, icon: icon, decimals: decimals,
                         higherIsBetter: higherIsBetter)
    }
}
