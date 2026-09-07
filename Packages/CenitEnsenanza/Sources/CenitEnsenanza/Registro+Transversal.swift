import Foundation

// Entradas de la pestaña «transversal» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
extension Registro {
    public static let transversal: [Funcionalidad] = [
        Funcionalidad(
            id: .transversalWidgets,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalLiveActivity,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalWatch,
            pestana: .transversal,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalAvisos,
            pestana: .transversal,
            requiere: [.permiso(.notificaciones)],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalGestos,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85"
        ),
    ]
}
