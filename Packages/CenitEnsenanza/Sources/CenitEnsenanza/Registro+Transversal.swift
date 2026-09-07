import Foundation

// Entradas de la pestaña «transversal» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
extension Registro {
    public static let transversal: [Funcionalidad] = [
        Funcionalidad(
            id: .transversalWidgets,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.widget.sin-plan.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalLiveActivity,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.live-activity.por-fc.linea")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .transversalWatch,
            pestana: .transversal,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.watch.primer-uso.queEs")],
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
            piezas: [.ayuda(seccion: .transversal), .gestoConBoton(gesto: "gesto.entrenar.series.gesto", boton: "gesto.entrenar.series.boton"), .gestoConBoton(gesto: "gesto.entrenar.ronda.gesto", boton: "gesto.entrenar.ronda.boton"), .gestoConBoton(gesto: "gesto.entrenar.rutina.gesto", boton: "gesto.entrenar.rutina.boton"), .gestoConBoton(gesto: "gesto.hoy.hipnograma.gesto", boton: "gesto.hoy.hipnograma.boton")],
            desde: "1.85"
        ),
    ]
}
