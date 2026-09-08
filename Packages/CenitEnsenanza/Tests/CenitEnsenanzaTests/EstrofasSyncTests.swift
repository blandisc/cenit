import XCTest
@testable import CenitEnsenanza

// MARK: - Tests de la regla de las estrofas (épico FER-428, L8/FER-437 · D1 · qa r1)
//
// Foundation-only, como el resto del paquete: la regla no sabe de SwiftUI ni de HealthKit. Los
// fixtures son los REALISTAS del qa, no los mansos: cada etapa trae lo que traería un iPhone de
// verdad (el HRV diurno del Watch sin noches, la energía activa del día sin entrenos), y la estrofa
// solo se gana si el ANCLA del grupo trajo filas. Además: las cuatro en orden, `saving` vacío, un
// grupo a medias, el orden de salida es el del enum y no el de llegada, y la última clave manda.

final class EstrofasSyncTests: XCTestCase {

    /// Un iPhone típico con Watch, 180 días: todo trae filas. Cada test sobreescribe UN grupo.
    private static let tipico: [String: Int] = [
        "resting_hr": 180,
        "sleep": 12, "hrv": 30, "skin_temp": 12, "resp_rate": 12,
        "workouts": 3, "hr_apple_workouts": 900, "active_kcal": 180,
        "saving": 2_400,
    ]

    /// Todas las claves de todos los grupos, terminadas, con las filas del típico salvo `cambios`.
    private func fixture(_ cambios: [String: Int] = [:]) -> [(clave: String, filas: Int)] {
        EstrofaSync.allCases
            .flatMap { EstrofasSync.grupos[$0]?.etapas ?? [] }
            .map { (clave: $0, filas: cambios[$0] ?? Self.tipico[$0] ?? 0) }
    }

    // MARK: 1. corazón + noches + entrenos con filas → las cuatro, en orden

    func test_conCorazonNochesYEntrenosSalenLasCuatroEnOrden() {
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: fixture()),
            [.corazon, .noches, .entrenos, .guardado]
        )
    }

    // MARK: 2. entrenos: manda `workouts`, no la energía activa

    /// (a) Un iPhone sin un solo entreno registrado sigue trayendo energía activa todos los días:
    /// eso NO es un entreno y no gana «Tus entrenamientos».
    func test_energiaActivaSinEntrenosNoSaleEntrenos() {
        let t = fixture(["workouts": 0, "hr_apple_workouts": 0, "active_kcal": 180])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .guardado])
    }

    /// (d) Tres entrenos sin energía activa ni FC de entreno (un reloj de terceros) SÍ los ganan.
    func test_entrenosSinEnergiaActivaSiSaleEntrenos() {
        let t = fixture(["workouts": 3, "hr_apple_workouts": 0, "active_kcal": 0])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .entrenos, .guardado])
    }

    // MARK: 3. noches: manda `sleep`, no el HRV

    /// (b) El Watch mide HRV de día aunque no se duerma con él puesto: filas de HRV sin una sola
    /// noche NO ganan «Tus noches».
    func test_hrvDiurnoSinNochesNoSaleNoches() {
        let t = fixture(["hrv": 30, "sleep": 0, "skin_temp": 0, "resp_rate": 0])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .entrenos, .guardado])
    }

    /// (c) Quien duerme con reloj pero no tiene HRV, temperatura de muñeca ni respiración (un reloj
    /// viejo) SÍ gana «Tus noches»: el sueño es lo que enseña la estrofa.
    func test_nochesSinOtrasSenalesNocturnasSiSaleNoches() {
        let t = fixture(["sleep": 12, "hrv": 0, "skin_temp": 0, "resp_rate": 0])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [.corazon, .noches, .entrenos, .guardado])
    }

    // MARK: 4. `saving` con 0 filas → sin .guardado

    func test_savingConCeroFilasNoSaleGuardado() {
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: fixture(["saving": 0])), [.corazon, .noches, .entrenos])
    }

    /// Nada terminó con nada: ni una estrofa (la pantalla conserva la línea de progreso).
    func test_todoEnCeroNoSaleNinguna() {
        let cero = Dictionary(uniqueKeysWithValues: Self.tipico.keys.map { ($0, 0) })
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: fixture(cero)), [])
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: []), [])
    }

    // MARK: 5. un grupo a medias → todavía no

    func test_grupoAMediasTodaviaNo() {
        // Solo `sleep` terminó (con filas): «Tus noches» espera a hrv/skin_temp/resp_rate aunque el
        // ancla ya trajo lo suyo.
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: [(clave: "sleep", filas: 12)]), [])
        // Con `resting_hr` ya terminado, sale «Tu corazón» y noches sigue esperando.
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: [(clave: "resting_hr", filas: 180), (clave: "sleep", filas: 12)]),
            [.corazon]
        )
        // Una etapa que terminó con CERO no es lo mismo que una que no terminó: cierra el grupo.
        let cerrado: [(clave: String, filas: Int)] = [
            (clave: "sleep", filas: 12), (clave: "hrv", filas: 0),
            (clave: "skin_temp", filas: 0), (clave: "resp_rate", filas: 0),
        ]
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: cerrado), [.noches])
    }

    // MARK: 6. el orden de salida es el del enum, no el de llegada

    func test_ordenDeSalidaEsElDelEnumNoElDeLlegada() {
        // Llegan al revés: saving, entrenos, noches, corazón.
        XCTAssertEqual(
            EstrofasSync.ganadas(terminadas: Array(fixture().reversed())),
            [.corazon, .noches, .entrenos, .guardado]
        )
    }

    /// Si una clave llega dos veces (un reintento), manda la última.
    func test_claveRepetidaMandaLaUltima() {
        let t: [(clave: String, filas: Int)] = [(clave: "resting_hr", filas: 3), (clave: "resting_hr", filas: 0)]
        XCTAssertEqual(EstrofasSync.ganadas(terminadas: t), [])
    }

    // MARK: 7. invariantes de los grupos

    func test_cadaClaveViveEnUnSoloGrupoNingunGrupoEstaVacioYElAnclaEsDelGrupo() {
        var vistas: [String: EstrofaSync] = [:]
        for estrofa in EstrofaSync.allCases {
            guard let grupo = EstrofasSync.grupos[estrofa] else { return XCTFail("\(estrofa) no tiene grupo") }
            XCTAssertFalse(grupo.etapas.isEmpty, "\(estrofa) no tiene etapas")
            XCTAssertTrue(grupo.etapas.contains(grupo.ancla), "el ancla \(grupo.ancla) de \(estrofa) no está en su grupo")
            for clave in grupo.etapas {
                XCTAssertNil(vistas[clave], "\(clave) está en \(estrofa) y en \(vistas[clave]!)")
                vistas[clave] = estrofa
            }
        }
    }
}
