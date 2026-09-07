import XCTest
@testable import CenitEnsenanza

// MARK: - Tests de la regla de las estrofas (épico FER-428, L8/FER-437 · D1)
//
// Foundation-only, como el resto del paquete: la regla no sabe de SwiftUI ni de HealthKit. Los
// casos son los del spec: las cuatro en orden, sin entrenos, sin noches, `saving` vacío, un grupo a
// medias, y el orden de salida es el del enum y no el de llegada.

final class EstrofasSyncTests: XCTestCase {

    private static let entrenos = ["workouts", "hr_apple_workouts", "active_kcal"]
    private static let noches = ["sleep", "hrv", "skin_temp", "resp_rate"]

    /// Todas las claves de todos los grupos, con las filas que decida `filas(clave)`.
    private func todas(_ filas: (String) -> Int) -> [(clave: String, filas: Int)] {
        EstrofaSync.allCases
            .flatMap { EstrofasSync.grupos[$0] ?? [] }
            .map { (clave: $0, filas: filas($0)) }
    }

    // MARK: 1. corazón + noches + entrenos con filas → las cuatro, en orden

    func test_conCorazonNochesYEntrenosSalenLasCuatroEnOrden() {
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: todas { _ in 3 }),
            [.corazon, .noches, .entrenos, .guardado]
        )
    }

    // MARK: 2. sin entrenos (filas 0 en las tres) → sin .entrenos

    func test_sinEntrenosNoSaleEntrenos() {
        let t = todas { Self.entrenos.contains($0) ? 0 : 3 }
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .guardado])
    }

    // MARK: 3. sin señales nocturnas → sin .noches

    func test_sinSenalesNocturnasNoSaleNoches() {
        let t = todas { Self.noches.contains($0) ? 0 : 3 }
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .entrenos, .guardado])
    }

    /// Basta con que UNA etapa del grupo traiga filas: quien duerme con reloj pero no tiene
    /// temperatura de muñeca sigue ganando «Tus noches».
    func test_unaSolaEtapaDelGrupoConFilasBasta() {
        let t = todas { $0 == "hrv" ? 5 : ($0 == "resting_hr" || $0 == "saving" ? 1 : 0) }
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .guardado])
    }

    // MARK: 4. `saving` con 0 filas → sin .guardado

    func test_savingConCeroFilasNoSaleGuardado() {
        let t = todas { $0 == "saving" ? 0 : 3 }
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .entrenos])
    }

    /// Nada terminó con nada: ni una estrofa (la pantalla conserva la línea de progreso).
    func test_todoEnCeroNoSaleNinguna() {
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: todas { _ in 0 }), [])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: []), [])
    }

    // MARK: 5. un grupo a medias → todavía no

    func test_grupoAMediasTodaviaNo() {
        // Solo `sleep` terminó (con filas): «Tus noches» espera a hrv/skin_temp/resp_rate.
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: [(clave: "sleep", filas: 40)]), [])
        // Con `resting_hr` ya terminado, sale «Tu corazón» y noches sigue esperando.
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: [(clave: "resting_hr", filas: 90), (clave: "sleep", filas: 40)]),
            [.corazon]
        )
        // Una etapa que terminó con CERO no es lo mismo que una que no terminó: cierra el grupo.
        let cerrado: [(clave: String, filas: Int)] = [
            (clave: "sleep", filas: 40), (clave: "hrv", filas: 0),
            (clave: "skin_temp", filas: 0), (clave: "resp_rate", filas: 0),
        ]
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: cerrado), [.noches])
    }

    // MARK: 6. el orden de salida es el del enum, no el de llegada

    func test_ordenDeSalidaEsElDelEnumNoElDeLlegada() {
        // Llegan al revés: saving, entrenos, noches, corazón.
        let alReves = todas { _ in 2 }.reversed()
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: Array(alReves)),
            [.corazon, .noches, .entrenos, .guardado]
        )
    }

    /// Si una clave llega dos veces (un reintento), manda la última.
    func test_claveRepetidaMandaLaUltima() {
        let t: [(clave: String, filas: Int)] = [(clave: "resting_hr", filas: 3), (clave: "resting_hr", filas: 0)]
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [])
    }

    // MARK: 7. invariantes de los grupos

    func test_cadaClaveViveEnUnSoloGrupoYNingunGrupoEstaVacio() {
        var vistas: [String: EstrofaSync] = [:]
        for estrofa in EstrofaSync.allCases {
            let etapas = EstrofasSync.grupos[estrofa] ?? []
            XCTAssertFalse(etapas.isEmpty, "\(estrofa) no tiene etapas")
            for clave in etapas {
                XCTAssertNil(vistas[clave], "\(clave) está en \(estrofa) y en \(vistas[clave]!)")
                vistas[clave] = estrofa
            }
        }
    }
}
