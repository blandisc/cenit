#if os(iOS) && DEBUG
import Foundation

/// CEN-45 · las claves de navegación de captura (`notifyutil -p cenit.nav.<clave>` / `cenit://<clave>`)
/// que la raíz de Fuerza atiende. Antes las atendía el dock (`RootTabView`), borrado con el Camino C+;
/// desde CEN-43 ninguna llegaba a ningún lado. `Tools/check-nav-keys.py` exige que toda clave de
/// `DebugNavWatcher.screens` esté aquí (R1).
///
/// Destino de cada una (lo resuelve `FuerzaRootView`):
///   train · entrenar                      → la raíz (cierra la hoja abierta)
///   settings · ajustes · more             → hoja Ajustes
///   applehealth · datasources · support   → hoja Ajustes (sus hijas se abren con `-cenit.route ajustes/<clave>`)
///   weeklyplan · misrutinas · routineToday → hoja Plan
///   library                               → hoja Progreso › Biblioteca
///   workouthistory · workouts             → hoja Progreso › Mis entrenamientos
///   intervals                             → el temporizador de intervalos
enum FuerzaDebugNav {
    static let clavesNav: [String] = [
        "train", "entrenar",
        "settings", "ajustes", "more",
        "applehealth", "datasources", "support",
        "weeklyplan", "misrutinas", "routineToday",
        "library",
        "workouthistory", "workouts",
        "intervals",
    ]
}
#endif
