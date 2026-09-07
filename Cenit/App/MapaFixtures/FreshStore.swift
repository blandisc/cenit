#if os(iOS) && DEBUG
import Foundation

/// `-cenit.freshStore YES` (FER-381): borra la base SQLite ANTES de que el store se abra, para que
/// cada estado de captura sea hermético sin `xcrun simctl erase` entre corridas (los fixtures escriben
/// rutinas/sesiones en el store real, y sin esto una corrida contamina a la siguiente).
///
/// SOLO SIMULADOR, igual que `ScreenshotFixtures.activeState()`: jamás debe correr en un iPhone real
/// — borraría los datos del dueño. Se llama una vez, al inicio de `AppModel.init`, antes de cualquier
/// apertura del store (que es perezosa en `Repository.ensureStore`).
enum FreshStore {
    static func applyIfRequested() {
        #if targetEnvironment(simulator)
        guard UserDefaults.standard.string(forKey: "cenit.freshStore")?.lowercased() == "yes" else { return }
        guard let path = try? StorePaths.defaultDatabasePath() else { return }
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {   // el .sqlite y sus sidecars WAL/SHM
            let p = path + suffix
            if fm.fileExists(atPath: p) { try? fm.removeItem(atPath: p) }
        }
        print("[FreshStore] base borrada antes de abrir — captura hermética")
        #endif
    }
}
#endif
