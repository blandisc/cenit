import Foundation

// Entradas de la pestaña «cuerpo» (ex-tendencias) del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let tendencias: [Funcionalidad] = [
        Funcionalidad(
            id: .tendenciasPestana,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .hito(id: "tendencias.pestana.primera-tendencia"), .vacio(clave: "vacio.tendencias.pasos.queEs")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasPeriodo,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "tendencias.periodo")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasPreparacion,
            pestana: .cuerpo,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "tendencias.preparacion"), .vacio(clave: "vacio.tendencias.heroe.queEs")],
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
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/sueno", "hoy/esfuerzo", "hoy/estres"]
        ),
        Funcionalidad(
            id: .tendenciasMapaDelDia,
            pestana: .cuerpo,
            requiere: [.watch, .permiso(.calendario)],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "tendencias.mapa-del-dia")],
            desde: "1.85",
            mapa: ["hoy/estres"]
        ),
        Funcionalidad(
            id: .tendenciasCarga,
            pestana: .cuerpo,
            requiere: [.entrenos],
            piezas: [.ayuda(seccion: .cuerpo), .hito(id: "tendencias.carga.leida")],
            desde: "1.85",
            mapa: ["tendencias/cuerpo-m"]
        ),
        Funcionalidad(
            id: .tendenciasVitales,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .cuerpo), .vacio(clave: "vacio.detalle.tendencia.queEs"), .vacio(clave: "vacio.detalle.anoche.queEs"), .vacio(clave: "vacio.detalle.hoy.queEs")],
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
            id: .tendenciasExplorar,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "tendencias.explorar"), .vacio(clave: "vacio.detalle.tendencia.queEs")],
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
            id: .tendenciasFuentes,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: []
        ),
    ]
}
