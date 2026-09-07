import Foundation

// MARK: - Preferencia de unidades
//
// Cénit guarda TODO en SI (km, kg, cm, °C): los importadores normalizan al entrar, así que esta capa
// es puramente cosmética. Voltear el interruptor no migra nada ni cambia un byte en disco.
// Longitud y masa comparten un interruptor; la temperatura tiene su propia anulación, porque mucha
// gente piensa en kg y cm y aun así lee la temperatura del cuerpo en °F (y al revés). Por omisión,
// métrico: es lo que ya guardamos y lo que usa casi todo el mundo.
//
// Se persiste con @AppStorage (UserDefaults), igual que el resto de preferencias de la app.

/// El sistema de longitud + masa. La temperatura se resuelve aparte (ver `UnitPrefs`).
enum UnitSystem: String, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    /// La unidad de temperatura que «va con» este sistema cuando no hay anulación explícita.
    var temperatureMatching: TemperatureUnit {
        switch self {
        case .metric:   return .celsius
        case .imperial: return .fahrenheit
        }
    }
}

/// Unidad de temperatura en pantalla. Vive aparte de `UnitSystem` para poder fijarla sola.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
}

/// Las dos llaves de UserDefaults y la regla que las resuelve. Ajustes (`@AppStorage`) y el
/// formateador leen de aquí, para que no existan dos cadenas escritas a mano que se separen.
enum UnitPrefs {
    /// Guarda el rawValue de `UnitSystem`.
    static let systemKey = "units.system"
    /// Guarda el rawValue de `TemperatureUnit`. Cadena vacía = «la que vaya con el sistema».
    static let temperatureKey = "units.temperature"

    /// Manda la anulación explícita si es un rawValue válido; cualquier otra cosa sigue al sistema.
    static func resolveTemperature(system: UnitSystem, override raw: String) -> TemperatureUnit {
        TemperatureUnit(rawValue: raw) ?? system.temperatureMatching
    }
}

// MARK: - Conversión y formato

/// Conversión y formato de unidades: puro, sin dependencias y sin leer UserDefaults — quien llama
/// entrega ya resuelto el sistema, lo que deja esto trivial de probar y sin efectos secundarios.
/// Es el único lugar donde viven los factores, y `UnitFormatterTests` los fija uno por uno: un
/// factor equivocado desplazaría en silencio cada peso, distancia, estatura y temperatura de la app.
enum UnitFormatter {

    // MARK: Factores (los tests fijan estos números exactos)

    /// 1 km = 0.621371 mi.
    static let milesPerKilometer = 0.621371
    /// 1 kg = 2.20462 lb.
    static let poundsPerKilogram = 2.20462
    /// 1 in = 2.54 cm, exacto por definición.
    static let centimetersPerInch = 2.54

    /// 1 m = 1.09361 yd. Sólo se usa en el tramo corto en imperial.
    private static let yardsPerMeter = 1.09361
    /// Por debajo de una décima de milla (~160 m) la distancia se cuenta en yardas: «0.0 mi» no dice nada.
    private static let yardThreshold = 0.1
    /// La pendiente de la escala Fahrenheit. El corrimiento de +32 se aplica aparte, porque una
    /// DIFERENCIA de temperatura escala pero no se corre.
    private static let fahrenheitPerCelsius = 9.0 / 5.0
    /// El cero de la escala Fahrenheit respecto a la Celsius.
    private static let fahrenheitZeroOffset = 32.0

    // MARK: Conversión pura

    static func kmToMiles(_ km: Double) -> Double { km * milesPerKilometer }

    static func kgToPounds(_ kg: Double) -> Double { kg * poundsPerKilogram }

    static func poundsToKg(_ lb: Double) -> Double { lb / poundsPerKilogram }

    static func cmToInches(_ cm: Double) -> Double { cm / centimetersPerInch }

    static func celsiusToFahrenheit(_ c: Double) -> Double {
        c * fahrenheitPerCelsius + fahrenheitZeroOffset
    }

    // MARK: Distancia (los entrenamientos llegan en metros; los totales, en km)

    /// Métrico: «1.2 km» a partir de un kilómetro, «850 m» por debajo.
    /// Imperial: «3.1 mi» a partir de una décima de milla, «109 yd» por debajo.
    static func distanceFromMeters(_ meters: Double, system: UnitSystem) -> String {
        let km = meters / 1000.0
        switch system {
        case .metric:
            guard km >= 1 else { return measure(meters, decimals: 0, "m") }
            return measure(km, decimals: 1, "km")
        case .imperial:
            let miles = kmToMiles(km)
            guard miles >= yardThreshold else {
                return measure(meters * yardsPerMeter, decimals: 0, "yd")
            }
            return measure(miles, decimals: 1, "mi")
        }
    }

    /// Un decimal siempre: «12.4 km» / «7.7 mi».
    static func distanceFromKilometers(_ km: Double, system: UnitSystem) -> String {
        measure(system == .imperial ? kmToMiles(km) : km, decimals: 1, distanceUnit(system))
    }

    /// Sólo la etiqueta, para quien arma el número por su cuenta.
    static func distanceUnit(_ system: UnitSystem) -> String {
        system == .imperial ? "mi" : "km"
    }

    // MARK: Masa (se guarda en kg)

    /// Un decimal siempre: «74.5 kg» / «164.2 lb».
    static func massFromKilograms(_ kg: Double, system: UnitSystem) -> String {
        measure(system == .imperial ? kgToPounds(kg) : kg, decimals: 1, massUnit(system))
    }

    static func massUnit(_ system: UnitSystem) -> String {
        system == .imperial ? "lb" : "kg"
    }

    // MARK: Estatura (se guarda en cm)

    /// Pulgadas enteras repartidas en pies y pulgadas. Se redondea ANTES de repartir, así que un
    /// 11.5″ que sube a 12″ carga el pie por sí solo: nunca sale «5′ 12″».
    static func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int(cmToInches(cm).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    /// Métrico: «178 cm». Imperial: «5′ 10″».
    static func heightFromCentimeters(_ cm: Double, system: UnitSystem) -> String {
        switch system {
        case .metric:
            return measure(cm, decimals: 0, "cm")
        case .imperial:
            let (feet, inches) = cmToFeetInches(cm)
            // Prima y doble prima: los glifos convencionales de pie y pulgada, legibles en chico.
            return "\(feet)′ \(inches)″"
        }
    }

    // MARK: Temperatura (se guarda en °C)

    /// Una temperatura ABSOLUTA: «33.4 °C» / «92.1 °F».
    static func temperatureFromCelsius(_ c: Double, unit: TemperatureUnit, decimals: Int = 1) -> String {
        let value = unit == .fahrenheit ? celsiusToFahrenheit(c) : c
        return measure(value, decimals: decimals, temperatureUnit(unit))
    }

    /// Una DESVIACIÓN (±Δ°C, como la de temperatura de piel): escala por 9/5 y nada más. Sumarle
    /// el corrimiento de +32 convertiría una diferencia en una temperatura absoluta.
    static func temperatureDeltaFromCelsius(_ dc: Double, unit: TemperatureUnit, decimals: Int = 1) -> String {
        let value = unit == .fahrenheit ? dc * fahrenheitPerCelsius : dc
        return measure(value, decimals: decimals, temperatureUnit(unit))
    }

    static func temperatureUnit(_ unit: TemperatureUnit) -> String {
        unit == .fahrenheit ? "°F" : "°C"
    }

    // MARK: Armado de la cadena

    /// Número + espacio + etiqueta: la forma que usa toda la app.
    private static func measure(_ value: Double, decimals: Int, _ unit: String) -> String {
        number(value, decimals: decimals) + " " + unit
    }

    /// Cero decimales imprime el entero redondeado; de ahí en adelante, decimales fijos.
    private static func number(_ value: Double, decimals: Int) -> String {
        decimals <= 0 ? String(Int(value.rounded())) : String(format: "%.\(decimals)f", value)
    }
}
