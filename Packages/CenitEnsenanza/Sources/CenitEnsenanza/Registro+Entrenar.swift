import Foundation

// Entradas de la pestaña «entrenar» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
extension Registro {
    public static let entrenar: [Funcionalidad] = [
        Funcionalidad(
            id: .entrenarPestana,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarPrimerUso,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarTaller,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarHero,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarOtraForma,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.otra-forma")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarMosaico,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .vacio(clave: "vacio.mosaico.dosis.linea"), .vacio(clave: "vacio.mosaico.volumen.linea")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarPlan,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.plan.semana-ligera"), .vacio(clave: "No routines yet")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarProgresion,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.progresion.ritmo"), .tip(id: "entrenar.progresion.activar")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarRir,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.rir")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarAmrapDrop,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.amrap-drop.amrap"), .tip(id: "entrenar.amrap-drop.drop")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarDescanso,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.descanso.por-fc")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarBiblioteca,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .vacio(clave: "vacio.biblioteca.filtros.queEs"), .vacio(clave: "Not logged yet")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarImportarPlan,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarImportarCsv,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarSesionViva,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.sesion-viva.foco-entrar"), .tip(id: "entrenar.sesion-viva.foco-salir"), .tip(id: "entrenar.sesion-viva.discos"), .gestoConBoton(gesto: "gesto.entrenar.foco.gesto", boton: "gesto.entrenar.foco.boton"), .gestoConBoton(gesto: "gesto.entrenar.discos.gesto", boton: "gesto.entrenar.discos.boton")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarEsfuerzoEstimado,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .tip(id: "entrenar.esfuerzo-estimado")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarRecibo,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .vacio(clave: "No tickets yet"), .vacio(clave: "No cardio tickets yet")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarHistorial,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar), .hito(id: "entrenar.historial.primera-sesion"), .vacio(clave: "No workouts yet"), .vacio(clave: "vacio.historial.periodo.queEs")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarMarcas,
            pestana: .entrenar,
            requiere: [.entrenos],
            piezas: [.ayuda(seccion: .entrenar), .hito(id: "entrenar.marcas.primer-record"), .vacio(clave: "You don't have any marks yet")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarMapaMuscular,
            pestana: .entrenar,
            requiere: [.entrenos],
            piezas: [.ayuda(seccion: .entrenar), .vacio(clave: "Train to fill your map"), .vacio(clave: "No sets in this range")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .entrenarRespiraIntervalos,
            pestana: .entrenar,
            requiere: [],
            piezas: [.ayuda(seccion: .entrenar)],
            desde: "1.85"
        ),
    ]
}
