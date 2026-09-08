import XCTest
@testable import Cenit

/// FER-398 — the one-time move of the store container off the names the app shipped under before
/// (see `StorePaths.legacyFolderName` / `legacyDatabaseFileName`) onto `<AppSupport>/Cenit/cenit.sqlite`.
///
/// What actually has to hold, and what each test pins:
///   · the move carries EVERYTHING in the folder (sidecars, restore backups, `MediaCache/`);
///   · a fresh install and an already-migrated one do nothing at all;
///   · when both containers exist, the live one wins and the legacy one is left intact for rescue;
///   · a crash between the sidecar rename and the main-file rename RESUMES on the next launch —
///     which is exactly why the main file is renamed last;
///   · running it twice is a no-op the second time.
///
/// Same tmp-dir pattern as `DataBackupSwapTests`: plain files under a per-test directory, so nothing
/// touches the real Application Support.
final class StorePathsMigrationTests: XCTestCase {

    private var appSupport: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        appSupport = fm.temporaryDirectory
            .appendingPathComponent("store-paths-\(UUID().uuidString)")
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: appSupport)
    }

    // MARK: - Helpers

    private var legacyDir: URL { appSupport.appendingPathComponent(StorePaths.legacyFolderName) }
    private var newDir: URL { appSupport.appendingPathComponent(StorePaths.folderName) }

    /// Los nombres heredados salen de `StorePaths`, nunca de un literal repetido aquí: son dato en
    /// disco, y la prueba tiene que mover EXACTAMENTE lo que mueve la migración.
    private var legacyDB: String { StorePaths.legacyDatabaseFileName }

    /// `<carpeta heredada>/<archivo heredado><sufijo>` — la ruta relativa que usan los `write`.
    private func inLegacyDir(_ suffix: String = "") -> String {
        "\(StorePaths.legacyFolderName)/\(legacyDB)\(suffix)"
    }

    /// La misma pareja, pero ya dentro de la carpeta nueva: el estado a medio migrar.
    private func inNewDir(_ suffix: String = "") -> String {
        "\(StorePaths.folderName)/\(legacyDB)\(suffix)"
    }

    @discardableResult
    private func write(_ relativePath: String, _ contents: String) throws -> URL {
        let url = appSupport.appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        fm.fileExists(atPath: appSupport.appendingPathComponent(relativePath).path)
    }

    // MARK: - Paths

    /// The path helper must land inside the Cénit container, under the Cénit file name.
    func testDatabasePathIsInsideTheCenitContainer() throws {
        let path = try StorePaths.databasePath(in: appSupport)
        XCTAssertTrue(path.hasSuffix("/Cenit/cenit.sqlite"),
                      "databasePath must end in Cenit/cenit.sqlite; got \(path)")
        XCTAssertTrue(fm.fileExists(atPath: newDir.path), "it creates the container it points into")
    }

    /// `containerDirectory` is pure path arithmetic — it must not create anything.
    func testContainerDirectoryCreatesNothing() {
        _ = StorePaths.containerDirectory(in: appSupport)
        XCTAssertFalse(fm.fileExists(atPath: newDir.path))
    }

    /// The media cache hangs off the same container, so the ONE folder rename carries it too.
    func testMediaCacheLivesUnderTheContainer() throws {
        let cache = try MediaCache(container: StorePaths.containerDirectory(in: appSupport))
        let path = cache.thumbPath("An_Exercise").path
        XCTAssertTrue(path.contains("/Cenit/MediaCache/media/"),
                      "MediaCache must sit at <container>/MediaCache/media; got \(path)")
    }

    // MARK: - The move

    /// The whole folder moves in one rename: DB, both WAL sidecars, the rollback sidecar a previous
    /// restore left behind, and the downloaded media. Nothing stays behind under the old name.
    func testMovesTheWholeContainerIncludingSidecarsBackupsAndMedia() throws {
        try write(inLegacyDir(), "DB")
        try write(inLegacyDir("-wal"), "WAL")
        try write(inLegacyDir("-shm"), "SHM")
        try write("OpenWhoop/cenit-replaced-2026-09-06-101010.sqlite", "ROLLBACK")
        try write("OpenWhoop/MediaCache/media/Barbell_Bench_Press.gif", "GIF")

        let outcome = StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport)

        XCTAssertEqual(outcome, .movedFolder)
        XCTAssertFalse(fm.fileExists(atPath: legacyDir.path), "the legacy folder is gone, not copied")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-shm")), "SHM")
        XCTAssertTrue(exists("Cenit/cenit-replaced-2026-09-06-101010.sqlite"),
                      "a restore's rollback sidecar rides along — it is someone's only copy")
        XCTAssertEqual(try read(newDir.appendingPathComponent("MediaCache/media/Barbell_Bench_Press.gif")), "GIF")
        XCTAssertFalse(exists(inNewDir()), "the legacy file name must not survive the move")
    }

    /// Fresh install: neither container exists. The migration must not create one.
    func testFreshInstallDoesNothing() {
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .nothingToDo)
        XCTAssertFalse(fm.fileExists(atPath: newDir.path))
        XCTAssertFalse(fm.fileExists(atPath: legacyDir.path))
    }

    /// Already migrated: the new DB is there and no legacy folder is left.
    func testAlreadyMigratedIsReported() throws {
        try write("Cenit/cenit.sqlite", "DB")
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated)
    }

    /// Both containers exist — the live one wins and the legacy one is NOT touched. Someone can still
    /// rescue it by hand; deleting it here would destroy the only copy of a history we failed to move.
    func testBothContainersKeepsBothAndTheNewOneWins() throws {
        try write("Cenit/cenit.sqlite", "NEW")
        try write(inLegacyDir(), "OLD")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .keptBothNewWins)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "NEW",
                       "the live database is never overwritten by the legacy one")
        XCTAssertEqual(try read(legacyDir.appendingPathComponent(legacyDB)), "OLD",
                       "the legacy container is left exactly as it was")
    }

    /// Ronda 2 · D8. `Cenit/` existe pero VACÍA (una primera corrida interrumpida, o un helper de ruta
    /// que la creó) y `OpenWhoop/` tiene los datos de verdad. El rename atómico no puede correr —el
    /// destino está ocupado— y antes de esto la migración devolvía `.nothingToDo`: la app abría en
    /// blanco con el historial completo del usuario intacto y invisible a un directorio de distancia.
    func testMergesIntoAnExistingButEmptyContainer() throws {
        try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        try write(inLegacyDir(), "DB")
        try write(inLegacyDir("-wal"), "WAL")
        try write(inLegacyDir("-shm"), "SHM")
        try write("OpenWhoop/cenit-replaced-2026-09-06-101010.sqlite", "ROLLBACK")
        try write("OpenWhoop/MediaCache/media/Barbell_Bench_Press.gif", "GIF")

        let outcome = StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport)

        XCTAssertEqual(outcome, .mergedIntoExisting)
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB",
                       "el historial tiene que quedar donde la app lo abre")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-shm")), "SHM")
        XCTAssertTrue(exists("Cenit/cenit-replaced-2026-09-06-101010.sqlite"),
                      "el sidecar de rollback viaja igual que en el rename de carpeta")
        XCTAssertEqual(try read(newDir.appendingPathComponent("MediaCache/media/Barbell_Bench_Press.gif")), "GIF")
        XCTAssertFalse(exists(inNewDir()), "el nombre viejo no sobrevive")
        XCTAssertFalse(fm.fileExists(atPath: legacyDir.path),
                       "la cáscara vacía se retira; si no, cada arranque reportaría keptBothNewWins")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated,
                       "y el segundo arranque no vuelve a mover nada")
    }

    /// La mezcla NUNCA pisa: un archivo que ya está en `Cenit/` gana y su tocayo heredado se queda
    /// para rescate a mano. La base sí falta, así que esa sí entra.
    func testMergeNeverOverwritesWhatIsAlreadyThere() throws {
        try write("Cenit/MediaCache/media/Barbell_Bench_Press.gif", "NEW-GIF")
        try write(inLegacyDir(), "DB")
        try write("OpenWhoop/MediaCache/media/Barbell_Bench_Press.gif", "OLD-GIF")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .mergedIntoExisting)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("MediaCache/media/Barbell_Bench_Press.gif")),
                       "NEW-GIF", "lo que ya estaba manda")
        XCTAssertEqual(try read(legacyDir.appendingPathComponent("MediaCache/media/Barbell_Bench_Press.gif")),
                       "OLD-GIF", "y lo que no cupo se queda para rescate, no se borra")
    }

    /// El `Cenit/` existente ya trae el archivo con el nombre heredado (una corrida que murió entre el rename de carpeta y
    /// el del archivo) Y además quedó un `OpenWhoop/`. Manda el reanudado: la base que ya está adentro
    /// es la más reciente. La heredada de afuera se conserva intacta.
    func testAnInterruptedRenameWinsOverAStrayLegacyFolder() throws {
        try write(inNewDir(), "INSIDE")
        try write(inLegacyDir(), "OUTSIDE")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .resumedRenames)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "INSIDE")
        XCTAssertEqual(try read(legacyDir.appendingPathComponent(legacyDB)), "OUTSIDE",
                       "la carpeta heredada sobrante no se toca")
    }

    /// The crash that the sidecar-first / main-file-last order exists for: the process died after the
    /// `-wal` rename and before the main file's. The next launch has to finish the job, not stall.
    func testResumesAfterACrashBetweenTheSidecarAndTheMainFile() throws {
        try write(inNewDir(), "DB")            // main file NOT renamed yet
        try write("Cenit/cenit.sqlite-wal", "WAL")       // sidecar already renamed
        try write(inNewDir("-shm"), "SHM")       // this one still pending

        let outcome = StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport)

        XCTAssertEqual(outcome, .resumedRenames)
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL",
                       "the already-renamed sidecar is left alone, not clobbered")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-shm")), "SHM")
        XCTAssertFalse(exists(inNewDir()))
    }

    /// It runs on EVERY launch, so the second run has to be a no-op with the data untouched.
    func testIsIdempotent() throws {
        try write(inLegacyDir(), "DB")
        try write(inLegacyDir("-wal"), "WAL")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .movedFolder)
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated)
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL")
    }
}
