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

    // MARK: 3. Mapeo de la lectura de Hoy → elegibilidad (HitoHoy · FER-436 · qa r1)

    /// (a) Sin historia (pase completo sobre store vacío antes del onboarding): ambos `nil` —el
    /// dato está ausente, no es «umbral no cruzado».
    func test_hoy_sinHistoria_ambosNil() {
        let e = HitoHoy.elegibilidad(hayHistoria: false, hayVeredicto: false, sinReloj: false,
                                     autonomicNights: 0, seed: 4, trust: 14)
        XCTAssertNil(e.primeraLectura)
        XCTAssertNil(e.baseFirme)
    }

    /// (b) Con historia pero 0 noches todavía: ambos `false` (con historia, aún no cruza).
    func test_hoy_conHistoriaCeroNoches_ambosFalse() {
        let e = HitoHoy.elegibilidad(hayHistoria: true, hayVeredicto: false, sinReloj: false,
                                     autonomicNights: 0, seed: 4, trust: 14)
        XCTAssertEqual(e.primeraLectura, false)
        XCTAssertEqual(e.baseFirme, false)
    }

    /// (c) 40 noches, con veredicto y reloj: ambos `true`.
    func test_hoy_cuarentaNoches_ambosTrue() {
        let e = HitoHoy.elegibilidad(hayHistoria: true, hayVeredicto: true, sinReloj: false,
                                     autonomicNights: 40, seed: 4, trust: 14)
        XCTAssertEqual(e.primeraLectura, true)
        XCTAssertEqual(e.baseFirme, true)
    }

    /// (d) 4 noches con veredicto y reloj: primera lectura `true`, base firme aún `false`.
    func test_hoy_cuatroNoches_primeraSiBaseNo() {
        let e = HitoHoy.elegibilidad(hayHistoria: true, hayVeredicto: true, sinReloj: false,
                                     autonomicNights: 4, seed: 4, trust: 14)
        XCTAssertEqual(e.primeraLectura, true)
        XCTAssertEqual(e.baseFirme, false)
    }

    /// D2: base firme exige reloj. 14 noches SIN lectura de anoche (sinReloj) no saca «Base firme».
    func test_hoy_baseFirmeExigeReloj() {
        let e = HitoHoy.elegibilidad(hayHistoria: true, hayVeredicto: false, sinReloj: true,
                                     autonomicNights: 14, seed: 4, trust: 14)
        XCTAssertEqual(e.primeraLectura, false)
        XCTAssertEqual(e.baseFirme, false)
    }

    // MARK: 4. La secuencia exacta del qa: store vacío → primer sync de 180 días

    /// Reproduce el defecto D1: la PRIMERA evaluación corre sobre un store vacío (sin historia,
    /// `nil` → HitoPuerta espera, NO registra `false`); el primer sync trae 40 noches ya cruzadas
    /// → `registrarInicial(true)`, que NO dispara. Nadie con 179 noches recibe «Base firme».
    func test_secuenciaStoreVacioLuego40Noches_noDispara() {
        var inicialPrimera: Bool?
        var inicialBase: Bool?
        var disparosPrimera = 0
        var disparosBase = 0

        func paso(hayHistoria: Bool, hayVeredicto: Bool, sinReloj: Bool, noches: Int) {
            let e = HitoHoy.elegibilidad(hayHistoria: hayHistoria, hayVeredicto: hayVeredicto,
                                         sinReloj: sinReloj, autonomicNights: noches,
                                         seed: 4, trust: 14)
            switch HitoPuerta.decidir(inicial: inicialPrimera, cruzadoAhora: e.primeraLectura) {
            case .registrarInicial(let c): inicialPrimera = c
            case .disparar: disparosPrimera += 1
            case .nunca, .esperar: break
            }
            switch HitoPuerta.decidir(inicial: inicialBase, cruzadoAhora: e.baseFirme) {
            case .registrarInicial(let c): inicialBase = c
            case .disparar: disparosBase += 1
            case .nunca, .esperar: break
            }
        }

        // 1) pase completo sobre store VACÍO (lo que hacía el pase full pre-onboarding)
        paso(hayHistoria: false, hayVeredicto: false, sinReloj: false, noches: 0)
        XCTAssertNil(inicialPrimera, "sin historia no se registra nada")
        XCTAssertNil(inicialBase)
        // 2) primer sync de 180 días: 179 noches, ya cruzadas
        paso(hayHistoria: true, hayVeredicto: true, sinReloj: false, noches: 179)
        XCTAssertEqual(inicialPrimera, true, "se registra «ya cruzado», no dispara")
        XCTAssertEqual(inicialBase, true)
        // 3) mañanas siguientes
        paso(hayHistoria: true, hayVeredicto: true, sinReloj: false, noches: 180)
        XCTAssertEqual(disparosPrimera, 0)
        XCTAssertEqual(disparosBase, 0)
    }
}

