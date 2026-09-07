import XCTest
@testable import Cenit

/// FER-398 — the one-time move of the store container off the NOOP-era names
/// (`<AppSupport>/OpenWhoop/whoop.sqlite` → `<AppSupport>/Cenit/cenit.sqlite`).
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
        try write("OpenWhoop/whoop.sqlite", "DB")
        try write("OpenWhoop/whoop.sqlite-wal", "WAL")
        try write("OpenWhoop/whoop.sqlite-shm", "SHM")
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
        XCTAssertFalse(exists("Cenit/whoop.sqlite"), "the legacy file name must not survive the move")
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
        try write("OpenWhoop/whoop.sqlite", "OLD")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .keptBothNewWins)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "NEW",
                       "the live database is never overwritten by the legacy one")
        XCTAssertEqual(try read(legacyDir.appendingPathComponent("whoop.sqlite")), "OLD",
                       "the legacy container is left exactly as it was")
    }

    /// The crash that the sidecar-first / main-file-last order exists for: the process died after the
    /// `-wal` rename and before the main file's. The next launch has to finish the job, not stall.
    func testResumesAfterACrashBetweenTheSidecarAndTheMainFile() throws {
        try write("Cenit/whoop.sqlite", "DB")            // main file NOT renamed yet
        try write("Cenit/cenit.sqlite-wal", "WAL")       // sidecar already renamed
        try write("Cenit/whoop.sqlite-shm", "SHM")       // this one still pending

        let outcome = StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport)

        XCTAssertEqual(outcome, .resumedRenames)
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL",
                       "the already-renamed sidecar is left alone, not clobbered")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-shm")), "SHM")
        XCTAssertFalse(exists("Cenit/whoop.sqlite"))
    }

    /// It runs on EVERY launch, so the second run has to be a no-op with the data untouched.
    func testIsIdempotent() throws {
        try write("OpenWhoop/whoop.sqlite", "DB")
        try write("OpenWhoop/whoop.sqlite-wal", "WAL")

        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .movedFolder)
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated)
        XCTAssertEqual(StorePaths.migrateLegacyContainerIfNeeded(appSupport: appSupport), .alreadyMigrated)

        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite")), "DB")
        XCTAssertEqual(try read(newDir.appendingPathComponent("cenit.sqlite-wal")), "WAL")
    }
}
