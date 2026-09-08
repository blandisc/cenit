import XCTest
@testable import CenitEnsenanza

// MARK: - Tests de Novedades (épico FER-428, L2/FER-435)
//
// Entradas SINTÉTICAS: el registro real de hoy no declara ninguna `.novedad` (las del épico se
// registran al cerrarlo, FER-439), así que estos tests no dependen de él.

final class NovedadesTests: XCTestCase {
    private func funcionalidad(_ id: FuncionalidadID, novedades: [(String, Bool)]) -> Funcionalidad {
        Funcionalidad(
            id: id,
            pestana: .ajustes,
            piezas: [.ayuda(seccion: .ajustes)] + novedades.map { .novedad(version: $0.0, mayor: $0.1) },
            desde: "1.85"
        )
    }

    private var registro: [Funcionalidad] {
        [
            funcionalidad(.ajustesAyuda, novedades: [("1.90", true)]),
            funcionalidad(.ajustesNovedades, novedades: [("1.90", false)]),
            funcionalidad(.ajustesPerfil, novedades: [("1.85", false)]),
            funcionalidad(.ajustesFuentes, novedades: []),
        ]
    }

    func test_nilTodoPendiente() {
        let pendientes = Novedades.pendientes(en: registro, ultimaVista: nil)
        XCTAssertEqual(pendientes.map(\.version), ["1.90", "1.85"])
        XCTAssertEqual(pendientes[0].funcionalidades.map(\.id), [.ajustesAyuda, .ajustesNovedades])
        XCTAssertEqual(pendientes[1].funcionalidades.map(\.id), [.ajustesPerfil])
        // "" = nunca vista, igual que nil.
        XCTAssertEqual(Novedades.pendientes(en: registro, ultimaVista: "").map(\.version), ["1.90", "1.85"])
    }

    func test_soloVersionesPosterioresALaVista() {
        let pendientes = Novedades.pendientes(en: registro, ultimaVista: "1.85")
        XCTAssertEqual(pendientes.map(\.version), ["1.90"])
    }

    func test_alDiaNoHayPendientes() {
        XCTAssertTrue(Novedades.pendientes(en: registro, ultimaVista: "1.90").isEmpty)
        XCTAssertTrue(Novedades.pendientes(en: registro, ultimaVista: "2.0").isEmpty)
    }

    func test_porVersionOrdenaNumericoNoAlfabetico() {
        let registro = [
            funcionalidad(.ajustesAyuda, novedades: [("1.9", false)]),
            funcionalidad(.ajustesNovedades, novedades: [("1.100", false)]),
            funcionalidad(.ajustesPerfil, novedades: [("1.85", false)]),
        ]
        XCTAssertEqual(Novedades.porVersion(registro).map(\.version), ["1.100", "1.85", "1.9"])
    }

    func test_sinNovedadesEsVacio() {
        let registro = [funcionalidad(.ajustesFuentes, novedades: [])]
        XCTAssertTrue(Novedades.porVersion(registro).isEmpty)
        XCTAssertNil(Novedades.mayorPendiente(en: registro, ultimaVista: nil))
    }

    func test_mayorPendiente() {
        XCTAssertEqual(Novedades.mayorPendiente(en: registro, ultimaVista: nil), "1.90")
        XCTAssertEqual(Novedades.mayorPendiente(en: registro, ultimaVista: "1.85"), "1.90")
        XCTAssertNil(Novedades.mayorPendiente(en: registro, ultimaVista: "1.90"))
        // Una `.novedad` no-mayor nunca gana la tarjeta.
        let soloMenores = [funcionalidad(.ajustesPerfil, novedades: [("1.95", false)])]
        XCTAssertNil(Novedades.mayorPendiente(en: soloMenores, ultimaVista: nil))
    }

    func test_funcionalidadConDosNovedadesDeLaMismaVersionSaleUnaVez() {
        let registro = [funcionalidad(.ajustesAyuda, novedades: [("1.90", false), ("1.90", true)])]
        let versiones = Novedades.porVersion(registro)
        XCTAssertEqual(versiones.count, 1)
        XCTAssertEqual(versiones[0].funcionalidades.count, 1)
    }
}
