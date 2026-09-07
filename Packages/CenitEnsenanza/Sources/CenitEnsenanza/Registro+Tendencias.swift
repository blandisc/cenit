import Foundation

// Entradas de la pestaña «tendencias» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
extension Registro {
    public static let tendencias: [Funcionalidad] = [
        Funcionalidad(
            id: .tendenciasPestana,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .hito(id: "tendencias.pestana.primera-tendencia"), .vacio(clave: "vacio.tendencias.pasos.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasPeriodo,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.periodo")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasPreparacion,
            pestana: .tendencias,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.preparacion"), .vacio(clave: "vacio.tendencias.heroe.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasDescansoCarga,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasMapaDelDia,
            pestana: .tendencias,
            requiere: [.watch, .permiso(.calendario)],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.mapa-del-dia")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasCarga,
            pestana: .tendencias,
            requiere: [.entrenos],
            piezas: [.ayuda(seccion: .tendencias), .hito(id: "tendencias.carga.leida")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasVitales,
            pestana: .tendencias,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .tendencias), .vacio(clave: "vacio.detalle.tendencia.queEs"), .vacio(clave: "vacio.detalle.anoche.queEs"), .vacio(clave: "vacio.detalle.hoy.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasComparar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.comparar"), .vacio(clave: "vacio.comparar.selector.queEs"), .vacio(clave: "vacio.comparar.sin-datos.queEs"), .vacio(clave: "vacio.comparar.pares.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasExplorar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.explorar"), .vacio(clave: "vacio.detalle.tendencia.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasDeporte,
            pestana: .tendencias,
            requiere: [.watch, .entrenos],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasLongevidad,
            pestana: .tendencias,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasFuentes,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85"
        ),
    ]
}
