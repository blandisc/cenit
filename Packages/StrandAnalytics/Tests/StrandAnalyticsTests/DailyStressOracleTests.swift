import XCTest
import Foundation
import StrandModels
@testable import StrandAnalytics

// DailyStressOracleTests.swift — la reja de «no se movió» del proxy diario de carga autonómica.
//
// POR QUÉ EXISTE. El 0–3 del día se GUARDA en la serie `stress` y se relee semanas después: es la
// curva del detalle, el «tiempo en calma» y la comparación contra la propia línea base. Un cambio
// que lo corra dos décimas no «afina» nada — reescribe en silencio lo que la persona ya vio y
// tuerce todas las tendencias construidas encima. Y como el archivo se reescribió entero en la sala
// limpia de FER-401, hacía falta una prueba que dijera, sin narrativa de por medio, que la
// implementación nueva responde EXACTAMENTE lo mismo que la anterior.
//
// `Resources/daily-stress-oracle.json` graba, para catorce historias sintéticas fijas y para la
// aritmética suelta, lo que el modelo respondía ANTES de la reescritura. Esta suite sostiene la
// implementación de hoy contra esas respuestas.
//
// TOLERANCIA. Cero. Cada valor viaja como el texto decimal más corto que vuelve a leerse idéntico,
// así que la recarga es exacta y cualquier diferencia es una diferencia real. Si algún día un
// cambio necesita de verdad una comparación más floja, eso se dice aquí en voz alta; no se afloja
// callando.
//
// Las entradas viven en `StressOracleInputs`, compartidas con el generador que escribió el archivo,
// para que las entradas no puedan separarse de lo grabado.
final class DailyStressOracleTests: XCTestCase {

    private var oracle: StressOracleTable!

    override func setUpWithError() throws {
        oracle = try StressOracleTable.load()
    }

    /// Compara un caso contra el archivo, token por token.
    private func expect(_ key: String, _ values: [String],
                        file: StaticString = #filePath, line: UInt = #line) {
        do {
            XCTAssertEqual(values, try oracle.tokens(key), "el caso \(key) se movió",
                           file: file, line: line)
        } catch {
            XCTFail("falta el caso \(key) en el archivo: \(error)", file: file, line: line)
        }
    }

    // MARK: - Las historias completas
    //
    // Cada escenario graba dos cosas: los escalares que la pantalla enseña (el número grande, su
    // banda, los dos deltas, el «tiempo en calma», de qué día es el ancla y si se muestra) y la
    // curva punto por punto, que es lo que se persiste.

    func testLosEscenariosNoSeMovieron() {
        for e in StressOracleInputs.escenarios() {
            let m = DailyStressModel(days: e.days, stored: e.stored,
                                     todayKey: e.todayKey, appleDays: e.appleDays)
            expect("escenario.\(e.name).escalares", StressOracleRender.escalares(m))
            expect("escenario.\(e.name).curva", StressOracleRender.curva(m))
        }
    }

    /// Una historia hecha sólo en el dispositivo debe salir IDÉNTICA con y sin el parámetro de
    /// fuentes: `appleDays` vacío es la identidad, no una variante.
    func testFuenteUnicaEsLaIdentidad() {
        let dias = StressOracleInputs.historiaCompleta()
        let hoy = StressOracleCalendar.dayKey(59)
        let conParam = DailyStressModel(days: dias, stored: [], todayKey: hoy, appleDays: [])
        let sinParam = DailyStressModel(days: dias, stored: [], todayKey: hoy)
        XCTAssertEqual(StressOracleRender.escalares(conParam), StressOracleRender.escalares(sinParam))
        XCTAssertEqual(StressOracleRender.curva(conParam), StressOracleRender.curva(sinParam))
    }

    // MARK: - La aritmética suelta

    func testCentroYDispersionNoSeMovieron() {
        for s in StressOracleInputs.series {
            let centro = StressMath.mean(s.xs)
            expect("math.mean.\(s.name)", [OracleText.of(centro)])
            expect("math.std.\(s.name)", [OracleText.of(StressMath.std(s.xs, mean: centro))])
            expect("math.stdSinCentro.\(s.name)", [OracleText.of(StressMath.std(s.xs, mean: nil))])
        }
    }

    func testCrudoNoSeMovio() {
        for c in StressOracleInputs.crudos {
            let crudo = StressMath.rawScore(rhrToday: c.rhr, meanRHR: c.meanRHR, sdRHR: c.sdRHR,
                                            hrvToday: c.hrv, meanHRV: c.meanHRV, sdHRV: c.sdHRV)
            expect("math.raw.\(c.name)", [OracleText.of(crudo),
                                          OracleText.of(StressMath.squash(crudo))])
        }
    }

    func testAplastadoNoSeMovio() {
        expect("math.squash", StressOracleInputs.paraAplastar.map {
            OracleText.of(StressMath.squash($0))
        })
    }

    func testBandasNoSeMovieron() {
        expect("bandas", StressOracleInputs.puntajes.map {
            StressOracleRender.band(StressBand(score: $0))
        })
    }

    // MARK: - La cobertura del archivo

    /// Ni un caso grabado se queda sin comparar. Sin esto, borrar una prueba dejaría el archivo
    /// verde por omisión.
    func testTodoCasoGrabadoSeComprueba() throws {
        var comprobados = Set<String>()
        for e in StressOracleInputs.escenarios() {
            comprobados.insert("escenario.\(e.name).escalares")
            comprobados.insert("escenario.\(e.name).curva")
        }
        for s in StressOracleInputs.series {
            comprobados.formUnion(["math.mean.\(s.name)", "math.std.\(s.name)",
                                   "math.stdSinCentro.\(s.name)"])
        }
        for c in StressOracleInputs.crudos { comprobados.insert("math.raw.\(c.name)") }
        comprobados.formUnion(["math.squash", "bandas"])
        XCTAssertEqual(Set(oracle.keys).subtracting(comprobados), [],
                       "hay casos en el archivo que ninguna prueba mira")
        XCTAssertEqual(comprobados.subtracting(Set(oracle.keys)), [],
                       "hay pruebas que piden casos que el archivo no trae")
    }
}
