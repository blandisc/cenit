import XCTest
import CenitAnalytics
@testable import Cenit

/// FER-499 · «Un solo oráculo» (DECISIONS 2026-09-15 §1): la portada de Entrenar, el widget de la
/// pantalla de inicio y la cara del Apple Watch publican, el mismo día y con las mismas entradas, la
/// MISMA palabra. Widget y reloj tienen una función pura que devuelve lo que publican; la portada dibuja
/// el oráculo como pase directo (su vista `some View` no es unit-testeable, así que su defensa es ser un
/// pase directo + la regla compartida `esPrimerUsoSinPlan` que este archivo sí prueba). Cubre además que
/// el consejo del caso sin Salud viaja al widget (`advice`), para que no vuelva a colgar la coma sola
/// (revisión adversarial FER-499 #1, QA D1).
@MainActor
final class OraculoUnicoTests: XCTestCase {

    private struct Caso {
        let nombre: String
        let prep: Preparedness.Read?
        let fullyLoaded: Bool
        let health: Bool
        let hasPlan: Bool
        let primerUso: Bool
    }

    private func read(_ verdict: Preparedness.Verdict) -> Preparedness.Read {
        Preparedness.Read(
            verdict: verdict,
            drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: 0.2),
                      .init(axis: .sleep, state: .inRange, orientedZ: nil)],
            signals: [], signalsPresent: 2, signalsTotal: 2,
            maturity: .trusted, autonomicNights: 30, trend: nil,
            autonomicPossible: true)
    }

    private var casos: [Caso] {
        [
            .init(nombre: "sin Salud · primer uso sin plan", prep: nil, fullyLoaded: true,
                  health: false, hasPlan: false, primerUso: true),
            .init(nombre: "sin Salud · con plan", prep: nil, fullyLoaded: true,
                  health: false, hasPlan: true, primerUso: false),
            .init(nombre: "sin Salud · veredicto viejo en el repo", prep: read(.full), fullyLoaded: true,
                  health: false, hasPlan: true, primerUso: false),
            .init(nombre: "con Salud · sin base todavía", prep: nil, fullyLoaded: true,
                  health: true, hasPlan: false, primerUso: true),
            .init(nombre: "con Salud · veredicto anclado", prep: read(.caution), fullyLoaded: true,
                  health: true, hasPlan: true, primerUso: false),
            .init(nombre: "veredicto pendiente", prep: nil, fullyLoaded: false,
                  health: true, hasPlan: true, primerUso: false),
        ]
    }

    /// La palabra del oráculo (lo que la portada dibuja tal cual) == la del snapshot del widget == la que
    /// viaja al reloj, caso por caso, incluido «nada» (nil) donde el iPhone calla a propósito.
    func testLosTresConsumidoresPublicanLaMismaPalabra() {
        for c in casos {
            let oraculo = LiquidHoyBuilder.hiloEntrenar(
                prep: c.prep, nights: c.prep?.autonomicNights ?? 0, healthConnected: c.health,
                verdictPending: c.prep == nil && !c.fullyLoaded,
                hasPlan: c.hasPlan, primerUsoSinPlan: c.primerUso)
            let widget = TrainWidgetPublisher.verdict(
                prep: c.prep, fullyLoaded: c.fullyLoaded, healthConnected: c.health,
                hasPlan: c.hasPlan, primerUsoSinPlan: c.primerUso)
            let reloj = AppModel.idleHilo(
                prep: c.prep, fullyLoaded: c.fullyLoaded, healthConnected: c.health,
                hasPlan: c.hasPlan, primerUsoSinPlan: c.primerUso)
            XCTAssertEqual(widget?.word, oraculo?.palabra, c.nombre)
            XCTAssertEqual(reloj?.palabra, oraculo?.palabra, c.nombre)
            XCTAssertEqual(reloj?.consejo, oraculo?.consejo, c.nombre)
            XCTAssertEqual(widget.map(\.tone), oraculo.map { TrainWidgetSnapshot.VerdictTone($0.tono) }, c.nombre)
        }
    }

    /// FER-499 (revisión adversarial #1/#2): la regla «primer uso sin plan» es UNA sola y compartida por
    /// las tres superficies. Un plan que existe nunca es primer uso; sin poder confirmar la semana (store
    /// caído) se trata como que hay plan, no como primer uso.
    func testPrimerUsoSinPlanEsLaMismaRegla() {
        // Sin sesión y semana vacía → primer uso.
        XCTAssertTrue(TrainWidgetPublisher.esPrimerUsoSinPlan(sessionLive: false, semanaVacia: true))
        // Con plan (semana no vacía) → NO es primer uso, aunque no haya sesión.
        XCTAssertFalse(TrainWidgetPublisher.esPrimerUsoSinPlan(sessionLive: false, semanaVacia: false))
        // Sesión viva → nunca primer uso.
        XCTAssertFalse(TrainWidgetPublisher.esPrimerUsoSinPlan(sessionLive: true, semanaVacia: true))
    }

    /// El caso que el reloj rompía antes del arreglo: sin Salud y con un plan (semana NO vacía), las tres
    /// superficies dicen «Sin Apple Salud,» — ninguna calla como si fuera primer uso.
    func testSinSaludConPlanNingunaSuperficieCallaComoPrimerUso() {
        let ausencia = String(localized: "Without Apple Health,")
        let primerUso = TrainWidgetPublisher.esPrimerUsoSinPlan(sessionLive: false, semanaVacia: false)
        XCTAssertFalse(primerUso)
        let widget = TrainWidgetPublisher.verdict(prep: nil, fullyLoaded: true, healthConnected: false,
                                                  hasPlan: true, primerUsoSinPlan: primerUso)
        let reloj = AppModel.idleHilo(prep: nil, fullyLoaded: true, healthConnected: false,
                                      hasPlan: true, primerUsoSinPlan: primerUso)
        XCTAssertEqual(widget?.word, ausencia)
        XCTAssertEqual(reloj?.palabra, ausencia)
    }

    /// QA D1: el consejo del caso sin Salud viaja en el snapshot del widget (`advice`), no solo la palabra
    /// fragmento — el widget lo pinta como segunda línea para no dejar «Sin Apple Salud,» con la coma sola.
    func testSinSaludElConsejoViajaAlWidget() {
        let consejo = String(localized: "progression uses only your routine and what you log.")
        let widget = TrainWidgetPublisher.verdict(prep: nil, fullyLoaded: true, healthConnected: false,
                                                  hasPlan: true, primerUsoSinPlan: false)
        XCTAssertEqual(widget?.advice, consejo)
        // Un veredicto normal (con Salud) también puede traer consejo, pero nunca es un fragmento colgante.
        let conSalud = TrainWidgetPublisher.verdict(prep: read(.caution), fullyLoaded: true,
                                                    healthConnected: true, hasPlan: true, primerUsoSinPlan: false)
        XCTAssertNotNil(conSalud?.word)
    }

    /// Las dos regresiones que motivaron la clase, fijadas por nombre: sin Salud y sin plan, NADIE habla;
    /// sin Salud y con plan, los tres dicen la ausencia, nunca «Conecta Apple Salud».
    func testSinSaludNadiePublicaElHiloCrudo() {
        let crudo = String(localized: "Conecta Apple Health")
        let ausencia = String(localized: "Without Apple Health,")

        XCTAssertNil(TrainWidgetPublisher.verdict(prep: nil, fullyLoaded: true, healthConnected: false,
                                                  hasPlan: false, primerUsoSinPlan: true))
        XCTAssertNil(AppModel.idleHilo(prep: nil, fullyLoaded: true, healthConnected: false,
                                       hasPlan: false, primerUsoSinPlan: true))

        let widget = TrainWidgetPublisher.verdict(prep: nil, fullyLoaded: true, healthConnected: false,
                                                  hasPlan: true, primerUsoSinPlan: false)
        let reloj = AppModel.idleHilo(prep: nil, fullyLoaded: true, healthConnected: false,
                                      hasPlan: true, primerUsoSinPlan: false)
        XCTAssertEqual(widget?.word, ausencia)
        XCTAssertEqual(reloj?.palabra, ausencia)
        XCTAssertNotEqual(widget?.word, crudo)
        XCTAssertNotEqual(reloj?.palabra, crudo)
        XCTAssertEqual(widget?.tone, .hollow)
    }
}
