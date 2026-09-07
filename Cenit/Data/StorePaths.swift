import Foundation
import os

/// Where Cénit keeps its one SQLite file, and the one-time move off the NOOP-era names.
///
/// **FER-398.** The container used to be `<AppSupport>/OpenWhoop/whoop.sqlite` — frozen since the
/// rebrand because renaming it would orphan every existing install's data. It is unfrozen here, with
/// a migration that runs once at launch (`CenitApp.init()`, before `AppModel()` opens the store).
///
/// The migration is a **folder rename**, not a copy: one `moveItem` carries the DB, its `-wal`/`-shm`
/// sidecars, the rollback sidecars a previous restore left behind and `MediaCache/` in a single
/// atomic step, with no window where the data lives in two places or half of it in each. The
/// per-file rename that follows renames the **sidecars first and the main file LAST**, so the main
/// file's name is the mark of "done": a crash halfway leaves `whoop.sqlite` in place and the next
/// launch simply resumes.
///
/// Nothing is ever deleted. If the move fails, the old folder stays exactly as it was and the app
/// opens on an empty `Cenit/` — the user's history is recoverable by hand rather than gone.
enum StorePaths {

    // MARK: - Names

    /// Container folder under Application Support.
    static let folderName = "Cenit"
    /// The single SQLite file inside it.
    static let databaseFileName = "cenit.sqlite"
    /// The NOOP-era container this migration moves away from.
    static let legacyFolderName = "OpenWhoop"
    /// The NOOP-era database file name inside that container.
    static let legacyDatabaseFileName = "whoop.sqlite"

    /// SQLite's own sidecars, renamed alongside the main file (order matters — see the type doc).
    private static let sidecarSuffixes = ["-wal", "-shm"]

    private static let log = Logger(subsystem: "com.feriracheta.cenit", category: "StorePaths")

    // MARK: - Paths

    /// The user's Application Support directory, created if missing.
    static func appSupport() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
    }

    /// `<appSupport>/Cenit` — the folder that holds the DB, its sidecars and `MediaCache/`.
    /// Pure path arithmetic: it creates nothing.
    static func containerDirectory(in appSupport: URL) -> URL {
        appSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `<appSupport>/Cenit/cenit.sqlite`, creating the container if needed.
    static func databasePath(in appSupport: URL) throws -> String {
        let container = containerDirectory(in: appSupport)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container.appendingPathComponent(databaseFileName).path
    }

    /// `<AppSupport>/Cenit/cenit.sqlite`, creating the directory if needed.
    static func defaultDatabasePath() throws -> String {
        try databasePath(in: appSupport())
    }

    // MARK: - Legacy migration

    /// What `migrateLegacyContainerIfNeeded` actually did. Reported (not just logged) so the launch
    /// path and the tests can both assert on it.
    enum LegacyMigrationOutcome: Equatable {
        /// Fresh install — neither the new container nor the legacy one is there. Also the result
        /// when the folder rename FAILED: nothing was moved, and the old folder is untouched.
        case nothingToDo
        /// The new container already holds `cenit.sqlite` and there is no legacy folder left.
        case alreadyMigrated
        /// The legacy folder was renamed whole (DB + sidecars + backups + `MediaCache/`).
        case movedFolder
        /// The folder was already `Cenit/` but still held `whoop.sqlite` — a previous run was
        /// interrupted between the folder rename and the file rename, and this run finished it.
        case resumedRenames
        /// BOTH containers exist and the new one already has its DB. The legacy folder is left
        /// exactly as it is: the live database wins, and the old one stays for manual rescue.
        case keptBothNewWins
    }

    /// Move the NOOP-era container onto the Cénit names, once. Idempotent and safe to call on every
    /// launch: on an already-migrated install it does two `fileExists` checks and returns.
    ///
    /// Call it BEFORE anything opens the store.
    @discardableResult
    static func migrateLegacyContainerIfNeeded(appSupport: URL,
                                               fm: FileManager = .default) -> LegacyMigrationOutcome {
        let container = containerDirectory(in: appSupport)
        let legacyContainer = appSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
        let newDB = container.appendingPathComponent(databaseFileName)
        let legacyDB = container.appendingPathComponent(legacyDatabaseFileName)

        // ① The new database already exists ⇒ we are done, whatever else is lying around.
        if fm.fileExists(atPath: newDB.path) {
            guard fm.fileExists(atPath: legacyContainer.path) else { return .alreadyMigrated }
            log.notice("Legacy container still present beside a live \(folderName, privacy: .public)/ — left untouched for manual rescue.")
            return .keptBothNewWins
        }

        // ② The legacy container is there and the new one is not ⇒ ONE atomic rename carries
        //    everything: the DB, its -wal/-shm, any rollback sidecar, and MediaCache/.
        var moved = false
        if fm.fileExists(atPath: legacyContainer.path), !fm.fileExists(atPath: container.path) {
            do {
                try fm.moveItem(at: legacyContainer, to: container)
                moved = true
            } catch {
                // Never delete anything on failure: the old folder is still whole, and the app will
                // open on an empty Cenit/ rather than on half a database.
                log.fault("Could not move \(legacyFolderName, privacy: .public)/ to \(folderName, privacy: .public)/: \(error.localizedDescription, privacy: .public). The old folder is untouched.")
                return .nothingToDo
            }
        }

        // ③ Inside the container, rename the file itself. SIDECARS FIRST, main file LAST — the main
        //    file's name is the "done" mark, so an interrupted run resumes here on the next launch.
        guard fm.fileExists(atPath: legacyDB.path) else {
            return moved ? .movedFolder : .nothingToDo
        }
        for suffix in sidecarSuffixes {
            let from = URL(fileURLWithPath: legacyDB.path + suffix)
            let to = URL(fileURLWithPath: newDB.path + suffix)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            do { try fm.moveItem(at: from, to: to) }
            catch { log.error("Could not rename the \(suffix, privacy: .public) sidecar: \(error.localizedDescription, privacy: .public)") }
        }
        do {
            try fm.moveItem(at: legacyDB, to: newDB)
        } catch {
            log.fault("Could not rename \(legacyDatabaseFileName, privacy: .public) to \(databaseFileName, privacy: .public): \(error.localizedDescription, privacy: .public). The old file is untouched.")
            return .nothingToDo
        }
        return moved ? .movedFolder : .resumedRenames
    }
}
