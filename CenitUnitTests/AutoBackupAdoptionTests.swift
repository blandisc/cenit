import XCTest
@testable import Cenit

/// FER-398 · ronda 2 (D7) — el respaldo automático en iCloud Drive cambió de nombre:
/// `NOOP-backup.sqlite` → `Cenit-backup.sqlite`.
///
/// El riesgo no es el nombre: es la **rotación**. Una carpeta configurada antes de FER-398 ya tiene el
/// archivo viejo dentro. Si el respaldo nuevo se escribiera al lado, esa copia quedaría congelada para
/// siempre y, en el selector de restaurar, sería indistinguible de la viva — el usuario podría
/// restaurar meses de retraso creyendo que toma la última. Por eso `writeCopy` ADOPTA el archivo
/// viejo (lo renombra a su lugar) antes de rotar, y sigue el mismo linaje en vez de bifurcarlo.
final class AutoBackupAdoptionTests: XCTestCase {

    private var folder: URL!
    private let fm = FileManager.default

    private var dest: URL { folder.appendingPathComponent("Cenit-backup.sqlite") }
    private var prev: URL { folder.appendingPathComponent("Cenit-backup.sqlite.prev") }
    private var legacy: URL { folder.appendingPathComponent("NOOP-backup.sqlite") }
    private var legacyPrev: URL { folder.appendingPathComponent("NOOP-backup.sqlite.prev") }

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("auto-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: folder)
    }

    @discardableResult
    private func write(_ url: URL, _ contents: String) throws -> URL {
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func backUp(db: URL) {
        let error = AutoBackup.writeCopy(db: db, to: dest, keepingPrev: prev,
                                         adopting: legacy, adoptingPrev: legacyPrev)
        XCTAssertNil(error, "el respaldo no debió fallar: \(String(describing: error))")
    }

    /// El ciclo completo sobre una carpeta que viene del nombre anterior: al terminar existe
    /// `Cenit-backup.sqlite` con los datos de hoy, el archivo viejo NO se perdió (bajó a `.prev`) y no
    /// queda ningún `NOOP-backup*` suelto que el selector de restaurar pueda confundir.
    func testAdoptsTheLegacyBackupInsteadOfLeavingItBeside() throws {
        let db = try write(folder.appendingPathComponent("cenit.sqlite"), "HOY")
        try write(legacy, "AYER")

        backUp(db: db)

        XCTAssertEqual(try read(dest), "HOY", "el respaldo vivo lleva el nombre nuevo y los datos de hoy")
        XCTAssertEqual(try read(prev), "AYER",
                       "el respaldo anterior no se pierde: la adopción lo puso en el linaje y la rotación lo bajó a .prev")
        XCTAssertFalse(fm.fileExists(atPath: legacy.path),
                       "y no queda un segundo SQLite congelado junto al vivo")
    }

    /// La copia de rollback del nombre viejo también se adopta: si no, `NOOP-backup.sqlite.prev` se
    /// quedaría en la carpeta para siempre como un tercer archivo indistinguible.
    func testAdoptsTheLegacyRollbackCopyToo() throws {
        let db = try write(folder.appendingPathComponent("cenit.sqlite"), "HOY")
        try write(legacyPrev, "ANTEAYER")

        backUp(db: db)

        XCTAssertEqual(try read(dest), "HOY")
        XCTAssertEqual(try read(prev), "ANTEAYER",
                       "sin respaldo vivo que rotar, la copia de rollback vieja ocupa el lugar de .prev")
        XCTAssertFalse(fm.fileExists(atPath: legacyPrev.path), "no queda huérfano con el nombre viejo")
    }

    /// Una carpeta ya migrada no vuelve a adoptar nada, y la rotación sigue siendo la de siempre:
    /// el respaldo de ayer baja a `.prev` y el de hoy ocupa el nombre vivo.
    func testOnAnAlreadyMigratedFolderItJustRotates() throws {
        let db = try write(folder.appendingPathComponent("cenit.sqlite"), "HOY")
        try write(dest, "AYER")
        try write(prev, "ANTEAYER")

        backUp(db: db)

        XCTAssertEqual(try read(dest), "HOY")
        XCTAssertEqual(try read(prev), "AYER", "la rotación de siempre: hoy manda, ayer baja a .prev")
    }

    /// El archivo vivo gana sobre el heredado: si ambos nombres existen, el nuevo NO se pisa con el
    /// viejo — adoptarlo ahí habría hecho retroceder el respaldo del usuario.
    func testALiveBackupIsNeverOverwrittenByTheLegacyOne() throws {
        let db = try write(folder.appendingPathComponent("cenit.sqlite"), "HOY")
        try write(dest, "AYER")
        try write(legacy, "VIEJISIMO")

        backUp(db: db)

        XCTAssertEqual(try read(dest), "HOY")
        XCTAssertEqual(try read(prev), "AYER", "rota el vivo, no el heredado")
        XCTAssertEqual(try read(legacy), "VIEJISIMO",
                       "el heredado se queda para rescate a mano; nunca pisa una copia más reciente")
    }
}
