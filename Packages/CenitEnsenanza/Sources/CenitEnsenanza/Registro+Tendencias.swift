import Foundation

// Entradas de la pestaña «tendencias» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let tendencias: [Funcionalidad] = [
        Funcionalidad(
            id: .tendenciasPestana,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .hito(id: "tendencias.pestana.primera-tendencia"), .vacio(clave: "vacio.tendencias.pasos.queEs")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasPeriodo,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.periodo")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasPreparacion,
            pestana: .tendencias,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.preparacion"), .vacio(clave: "vacio.tendencias.heroe.queEs")],
            desde: "1.85",
            mapa: [
                "hoy/preparacion-cargando",
                "hoy/preparacion-sin-permiso",
                "hoy/preparacion-sin-historia",
                "hoy/preparacion-con-ventana",
            ]
        ),
        Funcionalidad(
            id: .tendenciasDescansoCarga,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85",
            mapa: ["hoy/sueno", "hoy/esfuerzo", "hoy/estres"]
        ),
        Funcionalidad(
            id: .tendenciasMapaDelDia,
            pestana: .tendencias,
            requiere: [.watch, .permiso(.calendario)],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.mapa-del-dia")],
            desde: "1.85",
            mapa: ["hoy/estres"]
        ),
        Funcionalidad(
            id: .tendenciasCarga,
            pestana: .tendencias,
            requiere: [.entrenos],
            piezas: [.ayuda(seccion: .tendencias), .hito(id: "tendencias.carga.leida")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasVitales,
            pestana: .tendencias,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .tendencias), .vacio(clave: "vacio.detalle.tendencia.queEs"), .vacio(clave: "vacio.detalle.anoche.queEs"), .vacio(clave: "vacio.detalle.hoy.queEs")],
            desde: "1.85",
            mapa: [
                "tendencias/detalle-hrv-m-full",
                "tendencias/detalle-rhr-m-full",
                "tendencias/detalle-spo2-m-full",
                "tendencias/detalle-heart-rate-m-full",
                "tendencias/detalle-resp-rate-m-full",
                "tendencias/detalle-skin-temp-m-full",
            ]
        ),
        Funcionalidad(
            id: .tendenciasComparar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.comparar"), .vacio(clave: "vacio.comparar.selector.queEs"), .vacio(clave: "vacio.comparar.sin-datos.queEs"), .vacio(clave: "vacio.comparar.pares.queEs")],
            desde: "1.85",
            mapa: ["tendencias/comparar-full", "tendencias/comparar-vacio"]
        ),
        Funcionalidad(
            id: .tendenciasExplorar,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias), .tip(id: "tendencias.explorar"), .vacio(clave: "vacio.detalle.tendencia.queEs")],
            desde: "1.85",
            mapa: [
                "tendencias/explorar-full",
                "tendencias/explorar-vacio",
                "tendencias/detalle-avg-hr-m-full",
                "tendencias/detalle-max-hr-m-full",
                "tendencias/detalle-energy-kcal-m-full",
                "tendencias/detalle-vo2max-m-full",
                "tendencias/detalle-recovery-m-full",
                "tendencias/detalle-hrv-m-full",
                "tendencias/detalle-rhr-m-full",
                "tendencias/detalle-resp-rate-m-full",
                "tendencias/detalle-spo2-m-full",
                "tendencias/detalle-skin-temp-m-full",
                "tendencias/detalle-sleep-performance-m-full",
                "tendencias/detalle-in-bed-min-m-full",
                "tendencias/detalle-sleep-total-min-m-full",
                "tendencias/detalle-hours-vs-needed-pct-m-full",
                "tendencias/detalle-sleep-consistency-m-full",
                "tendencias/detalle-restorative-pct-m-full",
                "tendencias/detalle-restorative-min-m-full",
                "tendencias/detalle-sleep-efficiency-m-full",
                "tendencias/detalle-sleep-deep-min-m-full",
                "tendencias/detalle-sleep-rem-min-m-full",
                "tendencias/detalle-sleep-light-min-m-full",
                "tendencias/detalle-sleep-need-min-m-full",
                "tendencias/detalle-sleep-debt-min-m-full",
                "tendencias/detalle-strain-m-full",
                "tendencias/detalle-steps-m-full",
                "tendencias/detalle-hr-zones13-min-m-full",
                "tendencias/detalle-hr-zones45-min-m-full",
                "tendencias/detalle-hr-zones-all-min-m-full",
                "tendencias/detalle-strength-min-m-full",
                "tendencias/detalle-active-kcal-m-full",
                "tendencias/detalle-weight-m-full",
                "tendencias/detalle-body-fat-m-full",
                "tendencias/detalle-lean-mass-m-full",
                "tendencias/detalle-bmi-m-full",
                "tendencias/detalle-stress-m-full",
                "tendencias/detalle-heart-rate-m-full",
            ]
        ),
        Funcionalidad(
            id: .tendenciasDeporte,
            pestana: .tendencias,
            requiere: [.watch, .entrenos],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85",
            mapa: ["tendencias/actividad-full", "tendencias/actividad-vacio"]
        ),
        Funcionalidad(
            id: .tendenciasLongevidad,
            pestana: .tendencias,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85",
            mapa: [
                "tendencias/detalle-vo2max-m-full",
                "tendencias/edad-fisica-full",
                "tendencias/edad-fisica-vacio",
                "tendencias/edad-corporal-full",
                "tendencias/edad-corporal-vacio",
            ]
        ),
        Funcionalidad(
            id: .tendenciasFuentes,
            pestana: .tendencias,
            requiere: [],
            piezas: [.ayuda(seccion: .tendencias)],
            desde: "1.85",
            mapa: []
        ),
    ]
}
