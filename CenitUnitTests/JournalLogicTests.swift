import CenitStore
import XCTest
@testable import Cenit

/// Fija cómo se funden la bitácora y su catálogo.
///
/// Las dos reglas que se prueban aquí sostienen una sola promesa: la pregunta es la llave de unión
/// del motor de conductas, así que fundir dos orígenes no puede perder respuestas ni partir una
/// conducta en dos por una diferencia de mayúsculas.
@MainActor
final class JournalLogicTests: XCTestCase {

    private func entrada(_ dia: String, _ pregunta: String, _ si: Bool) -> JournalEntry {
        JournalEntry(day: dia, question: pregunta, answeredYes: si, notes: nil)
    }

    // MARK: - Repository.mergeJournal

    func testLaRespuestaNativaGanaCuandoChocaConLaImportada() {
        let dia = "2026-06-09"
        let pregunta = "Did you drink any alcohol?"
        let fusionadas = Repository.mergeJournal(
            imported: [entrada(dia, pregunta, false)],
            native: [entrada(dia, pregunta, true)]
        )

        XCTAssertEqual(fusionadas.count, 1, "día + pregunta es una sola llave")
        XCTAssertEqual(fusionadas.first?.answeredYes, true, "gana lo que el usuario respondió aquí")
    }

    func testLlavesDistintasSeUnenYSalenOrdenadasPorDiaYPregunta() {
        let fusionadas = Repository.mergeJournal(
            imported: [entrada("2026-06-09", "B?", true)],
            native: [entrada("2026-06-10", "A?", false), entrada("2026-06-09", "A?", true)]
        )

        XCTAssertEqual(fusionadas.count, 3, "sin colisión no se pierde nada")
        // Día ascendente y, dentro del día, pregunta ascendente: el mismo orden en que lee la base,
        // para que la pantalla no tenga que reordenar.
        XCTAssertEqual(fusionadas.map(\.day), ["2026-06-09", "2026-06-09", "2026-06-10"])
        XCTAssertEqual(fusionadas.map(\.question), ["A?", "B?", "A?"])
    }

    // MARK: - JournalCatalogStore.mergeCatalog

    func testElCatalogoAdoptaLaGrafiaDeLaPreguntaImportada() {
        let importada = "DID YOU DRINK ANY ALCOHOL?"
        let catalogo = JournalCatalogStore.mergeCatalog(imported: [importada], custom: [])

        XCTAssertEqual(catalogo.first, importada, "la importada manda y va al frente")
        // La de arranque equivalente se cayó por deduplicación sin distinguir mayúsculas: quedan
        // nueve de arranque más la importada, así que el total no se mueve.
        XCTAssertEqual(catalogo.count, JournalCatalogStore.starterQuestions.count)
    }

    func testLasPropiasSeAgreganAlFinalYLoVacioSeDescarta() {
        let catalogo = JournalCatalogStore.mergeCatalog(
            imported: [],
            custom: ["  ", "Did you nap?", "did you NAP?"]
        )

        XCTAssertEqual(Array(catalogo.prefix(JournalCatalogStore.starterQuestions.count)),
                       JournalCatalogStore.starterQuestions,
                       "las de arranque conservan texto y orden")
        XCTAssertEqual(catalogo.last, "Did you nap?", "gana la primera grafía escrita")
        XCTAssertEqual(catalogo.count, JournalCatalogStore.starterQuestions.count + 1,
                       "el espacio en blanco se descarta y la repetida no suma")
    }
}
