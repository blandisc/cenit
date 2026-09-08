import Foundation
import os

/// Where Cénit keeps its one SQLite file, and the one-time move off the names it shipped under before.
///
/// **FER-398.** The container used to live under the legacy folder + file name below — frozen since the
/// rebrand because renaming it would orphan every existing install's data. It is unfrozen here, with
/// a migration that runs once at launch (`CenitApp.init()`, before `AppModel()` opens the store).
///
/// The migration is a **folder rename**, not a copy: one `moveItem` carries the DB, its `-wal`/`-shm`
/// sidecars, the rollback sidecars a previous restore left behind and `MediaCache/` in a single
/// atomic step, with no window where the data lives in two places or half of it in each. The
/// per-file rename that follows renames the **sidecars first and the main file LAST**, so the main
/// file's name is the mark of "done": a crash halfway leaves the legacy name in place and the next
/// launch simply resumes.
///
/// When `Cenit/` already exists but holds no database — an interrupted first run, or a folder a path
/// helper created — the rename has nowhere to land, so the contents are **merged** into it instead,
/// entry by entry and main file last. Without that step the app would open empty on top of a full
/// `OpenWhoop/`: the history intact on disk and invisible.
///
/// Nothing is ever deleted (beyond the empty legacy shell a completed merge leaves behind). If the
/// move fails, the old folder stays exactly as it was and the app opens on an empty `Cenit/` — the
/// user's history is recoverable by hand rather than gone.
enum StorePaths {

    // MARK: - Names

    /// Container folder under Application Support.
    static let folderName = "Cenit"
    /// The single SQLite file inside it.
    static let databaseFileName = "cenit.sqlite"
    /// El contenedor heredado del que esta migración se muda. Dato en disco: no lo cambies.
    static let legacyFolderName = "OpenWhoop"
    /// El nombre heredado del archivo dentro de ese contenedor. Dato en disco: no lo cambies.
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
        /// The folder was already `Cenit/` but still held the legacy file name — a previous run was
        /// interrupted between the folder rename and the file rename, and this run finished it.
        case resumedRenames
        /// BOTH containers exist and the new one already has its DB. The legacy folder is left
        /// exactly as it is: the live database wins, and the old one stays for manual rescue.
        case keptBothNewWins
        /// `Cenit/` already existed but held NO database (an interrupted first run, a folder created
        /// by a path helper), while the legacy container still held the real data. The contents were
        /// merged into the existing folder file by file instead of the app opening empty.
        case mergedIntoExisting
    }

    /// Move the legacy container onto the Cénit names, once. Idempotent and safe to call on every
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

        // ②b `Cenit/` ALREADY EXISTS but holds no database of either name, and the legacy container
        //     still has the real data. The atomic rename above cannot run (the destination is taken),
        //     and without this the app would open empty on top of a full `OpenWhoop/` — the user's
        //     history intact on disk and invisible. So merge the CONTENTS, file by file, with the same
        //     discipline as ③: everything else first, the main database LAST, so its arrival is the
        //     "done" mark and an interrupted run resumes on the next launch. A destination that
        //     already exists is never overwritten — it is skipped and left for manual rescue.
        if !moved,
           fm.fileExists(atPath: legacyContainer.path),
           fm.fileExists(atPath: container.path),
           !fm.fileExists(atPath: legacyDB.path),
           mergeLegacyContents(from: legacyContainer, into: container, fm: fm) {
            return .mergedIntoExisting
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

    /// Move every entry of the legacy container into an existing `Cenit/`, renaming the database and
    /// its sidecars on the way. Returns whether the legacy database actually landed.
    ///
    /// Order is the whole point: the main database goes LAST, after its sidecars and everything else,
    /// so a crash mid-merge leaves the legacy file where it was and the next launch redoes the rest
    /// harmlessly (each already-moved entry is skipped because its destination exists).
    private static func mergeLegacyContents(from legacyContainer: URL, into container: URL,
                                            fm: FileManager) -> Bool {
        guard let entries = try? fm.contentsOfDirectory(at: legacyContainer,
                                                        includingPropertiesForKeys: nil) else {
            log.error("Could not read \(legacyFolderName, privacy: .public)/ to merge it; left untouched.")
            return false
        }
        // A partition, not a `sorted` — the main file goes last and everything else keeps the order
        // the filesystem gave. (`sorted` with a "is it the DB" predicate is not a strict weak
        // ordering, so it is free to interleave.)
        let ordered = entries.filter { $0.lastPathComponent != legacyDatabaseFileName }
            + entries.filter { $0.lastPathComponent == legacyDatabaseFileName }
        var landedDB = false
        for from in ordered {
            let name = from.lastPathComponent
            // el archivo heredado y sus dos compañeros (`-wal`, `-shm`) → los nombres de Cénit; lo demás
            // (MediaCache/, a restore sidecar) keeps its own name.
            let destName = name.hasPrefix(legacyDatabaseFileName)
                ? databaseFileName + String(name.dropFirst(legacyDatabaseFileName.count))
                : name
            let to = container.appendingPathComponent(destName)
            guard !fm.fileExists(atPath: to.path) else {
                log.notice("Merge skipped \(destName, privacy: .public): already present in \(folderName, privacy: .public)/.")
                continue
            }
            do {
                try fm.moveItem(at: from, to: to)
                if name == legacyDatabaseFileName { landedDB = true }
            } catch {
                log.error("Could not merge \(name, privacy: .public): \(error.localizedDescription, privacy: .public). Left in place.")
            }
        }
        // Only the now-empty shell is removed — never data. Without this, every later launch would
        // report `keptBothNewWins` over a folder with nothing in it.
        if let left = try? fm.contentsOfDirectory(at: legacyContainer, includingPropertiesForKeys: nil),
           left.isEmpty {
            try? fm.removeItem(at: legacyContainer)
        }
        return landedDB
    }
}
