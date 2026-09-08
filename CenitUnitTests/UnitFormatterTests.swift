import XCTest
@testable import Cenit

/// Fija los factores de conversión y la FORMA exacta de cada cadena de la capa métrico/imperial.
///
/// Cénit guarda todo en SI y convierte solo para pintar. Un factor equivocado aquí correría en
/// silencio cada peso, distancia, estatura y temperatura del app, sin romper una sola prueba de
/// lógica. Por eso cada número está escrito a mano abajo y nunca se deriva de la implementación.
///
/// Las tablas son a propósito: un caso nuevo es un renglón, no un método nuevo, y el mensaje de
/// fallo nombra el renglón que se cayó.
final class UnitFormatterTests: XCTestCase {

    private let tolerance = 1e-9

    // MARK: - Factores de conversión

    func testFactorDeDistancia() {
        XCTAssertEqual(UnitFormatter.milesPerKilometer, 0.621371, accuracy: 1e-12)

        for (km, millas) in [(0.0, 0.0), (1.0, 0.621371), (10.0, 6.21371)] {
            XCTAssertEqual(UnitFormatter.kmToMiles(km), millas, accuracy: tolerance, "\(km) km")
        }
    }

    func testFactorDeMasaYViajeRedondo() {
        XCTAssertEqual(UnitFormatter.poundsPerKilogram, 2.20462, accuracy: 1e-12)

        XCTAssertEqual(UnitFormatter.kgToPounds(1), 2.20462, accuracy: tolerance)
        XCTAssertEqual(UnitFormatter.kgToPounds(75), 165.3465, accuracy: 1e-4)
        XCTAssertEqual(UnitFormatter.poundsToKg(2.20462), 1, accuracy: tolerance)

        // Capturar una barra en libras y volver a kilos no puede moverle el peso.
        let ida = UnitFormatter.kgToPounds(83.2)
        XCTAssertEqual(UnitFormatter.poundsToKg(ida), 83.2, accuracy: tolerance)
    }

    func testFactorDeEstatura() {
        XCTAssertEqual(UnitFormatter.centimetersPerInch, 2.54, accuracy: 1e-12)

        for (cm, pulgadas) in [(2.54, 1.0), (30.48, 12.0)] {
            XCTAssertEqual(UnitFormatter.cmToInches(cm), pulgadas, accuracy: tolerance, "\(cm) cm")
        }
    }

    func testFactorDeTemperatura() {
        // −40 es el único punto donde las dos escalas se cruzan: buen centinela de la pendiente.
        let puntos: [(celsius: Double, fahrenheit: Double)] = [
            (0, 32), (37, 98.6), (100, 212), (-40, -40),
        ]
        for punto in puntos {
            XCTAssertEqual(UnitFormatter.celsiusToFahrenheit(punto.celsius), punto.fahrenheit,
                           accuracy: tolerance, "\(punto.celsius) °C")
        }
    }

    // MARK: - Distancia, ya como texto

    func testDistanciaDesdeMetros() {
        // Debajo del kilómetro, el sistema métrico cae a metros enteros; y por debajo de la décima
        // de milla, el imperial cae a yardas, porque «0.0 mi» no diría nada.
        let casos: [(metros: Double, sistema: UnitSystem, texto: String)] = [
            (1200, .metric, "1.2 km"),
            (1000, .metric, "1.0 km"),      // el umbral, incluido
            (999, .metric, "999 m"),
            (850, .metric, "850 m"),
            (5000, .imperial, "3.1 mi"),
            (100, .imperial, "109 yd"),     // 0.062 mi
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.distanceFromMeters(caso.metros, system: caso.sistema),
                           caso.texto, "\(caso.metros) m en \(caso.sistema)")
        }
    }

    func testDistanciaDesdeKilometros() {
        let casos: [(km: Double, sistema: UnitSystem, texto: String)] = [
            (12.4, .metric, "12.4 km"),
            (12.4, .imperial, "7.7 mi"),
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.distanceFromKilometers(caso.km, system: caso.sistema),
                           caso.texto, "\(caso.km) km en \(caso.sistema)")
        }
    }

    // MARK: - Masa y estatura, ya como texto

    func testMasaDesdeKilogramos() {
        let casos: [(kg: Double, sistema: UnitSystem, texto: String)] = [
            (74.5, .metric, "74.5 kg"),
            (74.5, .imperial, "164.2 lb"),
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.massFromKilograms(caso.kg, system: caso.sistema),
                           caso.texto, "\(caso.kg) kg en \(caso.sistema)")
        }
    }

    func testEstaturaDesdeCentimetros() {
        let casos: [(cm: Double, sistema: UnitSystem, texto: String)] = [
            (178, .metric, "178 cm"),
            (178, .imperial, "5′ 10″"),
            (152.4, .imperial, "5′ 0″"),    // 60″ exactos
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.heightFromCentimeters(caso.cm, system: caso.sistema),
                           caso.texto, "\(caso.cm) cm en \(caso.sistema)")
        }
    }

    func testElRedondeoDeEstaturaCargaElPie() {
        // 182.7 cm son 71.93″, que redondean a 72″. Esas 72 pulgadas tienen que volverse un pie
        // más: nunca debe salir «5′ 12″».
        let (pies, pulgadas) = UnitFormatter.cmToFeetInches(182.7)
        XCTAssertEqual(pies, 6)
        XCTAssertEqual(pulgadas, 0)
    }

    // MARK: - Temperatura, ya como texto

    func testTemperaturaAbsoluta() {
        let casos: [(celsius: Double, unidad: TemperatureUnit, decimales: Int, texto: String)] = [
            (33.4, .celsius, 1, "33.4 °C"),
            (33.4, .fahrenheit, 1, "92.1 °F"),
            (36.6, .celsius, 0, "37 °C"),   // cero decimales redondea y conserva la etiqueta
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.temperatureFromCelsius(caso.celsius, unit: caso.unidad,
                                                                decimals: caso.decimales),
                           caso.texto, "\(caso.celsius) °C en \(caso.unidad)")
        }
    }

    func testLaDesviacionEscalaSinSumarElOrigen() {
        // Una desviación de +0.6 °C son +1.1 °F: escala por 9/5 y jamás suma los 32 grados del
        // origen, que solo aplican a una temperatura absoluta.
        let casos: [(unidad: TemperatureUnit, texto: String)] = [
            (.celsius, "0.6 °C"),
            (.fahrenheit, "1.1 °F"),
        ]
        for caso in casos {
            XCTAssertEqual(UnitFormatter.temperatureDeltaFromCelsius(0.6, unit: caso.unidad),
                           caso.texto, "desviación en \(caso.unidad)")
        }
    }

    // MARK: - Cómo se resuelve la preferencia

    func testLaAnulacionDeTemperaturaGanaYLoDesconocidoNoDejaSinUnidad() {
        let casos: [(sistema: UnitSystem, anulacion: String, esperada: TemperatureUnit)] = [
            (.metric, "", .celsius),                // sin anulación, sigue al sistema
            (.imperial, "", .fahrenheit),
            (.imperial, "celsius", .celsius),       // con anulación válida, gana la anulación
            (.metric, "fahrenheit", .fahrenheit),
            (.metric, "kelvin", .celsius),          // un valor guardado que ya no existe
        ]
        for caso in casos {
            XCTAssertEqual(UnitPrefs.resolveTemperature(system: caso.sistema, override: caso.anulacion),
                           caso.esperada, "\(caso.sistema) + «\(caso.anulacion)»")
        }
    }

    func testCadaSistemaTraeSuTemperatura() {
        XCTAssertEqual(UnitSystem.metric.temperatureMatching, .celsius)
        XCTAssertEqual(UnitSystem.imperial.temperatureMatching, .fahrenheit)
    }

    // MARK: - Etiquetas y valores persistidos

    func testEtiquetasDeUnidad() {
        XCTAssertEqual([UnitSystem.metric, .imperial].map(UnitFormatter.distanceUnit), ["km", "mi"])
        XCTAssertEqual([UnitSystem.metric, .imperial].map(UnitFormatter.massUnit), ["kg", "lb"])
        XCTAssertEqual([TemperatureUnit.celsius, .fahrenheit].map(UnitFormatter.temperatureUnit),
                       ["°C", "°F"])
    }

    func testLlavesYValoresGuardados() {
        // Mover cualquiera de estos dejaría huérfana la preferencia que ya está en el teléfono.
        XCTAssertEqual(UnitPrefs.systemKey, "units.system")
        XCTAssertEqual(UnitPrefs.temperatureKey, "units.temperature")
        XCTAssertEqual(UnitSystem.allCases.map(\.rawValue), ["metric", "imperial"])
        XCTAssertEqual(TemperatureUnit.allCases.map(\.rawValue), ["celsius", "fahrenheit"])
    }
}
