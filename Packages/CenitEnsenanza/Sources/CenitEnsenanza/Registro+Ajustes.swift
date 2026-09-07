import Foundation

// Entradas de la pestaña «ajustes» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
extension Registro {
    public static let ajustes: [Funcionalidad] = [
        Funcionalidad(
            id: .ajustesPerfil,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesFuentes,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes), .vacio(clave: "vacio.fuentes.salud.queEs"), .vacio(clave: "vacio.salud.seccion.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesRespaldo,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesVigilancia,
            pestana: .ajustes,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesAvisos,
            pestana: .ajustes,
            requiere: [.permiso(.notificaciones)],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesHistorialFa,
            pestana: .ajustes,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesSesion,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesExperimental,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesAnimaciones,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesAyuda,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesNovedades,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .ajustesApariencia,
            pestana: .ajustes,
            requiere: [],
            piezas: [.ayuda(seccion: .ajustes)],
            desde: "1.85"
        ),
    ]
}
