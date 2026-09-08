import XCTest
@testable import CenitEnsenanza

// MARK: - Tests de la regla pura de los hitos (épico FER-428 · FER-436)
//
// Foundation-only, como el resto del paquete. La app persiste `inicial` por hito; aquí se simula
// esa persistencia con una variable para probar secuencias día a día.

final class HitoPuertaTests: XCTestCase {
    // MARK: 1. La tabla, caso por caso

    func test_sinInicialNiDato_espera() {
        XCTAssertEqual(HitoPuerta.decidir(inicial: nil, cruzadoAhora: nil), .esperar)
    }

    func test_sinInicialConDato_registraLoQueVe() {
        XCTAssertEqual(HitoPuerta.decidir(inicial: nil, cruzadoAhora: false), .registrarInicial(cruzado: false))
        XCTAssertEqual(HitoPuerta.decidir(inicial: nil, cruzadoAhora: true), .registrarInicial(cruzado: true))
    }

    func test_yaCruzadoAlInstalar_nunca() {
        XCTAssertEqual(HitoPuerta.decidir(inicial: true, cruzadoAhora: true), .nunca)
        XCTAssertEqual(HitoPuerta.decidir(inicial: true, cruzadoAhora: false), .nunca)
        XCTAssertEqual(HitoPuerta.decidir(inicial: true, cruzadoAhora: nil), .nunca)
    }

    func test_noCruzadoTodavia_espera() {
        XCTAssertEqual(HitoPuerta.decidir(inicial: false, cruzadoAhora: false), .esperar)
        // El dato se fue (motor sin calcular esta mañana): tampoco dispara, espera.
        XCTAssertEqual(HitoPuerta.decidir(inicial: false, cruzadoAhora: nil), .esperar)
    }

    func test_cruzaConLaVersionInstalada_dispara() {
        XCTAssertEqual(HitoPuerta.decidir(inicial: false, cruzadoAhora: true), .disparar)
    }

    // MARK: 2. Secuencias con fechas sintéticas (noche a noche)

    /// Simula lo que hace la app: guarda `inicial` cuando la regla lo pide y cuenta los disparos.
    private struct Simulacion {
        var inicial: Bool?
        var disparos = 0
        var dias: [Int] = []

        mutating func manana(noches: Int, umbral: Int) {
            let veredicto = HitoPuerta.decidir(inicial: inicial, cruzadoAhora: noches >= umbral)
            switch veredicto {
            case .registrarInicial(let cruzado): inicial = cruzado
            case .disparar: disparos += 1; dias.append(noches)
            case .nunca, .esperar: break
            }
        }
    }

    /// Alguien que instala con 1 noche y cruza la noche 4 con la versión puesta: dispara
    /// exactamente una vez, la mañana de la noche 4.
    func test_secuenciaQueCruzaLaNoche4_disparaUnaVezAlLlegar() {
        var sim = Simulacion()
        for noches in [1, 2, 3, 4] { sim.manana(noches: noches, umbral: 4) }
        XCTAssertEqual(sim.inicial, false, "la primera mañana registra «no cruzado»")
        XCTAssertEqual(sim.disparos, 1)
        XCTAssertEqual(sim.dias, [4], "dispara la mañana en que se cumple el umbral, no antes")
    }

    /// Alguien que ya tenía 40 noches al instalar: nunca ve «tu primera lectura».
    func test_secuenciaQueArrancaCruzada_nuncaDispara() {
        var sim = Simulacion()
        for noches in [40, 41, 42, 55, 90] { sim.manana(noches: noches, umbral: 4) }
        XCTAssertEqual(sim.inicial, true, "la primera mañana registra «ya cruzado»")
        XCTAssertEqual(sim.disparos, 0)
    }

    /// El dato tarda en llegar (motor sin calcular las primeras mañanas): no se registra nada
    /// hasta que existe, y entonces se registra lo que se ve.
    func test_secuenciaConDatoTardio_registraCuandoElDatoExiste() {
        var inicial: Bool?
        for cruzado in [nil, nil, false, true] as [Bool?] {
            let veredicto = HitoPuerta.decidir(inicial: inicial, cruzadoAhora: cruzado)
            if case .registrarInicial(let c) = veredicto { inicial = c }
            if cruzado == nil { XCTAssertEqual(veredicto, .esperar) }
        }
        XCTAssertEqual(inicial, false)
        XCTAssertEqual(HitoPuerta.decidir(inicial: inicial, cruzadoAhora: true), .disparar)
    }
}
