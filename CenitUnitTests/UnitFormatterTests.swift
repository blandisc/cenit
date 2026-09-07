import XCTest
@testable import Cenit

/// Fija los factores de conversión y la FORMA exacta de cada cadena de la capa métrico/imperial.
/// Cénit guarda todo en SI y convierte sólo para pintar: un factor equivocado aquí desplazaría en
/// silencio cada peso, distancia, estatura y temperatura de la app, sin romper nada más. Por eso
/// cada número vive aquí escrito a mano, no derivado de la implementación.
final class UnitFormatterTests: XCTestCase {

    private let tolerance = 1e-9

    // MARK: - Factores

    func testDistanceFactor() {
        XCTAssertEqual(UnitFormatter.milesPerKilometer, 0.621371, accuracy: 1e-12)
        XCTAssertEqual(UnitFormatter.kmToMiles(0), 0, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.kmToMiles(1), 0.621371, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.kmToMiles(10), 6.21371, accuracy: tolerance)
    }

    func testMassFactorAndRoundTrip() {
        XCTAssertEqual(UnitFormatter.poundsPerKilogram, 2.20462, accuracy: 1e-12)
        XCTAssertEqual(UnitFormatter.kgToPounds(1), 2.20462, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.kgToPounds(75), 165.3465, accuracy: 1e-4)
        XCTAssertEqual(UnitFormatter.poundsToKg(2.20462), 1, accuracy: tolerance)
        // Capturar un peso en libras y volver a kg no puede mover la barra.
        XCTAssertEqual(UnitFormatter.poundsToKg(UnitFormatter.kgToPounds(83.2)), 83.2, accuracy: tolerance)
    }

    func testHeightFactor() {
        XCTAssertEqual(UnitFormatter.centimetersPerInch, 2.54, accuracy: 1e-12)
        XCTAssertEqual(UnitFormatter.cmToInches(2.54), 1, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.cmToInches(30.48), 12, accuracy: tolerance)
    }

    func testTemperatureFactor() {
        XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(0), 32, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(37), 98.6, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(100), 212, accuracy: tolerance)
        // −40 es el único punto donde las dos escalas se cruzan: buen centinela de la pendiente.
        XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(-40), -40, accuracy: tolerance)
    }

    // MARK: - Distancia

    func testDistanceFromMetersMetricSwitchesToWholeMetersBelowAKilometer() {
        XCTAssertEqual(UnitFormatter.distanceFromMeters(1200, system: .metric), "1.2 km")
        XCTAssertEqual(UnitFormatter.distanceFromMeters(1000, system: .metric), "1.0 km")   // el umbral incluido
        XCTAssertEqual(UnitFormatter.distanceFromMeters(999, system: .metric), "999 m")
        XCTAssertEqual(UnitFormatter.distanceFromMeters(850, system: .metric), "850 m")
    }

    func testDistanceFromMetersImperialFallsBackToYards() {
        XCTAssertEqual(UnitFormatter.distanceFromMeters(5000, system: .imperial), "3.1 mi")
        // 100 m son 0.062 mi: por debajo de la décima de milla, «0.0 mi» no diría nada.
        XCTAssertEqual(UnitFormatter.distanceFromMeters(100, system: .imperial), "109 yd")
    }

    func testDistanceFromKilometers() {
        XCTAssertEqual(UnitFormatter.distanceFromKilometers(12.4, system: .metric), "12.4 km")
        XCTAssertEqual(UnitFormatter.distanceFromKilometers(12.4, system: .imperial), "7.7 mi")
    }

    // MARK: - Masa

    func testMassFromKilograms() {
        XCTAssertEqual(UnitFormatter.massFromKilograms(74.5, system: .metric), "74.5 kg")
        XCTAssertEqual(UnitFormatter.massFromKilograms(74.5, system: .imperial), "164.2 lb")
    }

    // MARK: - Estatura

    func testHeightFromCentimeters() {
        XCTAssertEqual(UnitFormatter.heightFromCentimeters(178, system: .metric), "178 cm")
        XCTAssertEqual(UnitFormatter.heightFromCentimeters(178, system: .imperial), "5′ 10″")
        XCTAssertEqual(UnitFormatter.heightFromCentimeters(152.4, system: .imperial), "5′ 0″")   // 60″ exactos
    }

    func testHeightRoundingCarriesIntoFeet() {
        // 182.7 cm son 71.93″: redondean a 72″, que deben cargar el pie. Nunca «5′ 12″».
        let (feet, inches) = UnitFormatter.cmToFeetInches(182.7)
        XCTAssertEqual(feet, 6)
        XCTAssertEqual(inches, 0)
    }

    // MARK: - Temperatura

    func testAbsoluteTemperature() {
        XCTAssertEqual(UnitFormatter.temperatureFromCelsius(33.4, unit: .celsius), "33.4 °C")
        XCTAssertEqual(UnitFormatter.temperatureFromCelsius(33.4, unit: .fahrenheit), "92.1 °F")
        // Cero decimales redondea al entero y conserva la etiqueta.
        XCTAssertEqual(UnitFormatter.temperatureFromCelsius(36.6, unit: .celsius, decimals: 0), "37 °C")
    }

    func testTemperatureDeltaScalesWithoutTheOffset() {
        // Una desviación de +0.6 °C son +1.1 °F: escala por 9/5, jamás suma 32.
        XCTAssertEqual(UnitFormatter.temperatureDeltaFromCelsius(0.6, unit: .celsius), "0.6 °C")
        XCTAssertEqual(UnitFormatter.temperatureDeltaFromCelsius(0.6, unit: .fahrenheit), "1.1 °F")
    }

    // MARK: - Resolución de la preferencia

    func testTemperatureOverrideResolution() {
        // Sin anulación explícita, la temperatura sigue al sistema de longitud/masa.
        XCTAssertEqual(UnitPrefs.resolveTemperature(system: .metric, override: ""), .celsius)
        XCTAssertEqual(UnitPrefs.resolveTemperature(system: .imperial, override: ""), .fahrenheit)
        // Con anulación válida, gana la anulación.
        XCTAssertEqual(UnitPrefs.resolveTemperature(system: .imperial, override: "celsius"), .celsius)
        XCTAssertEqual(UnitPrefs.resolveTemperature(system: .metric, override: "fahrenheit"), .fahrenheit)
        // Un valor guardado que ya no existe no puede dejar la app sin unidad.
        XCTAssertEqual(UnitPrefs.resolveTemperature(system: .metric, override: "kelvin"), .celsius)
    }

    func testSystemMatchingTemperature() {
        XCTAssertEqual(UnitSystem.metric.temperatureMatching, .celsius)
        XCTAssertEqual(UnitSystem.imperial.temperatureMatching, .fahrenheit)
    }

    // MARK: - Etiquetas y llaves persistidas

    func testUnitLabels() {
        XCTAssertEqual(UnitFormatter.distanceUnit(.metric), "km")
        XCTAssertEqual(UnitFormatter.distanceUnit(.imperial), "mi")
        XCTAssertEqual(UnitFormatter.massUnit(.metric), "kg")
        XCTAssertEqual(UnitFormatter.massUnit(.imperial), "lb")
        XCTAssertEqual(UnitFormatter.temperatureUnit(.celsius), "°C")
        XCTAssertEqual(UnitFormatter.temperatureUnit(.fahrenheit), "°F")
    }

    func testPersistedKeysAndRawValues() {
        // Cambiar cualquiera de las dos llaves deja huérfana la preferencia ya guardada.
        XCTAssertEqual(UnitPrefs.systemKey, "units.system")
        XCTAssertEqual(UnitPrefs.temperatureKey, "units.temperature")
        XCTAssertEqual(UnitSystem.allCases.map(\.rawValue), ["metric", "imperial"])
        XCTAssertEqual(TemperatureUnit.allCases.map(\.rawValue), ["celsius", "fahrenheit"])
    }
}
