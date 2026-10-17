import XCTest
@testable import CenitTraining

/// La única señal de salud de Cénit Fuerza: sueño corto o pulso en reposo alto retienen la subida.
final class ComoAmanecisteTests: XCTestCase {
    private let base = [56.0, 55, 57, 56, 58, 54, 56]   // mediana 56

    func test_sinNingunDato_sinDato_yPermiteSubida() {
        let l = ComoAmaneciste.leer(sueñoMin: nil, pulsoHoy: nil, pulsoBase: [])
        XCTAssertEqual(l, .sinDato)
        XCTAssertTrue(l.permiteSubida, "sin dato no se opina: el plan corre como está")
    }

    func test_sueñoCorto_retiene() {
        let l = ComoAmaneciste.leer(sueñoMin: 310, pulsoHoy: 56, pulsoBase: base)
        XCTAssertEqual(l, .sueñoCorto(minutos: 310))
        XCTAssertFalse(l.permiteSubida)
    }

    func test_seisHorasJustas_noEsCorto() {
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: 360, pulsoHoy: nil, pulsoBase: []), .enRango)
    }

    func test_pulsoSieteArribaDeLaMediana_retiene() {
        let l = ComoAmaneciste.leer(sueñoMin: 450, pulsoHoy: 63, pulsoBase: base)
        XCTAssertEqual(l, .pulsoAlto(hoy: 63, base: 56))
        XCTAssertFalse(l.permiteSubida)
    }

    func test_pulsoSeisArriba_enRango() {
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: 450, pulsoHoy: 62, pulsoBase: base), .enRango)
    }

    func test_sueñoCortoMandaSobrePulsoAlto() {
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: 300, pulsoHoy: 70, pulsoBase: base),
                       .sueñoCorto(minutos: 300))
    }

    func test_baseCorta_noJuzgaElPulso() {
        // Seis días no alcanzan para una mediana tuya: el pulso alto no se puede afirmar.
        let corta = Array(base.prefix(6))
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: nil, pulsoHoy: 80, pulsoBase: corta), .sinDato)
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: 420, pulsoHoy: 80, pulsoBase: corta), .enRango)
    }

    func test_ceroEsSinDato_noSueñoCorto() {
        // HealthKit sin noche registrada puede llegar como 0: no es «dormiste 0 h».
        XCTAssertEqual(ComoAmaneciste.leer(sueñoMin: 0, pulsoHoy: nil, pulsoBase: []), .sinDato)
    }

    func test_mediana_robustaAUnaNocheRara() {
        XCTAssertEqual(ComoAmaneciste.mediana([56, 55, 57, 90, 56, 54, 56]), 56)
        XCTAssertEqual(ComoAmaneciste.mediana([50, 60]), 55)
    }
}
