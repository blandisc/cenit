import Foundation

// Entradas de la pestaña «tendencias» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
extension Registro {
    public static let tendencias: [Funcionalidad] = [
        Funcionalidad(
            id: .tendenciasPestana,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .hito(id: "tendencias.pestana.primera-tendencia")],
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
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.preparacion")],
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
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasComparar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.comparar")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .tendenciasExplorar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.explorar")],
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
