import Foundation

// Entradas de la pestaña «transversal» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let transversal: [Funcionalidad] = [
        Funcionalidad(
            id: .transversalWidgets,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.widget.sin-plan.queEs")],
            desde: "1.85",
            mapa: [
                "fuera-del-iphone/widget-hoy-con-rutina",
                "fuera-del-iphone/widget-hoy-descanso",
                "fuera-del-iphone/widget-hoy-sesion-viva",
                "fuera-del-iphone/widget-hoy-snapshot-rancio",
                "fuera-del-iphone/widget-hoy-sin-snapshot",
                "fuera-del-iphone/widget-semana-con-rutina",
                "fuera-del-iphone/widget-semana-descanso",
                "fuera-del-iphone/widget-semana-sesion-viva",
                "fuera-del-iphone/widget-semana-snapshot-rancio",
                "fuera-del-iphone/widget-semana-sin-snapshot",
            ]
        ),
        Funcionalidad(
            id: .transversalLiveActivity,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.live-activity.por-fc.linea")],
            desde: "1.85",
            mapa: [
                "fuera-del-iphone/live-activity-set-activo",
                "fuera-del-iphone/live-activity-descanso-timer",
                "fuera-del-iphone/live-activity-descanso-hr",
                "fuera-del-iphone/live-activity-pausa",
                "fuera-del-iphone/live-activity-rancia",
                "fuera-del-iphone/live-activity-isla-dinamica",
            ]
        ),
        Funcionalidad(
            id: .transversalWatch,
            pestana: .transversal,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .transversal), .vacio(clave: "vacio.watch.primer-uso.queEs")],
            desde: "1.85",
            mapa: [
                "fuera-del-iphone/watch-idle-con-veredicto",
                "fuera-del-iphone/watch-idle-veredicto-atenuada",
                "fuera-del-iphone/watch-idle-sin-lectura-fallo-health",
                "fuera-del-iphone/watch-idle-ax5",
                "fuera-del-iphone/watch-healthkit-fallo-arranque",
                "fuera-del-iphone/watch-descanso-pulso-esperando",
                "fuera-del-iphone/watch-descanso-pulso-faltan-lpm",
                "fuera-del-iphone/watch-descanso-pulso-almost",
                "fuera-del-iphone/watch-descanso-pulso-ready",
                "fuera-del-iphone/watch-descanso-sigue-siguiente-ejercicio",
                "fuera-del-iphone/watch-descanso-pulso-ax5",
                "fuera-del-iphone/watch-standalone-live",
                "fuera-del-iphone/watch-resumen-sesion",
            ]
        ),
        Funcionalidad(
            id: .transversalAvisos,
            pestana: .transversal,
            requiere: [.permiso(.notificaciones)],
            piezas: [.ayuda(seccion: .transversal)],
            desde: "1.85",
            mapa: ["ajustes/aviso-matutino", "ajustes/recordatorio-entreno"]
        ),
        Funcionalidad(
            id: .transversalGestos,
            pestana: .transversal,
            requiere: [],
            piezas: [.ayuda(seccion: .transversal), .gestoConBoton(gesto: "gesto.entrenar.series.gesto", boton: "gesto.entrenar.series.boton"), .gestoConBoton(gesto: "gesto.entrenar.ronda.gesto", boton: "gesto.entrenar.ronda.boton"), .gestoConBoton(gesto: "gesto.entrenar.rutina.gesto", boton: "gesto.entrenar.rutina.boton"), .gestoConBoton(gesto: "gesto.hoy.hipnograma.gesto", boton: "gesto.hoy.hipnograma.boton")],
            desde: "1.85",
            mapa: [
                "entrenar/rutina-hoy",
                "entrenar/editor-rutina",
                "entrenar/tu-plan",
                "entrenar/sesion-superserie",
                "hoy/sueno",
            ]
        ),
    ]
}
