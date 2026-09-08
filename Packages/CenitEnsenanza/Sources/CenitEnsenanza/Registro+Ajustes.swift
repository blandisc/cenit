import Foundation

// Entradas de la pestaña «ajustes» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let ajustes: [Funcionalidad] = [
        Funcionalidad(
            id: .ajustesPerfil,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: [
                "ajustes/raiz",
                "ajustes/perfil-edad",
                "ajustes/perfil-peso",
                "ajustes/perfil-altura",
                "ajustes/fc-max",
                "onboarding/perfil",
            ]
        ),
        Funcionalidad(
            id: .ajustesFuentes,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes), .vacio(clave: "vacio.fuentes.salud.queEs"), .vacio(clave: "vacio.salud.seccion.queEs")],
            desde: "1.85",
            mapa: [
                "ajustes/fuentes-sin-conexion",
                "ajustes/fuentes-con-dias",
                "ajustes/fuentes-health-lasterror",
                "ajustes/fuentes-strengthcsv-error",
                "ajustes/apple-salud-cargando",
                "ajustes/apple-salud-sin-filas",
                "ajustes/apple-salud-con-filas",
                "hoy/fuentes",
            ]
        ),
        Funcionalidad(
            id: .ajustesRespaldo,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: [
                "ajustes/fuentes-backup-ok",
                "ajustes/fuentes-backup-error",
                "ajustes/fuentes-autobackup-lasterror",
                "onboarding/restore-offer",
                "onboarding/restore-result",
            ]
        ),
        Funcionalidad(
            id: .ajustesVigilancia,
            pestana: .ajustes,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz"]
        ),
        Funcionalidad(
            id: .ajustesAvisos,
            pestana: .ajustes,
            requiere: [.permiso(.notificaciones)],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/aviso-matutino", "ajustes/recordatorio-entreno", "onboarding/ciclo"]
        ),
        Funcionalidad(
            id: .ajustesHistorialFa,
            pestana: .ajustes,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/historial-fa-informa", "ajustes/historial-fa-oculta"]
        ),
        Funcionalidad(
            id: .ajustesSesion,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz"]
        ),
        Funcionalidad(
            id: .ajustesExperimental,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz", "ajustes/ciclo", "tendencias/ciclo"]
        ),
        Funcionalidad(
            id: .ajustesAnimaciones,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: [
                "ajustes/descarga-animaciones-idle",
                "ajustes/descarga-animaciones-descargando",
                "ajustes/descarga-animaciones-completado",
                "ajustes/descarga-animaciones-fallo",
            ]
        ),
        Funcionalidad(
            id: .ajustesAyuda,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz"]
        ),
        Funcionalidad(
            id: .ajustesNovedades,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz"]
        ),
        Funcionalidad(
            id: .ajustesApariencia,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85",
            mapa: ["ajustes/raiz", "ajustes/unidades"]
        ),
    ]
}
