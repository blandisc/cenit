import CenitStore
import Combine
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Sacar y meter la base completa, para mudarse de teléfono.
///
/// Cénit guarda todo en un archivo SQLite (`<AppSupport>/Cenit/cenit.sqlite`, más los `-wal`/`-shm`
/// mientras la base está abierta; ver `StorePaths`), así que mudarse es mover ese archivo. Sacar
/// pliega el WAL para que el archivo salga entero y lo copia a donde el usuario diga. Meter valida
/// el archivo elegido, guarda la base actual a un lado por si hay que volver, la reemplaza, y pide
/// reiniciar: la base sigue abierta, así que el archivo nuevo no entra en caliente.
///
/// Todo pasa dentro del recinto del sistema, apoyado en el permiso de leer y escribir archivos que
/// el usuario elige y en el alcance de seguridad de las URLs que devuelven los paneles. Ningún
/// camino revienta el app: lo que sale mal sale como `.failure` con un texto que se puede enseñar.
enum DataBackup {

    // MARK: - Resultado

    enum BackupResult {
        /// Se escribió el respaldo en `url`.
        case exported(URL)
        /// Entró el respaldo; hace falta reiniciar para que surta efecto. `sidecar` es dónde quedó
        /// la base anterior, por si el usuario quiere volver.
        case imported(sidecar: URL)
        /// El usuario cerró el panel. No pasó nada; no hay que hacer ruido.
        case cancelled
        /// Algo salió mal; `message` es para el usuario.
        case failure(String)
    }

    private static var databaseMissingMessage: String {
        "There's no Cénit data to export yet. Import or record some first."
    }

    private static func databaseNotFoundMessage(_ error: Error) -> String {
        "Couldn't locate the Cénit database. \(error.localizedDescription)"
    }

    // MARK: - Sacar

    /// Pliega el WAL y copia la base viva al archivo que elija el usuario.
    ///
    /// - Parameter checkpoint: se llama primero para volcar el WAL dentro del archivo principal
    ///   (en la práctica, `repo.checkpointForBackup`). Responde si el plegado de veras ocurrió.
    @MainActor
    static func runExport(checkpoint: @escaping () async -> Bool) async -> BackupResult {
        let databasePath: String
        do {
            databasePath = try StorePaths.defaultDatabasePath()
        } catch {
            return .failure(databaseNotFoundMessage(error))
        }

        let files = FileManager.default
        guard files.fileExists(atPath: databasePath) else {
            return .failure(databaseMissingMessage)
        }

        // En iOS el panel de exportación lleva un solo archivo, así que no se pueden mandar los
        // `-wal`/`-shm` de lado como en macOS. Si el plegado no ocurrió, la copia omitiría en
        // silencio todo lo escrito desde el último plegado automático: mejor fallar de frente que
        // entregar un respaldo a medias.
        guard await checkpoint() else {
            return .failure("Couldn't safely export right now — recent changes are still in the database's write-ahead log. Close any in-flight sync, then try again.")
        }

        let staged = files.temporaryDirectory.appendingPathComponent(defaultBackupName())
        do {
            removeIfPresent(staged)
            try files.copyItem(at: URL(fileURLWithPath: databasePath), to: staged)
        } catch {
            return .failure("Export failed: \(error.localizedDescription)")
        }

        guard let destination = await DocumentPicker.export(staged) else { return .cancelled }
        return .exported(destination)
    }

    // MARK: - Meter

    /// Elige un `.sqlite`, lo valida, guarda la base actual a un lado y lo pone en su lugar. La base
    /// sigue abierta, así que el archivo nuevo solo entra al reiniciar; avisarlo es del llamador.
    ///
    /// - Parameter beforeSwap: se ejecuta **antes** de tocar el archivo, para cerrar la base viva.
    ///   Sin eso, una escritura tardía caería en el inodo que el reemplazo deja huérfano.
    @MainActor
    static func runImport(beforeSwap: @MainActor () async -> Void = {}) async -> BackupResult {
        let databasePath: String
        do {
            databasePath = try StorePaths.defaultDatabasePath()
        } catch {
            return .failure(databaseNotFoundMessage(error))
        }

        // El panel del sistema con `asCopy` deja una copia local legible en el temporal, así que no
        // hay que llevar cuentas de alcance de seguridad.
        guard let source = await DocumentPicker.importFile(sqliteContentTypes()) else {
            return .cancelled
        }
        guard isSQLiteFile(at: source) else {
            return .failure("That file isn't a Cénit backup — it doesn't look like a SQLite database.")
        }

        do {
            await beforeSwap()
            return .imported(sidecar: try swapIn(source: source, dbPath: databasePath))
        } catch {
            return .failure("Import failed: \(error.localizedDescription)")
        }
    }

    /// El intercambio de archivos, donde el ORDEN es lo que protege los datos.
    ///
    /// Vive aparte de `runImport` para poder probar ese orden con archivos de un directorio temporal
    /// (FER-969 · X-04, FER-973 · T-04). Un tropiezo a media importación deja la base original —con
    /// su WAL— entera. Devuelve dónde quedó la copia de reversa; en una instalación nueva, la propia
    /// ruta viva, porque no había nada que preservar.
    static func swapIn(source: URL, dbPath: String) throws -> URL {
        let files = FileManager.default
        let liveURL = URL(fileURLWithPath: dbPath)
        let folder = liveURL.deletingLastPathComponent()

        // 1. Copia de reversa, con hora en el nombre, para que el usuario pueda volver.
        var rollback = folder.appendingPathComponent("cenit-replaced-\(timestamp()).sqlite")
        if files.fileExists(atPath: liveURL.path) {
            removeIfPresent(rollback)
            try files.copyItem(at: liveURL, to: rollback)
        } else {
            rollback = liveURL
        }

        // 2. El archivo entrante se prepara al lado del vivo, que nunca desaparece a media faena.
        let incoming = folder.appendingPathComponent("cenit-incoming-\(timestamp()).sqlite")
        removeIfPresent(incoming)
        try files.copyItem(at: source, to: incoming)

        // 3. El `-wal` y el `-shm` viejos se van ANTES del reemplazo, no después (FER-441).
        //    `beforeSwap()` ya cerró la base y plegó su WAL, así que están rancios. Borrarlos
        //    después serían dos llamadas separadas: un cierre forzado entre ellas dejaría el archivo
        //    NUEVO junto al `-wal` VIEJO, y el siguiente arranque repetiría marcos rancios sobre la
        //    base nueva. Borrándolos primero, un corte antes del reemplazo deja la base vieja ya
        //    plegada, y uno después deja la nueva sin WAL rancio. Ninguna de las dos se corrompe.
        removeIfPresent(URL(fileURLWithPath: dbPath + "-wal"))
        removeIfPresent(URL(fileURLWithPath: dbPath + "-shm"))

        // 4. El reemplazo.
        if files.fileExists(atPath: liveURL.path) {
            _ = try files.replaceItemAt(liveURL, withItemAt: incoming)
        } else {
            try files.moveItem(at: incoming, to: liveURL)
        }

        return rollback
    }

    // MARK: - Auxiliares

    /// Como `"Cénit-backup-2026-06-07.sqlite"`.
    private static func defaultBackupName() -> String {
        "Cénit-backup-\(DayKey.local(Date())).sqlite"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    /// El tipo `.sqlite` cuando el sistema lo conoce, más los genéricos para que los paneles abran
    /// también donde no está declarado.
    private static func sqliteContentTypes() -> [UTType] {
        var types: [UTType] = []
        if let sqlite = UTType(filenameExtension: "sqlite") { types.append(sqlite) }
        types.append(contentsOf: [.database, .data])
        return types
    }

    /// Un archivo SQLite empieza con `"SQLite format 3"` y un byte cero. Si no se puede leer eso, no
    /// es un respaldo nuestro.
    private static func isSQLiteFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let magic = Array("SQLite format 3".utf8) + [UInt8(0)]
        guard let head = try? handle.read(upToCount: magic.count),
              head.count == magic.count else { return false }
        return Array(head) == magic
    }

    private static func removeIfPresent(_ url: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return }
        try? files.removeItem(at: url)
    }
}

/// El respaldo casi automático de la base a una carpeta del iCloud Drive del propio usuario.
///
/// Por qué existe aparte del respaldo manual: las series crudas que se descargaron del aparato
/// externo heredado viven **solo** en el archivo del app — el aparato recortaba su copia en cuanto
/// el app confirmaba la descarga (ver `Backfiller`). Apple Salud se vuelve a sincronizar desde la
/// bóveda del sistema y un CSV se puede volver a importar, así que ese historial es lo único
/// irremplazable. Perder el contenedor del app —un borrado, una instalación nueva, un teléfono
/// perdido— lo pierde para siempre.
///
/// Con un Apple ID gratuito no hay contenedor de iCloud, pero el usuario sí puede señalar una vez
/// una carpeta suya de iCloud Drive: el marcador con alcance de seguridad que queda deja dejar ahí
/// una copia fresca en arranques posteriores, sin más avisos y sin permiso especial. iCloud la sube
/// fuera del aparato, así que sobrevive un borrado o un teléfono nuevo. Restaurar reusa
/// `DataBackup.runImport`.
///
/// Techo honesto: iCloud sube cuando el sistema quiere —normalmente minutos— y aquí solo se puede
/// escribir mientras el app está despierto, que es justo después de una sincronización, cuando hay
/// datos nuevos. El marcador vive en `UserDefaults` y se borra al desinstalar, así que tras una
/// reinstalación el usuario vuelve a elegir la carpeta una vez; lo que cruza es el archivo que ya
/// está en iCloud Drive.
@MainActor
final class AutoBackup: ObservableObject {

    /// Nombre visible de la carpeta elegida, o nada si el respaldo automático no está armado.
    @Published private(set) var destinationName: String?
    /// Cuándo aterrizó el último respaldo bueno. De aquí sale la línea «último respaldo hace…».
    @Published private(set) var lastBackup: Date?
    /// El último tropiezo (se perdió el acceso a la carpeta, falló la escritura). Se limpia al
    /// primer respaldo bueno.
    @Published private(set) var lastError: String?
    /// Cierto mientras hay una copia en curso, para que un doble toque no la atropelle.
    @Published private(set) var busy = false

    private let defaults = UserDefaults.standard
    private let bookmarkKey = PrefKey.autoBackupFolderBookmark.rawValue
    private let nameKey = PrefKey.autoBackupFolderName.rawValue
    private let lastKey = PrefKey.autoBackupLastDate.rawValue

    /// Cuando mucho un respaldo automático al día. El botón «Respaldar ahora» no lo consulta.
    private let minInterval: TimeInterval = 23 * 3_600

    /// Nombre fijo del archivo (FER-398 lo sacó del tronco de la app heredada). Restaurar es
    /// indiferente al nombre —el usuario elige el archivo a mano y el encabezado mágico lo valida—,
    /// así que ambos nombres restauran igual. Lo que el renombre habría roto es la rotación: una
    /// carpeta configurada antes de FER-398 ya tiene el nombre viejo, y escribir a un lado dejaría
    /// esa copia congelada para siempre, con pinta de segundo respaldo vigente. Por eso `writeCopy`
    /// busca los dos y adopta el viejo en la primera corrida.
    private let fileName = "Cenit-backup.sqlite"
    /// El nombre anterior a FER-398. Se lee y se adopta; nunca se escribe.
    private let legacyFileName = "NOOP-backup.sqlite"

    init() {
        destinationName = defaults.string(forKey: nameKey)
        if let seconds = defaults.object(forKey: lastKey) as? Double {
            lastBackup = Date(timeIntervalSince1970: seconds)
        }
    }

    /// Hay carpeta elegida, o sea: el respaldo automático está armado.
    var isConfigured: Bool { defaults.data(forKey: bookmarkKey) != nil }

    // MARK: - Armar y desarmar

    /// Enseña el selector de carpeta y guarda un marcador con alcance de seguridad a la que elijan.
    /// El texto de la pantalla empuja hacia una carpeta de iCloud Drive, para que el respaldo salga
    /// del aparato.
    func chooseFolder() async {
        guard let url = await DocumentPicker.pickFolder() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try url.bookmarkData(options: [],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            defaults.set(bookmark, forKey: bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: nameKey)
            destinationName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = String(localized: "Couldn't remember that folder. Try a folder in iCloud Drive.")
        }
    }

    /// Olvida el destino y deja de respaldar solo. El archivo que ya está en iCloud Drive se queda
    /// donde está, para que «Restaurar» siga encontrándolo.
    func disable() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
        destinationName = nil
    }

    // MARK: - Respaldar

    /// El respaldo automático, con su freno: no hace nada sin destino ni si el último es reciente.
    func backupIfDue(checkpoint: () async -> Bool) async {
        guard isConfigured else { return }
        if let last = lastBackup, Date().timeIntervalSince(last) < minInterval { return }
        await backupNow(checkpoint: checkpoint)
    }

    /// Copia la base viva a la carpeta elegida, ahora. Se puede llamar cuantas veces se quiera.
    func backupNow(checkpoint: () async -> Bool) async {
        guard !busy, isConfigured else { return }
        busy = true
        defer { busy = false }

        guard let folder = resolveFolder() else {
            lastError = String(localized: "Lost access to the backup folder — choose it again.")
            return
        }
        // El alcance vale para todo el proceso y se sostiene a través de la espera de abajo.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        // Plegar el WAL para que una copia simple salga entera. Con la base abierta esto funciona;
        // si no, más vale saltarse la ronda que mandar medio archivo.
        guard await checkpoint() else {
            lastError = String(localized: "Couldn't snapshot the database just now — will retry.")
            return
        }

        let databasePath: String
        do {
            databasePath = try StorePaths.defaultDatabasePath()
        } catch {
            lastError = String(localized: "Couldn't locate the Cénit database.")
            return
        }
        guard FileManager.default.fileExists(atPath: databasePath) else {
            lastError = String(localized: "No database to back up yet.")
            return
        }

        let destination = folder.appendingPathComponent(fileName)
        let rollback = folder.appendingPathComponent(fileName + ".prev")
        let legacy = folder.appendingPathComponent(legacyFileName)
        let legacyRollback = folder.appendingPathComponent(legacyFileName + ".prev")

        // La escritura bloquea y el archivo puede pesar varios megabytes: fuera del hilo de la
        // interfaz para que no dé un tirón.
        let database = URL(fileURLWithPath: databasePath)
        let failure = await Task.detached {
            AutoBackup.writeCopy(db: database, to: destination, keepingPrev: rollback,
                                 adopting: legacy, adoptingPrev: legacyRollback)
        }.value

        if let failure {
            lastError = String(localized: "Backup couldn't be saved: \(failure.localizedDescription)")
            return
        }

        let landed = Date()
        lastBackup = landed
        defaults.set(landed.timeIntervalSince1970, forKey: lastKey)
        lastError = nil
    }

    // MARK: - Auxiliares

    /// Convierte el marcador guardado en una carpeta usable, refrescándolo si el sistema lo declara
    /// rancio.
    private func resolveFolder() -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }

        if isStale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: [],
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    /// La copia coordinada de la base a `dest`, rotando antes la anterior a `prev` como seguro
    /// barato contra una escritura corrupta. Corre fuera del actor principal. Devuelve nada si todo
    /// salió bien.
    ///
    /// `legacy` es el archivo con el nombre anterior a FER-398: si la carpeta todavía lo tiene y
    /// `dest` aún no existe, se **renombra** a `dest`, de modo que esta corrida rote el MISMO linaje
    /// en vez de dejar un archivo viejo congelado junto a uno nuevo — dos respaldos, uno muerto e
    /// indistinguible del vivo cuando el usuario elige cuál restaurar.
    ///
    /// `legacyPrev` es su copia de reversa, adoptada igual y por lo mismo, o quedaría en la carpeta
    /// para siempre como un tercer archivo SQLite. Se adopta ANTES de rotar, para que una copia de
    /// reversa más fresca gane el lugar en esta corrida.
    ///
    /// Es `internal` a propósito: `AutoBackupAdoptionTests` ejerce la adopción y la rotación sobre
    /// archivos de un directorio temporal, sin iCloud ni carpeta elegida por nadie.
    nonisolated static func writeCopy(db: URL, to dest: URL, keepingPrev prev: URL,
                                      adopting legacy: URL, adoptingPrev legacyPrev: URL) -> Error? {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: dest, options: .forReplacing,
                               error: &coordinationError) { target in
            let files = FileManager.default
            do {
                // Adoptar lo que dejó el nombre anterior. De mejor esfuerzo: si falla, solo se salta
                // la rotación de esta corrida.
                if !files.fileExists(atPath: target.path), files.fileExists(atPath: legacy.path) {
                    try? files.moveItem(at: legacy, to: target)
                }
                if !files.fileExists(atPath: prev.path), files.fileExists(atPath: legacyPrev.path) {
                    try? files.moveItem(at: legacyPrev, to: prev)
                }

                // Rotar: el respaldo de ayer se vuelve la copia de reversa.
                if files.fileExists(atPath: target.path) {
                    try? files.removeItem(at: prev)
                    do {
                        try files.moveItem(at: target, to: prev)
                    } catch {
                        // Si no se pudo rotar, al menos dejar el camino libre para la copia nueva.
                        try? files.removeItem(at: target)
                    }
                }

                try files.copyItem(at: db, to: target)
            } catch {
                writeError = error
            }
        }

        return writeError ?? coordinationError
    }
}
