import Foundation

// Entradas de la pestaña «cuerpo» (ex-hoy) del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let hoy: [Funcionalidad] = [
        Funcionalidad(
            id: .hoyPalabra,
            pestana: .cuerpo,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: [
                "hoy/apunto",
                "hoy/exigido",
                "hoy/equilibrado",
                "hoy/desgastado",
                "onboarding/lectura-full",
                "onboarding/lectura-caution",
                "onboarding/lectura-easy",
                "onboarding/lectura-lowsignal",
            ]
        ),
        Funcionalidad(
            id: .hoyActa,
            pestana: .cuerpo,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/veredicto-acta", "onboarding/acta"]
        ),
        Funcionalidad(
            id: .hoyCalibracion,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/calibrando", "onboarding/calibrando"]
        ),
        Funcionalidad(
            id: .hoyPrimerVeredicto,
            pestana: .cuerpo,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .cuerpo), .hito(id: "hoy.primer-veredicto")],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyBaseFirme,
            pestana: .cuerpo,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .cuerpo), .hito(id: "hoy.base-firme")],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyEjeAutonomico,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/autonomico"]
        ),
        Funcionalidad(
            id: .hoyGuardian,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/guardian"]
        ),
        Funcionalidad(
            id: .hoyManuales,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "hoy.manuales")],
            desde: "1.85",
            mapa: ["hoy/decide-manual", "hoy/contexto-manual"]
        ),
        Funcionalidad(
            id: .hoyMatriz,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/apunto", "hoy/exigido", "hoy/equilibrado", "hoy/desgastado"]
        ),
        Funcionalidad(
            id: .hoyScrub,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [
                .ayuda(seccion: .cuerpo),
                .tip(id: "hoy.scrub"),
                .gestoConBoton(gesto: "tip.hoy.scrub.gesto", boton: "tip.hoy.scrub.boton"),
            ],
            desde: "1.85",
            mapa: ["hoy/apunto", "hoy/exigido", "hoy/equilibrado", "hoy/desgastado"]
        ),
        Funcionalidad(
            id: .hoyHojaMetrica,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .tip(id: "hoy.hoja-metrica"), .vacio(clave: "vacio.hoja-metrica.tendencia.queEs"), .vacio(clave: "vacio.hoja-metrica.fc-hoy.queEs")],
            desde: "1.85",
            mapa: [
                "hoy/metrica-hrv",
                "hoy/metrica-rhr",
                "hoy/metrica-steps",
                "hoy/metrica-sleep",
                "hoy/metrica-resp-rate",
                "hoy/metrica-heart-rate",
                "hoy/metrica-spo2",
                "hoy/metrica-vo2max",
                "hoy/carga",
            ]
        ),
        Funcionalidad(
            id: .hoyTuPatron,
            pestana: .cuerpo,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/metrica-hrv", "hoy/metrica-rhr"]
        ),
        Funcionalidad(
            id: .hoyDetalleRico,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo), .vacio(clave: "vacio.sueno.tendencia.queEs"), .vacio(clave: "vacio.sueno.anoche.queEs")],
            desde: "1.85",
            mapa: ["hoy/sueno", "hoy/esfuerzo", "hoy/estres", "hoy/temperatura"]
        ),
        Funcionalidad(
            id: .hoyAvisoMalestar,
            pestana: .cuerpo,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyFranjas,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/t3-leyendo", "hoy/t3-sin-sync", "hoy/t3-noche-no-registrada"]
        ),
        Funcionalidad(
            id: .hoySincronizar,
            pestana: .cuerpo,
            requiere: [.permiso(.salud)],
            piezas: [
                .ayuda(seccion: .cuerpo),
                .tip(id: "hoy.sincronizar"),
                .gestoConBoton(gesto: "tip.hoy.sincronizar.gesto", boton: "tip.hoy.sincronizar.boton"),
            ],
            desde: "1.85",
            mapa: ["hoy/t3-sin-sync"]
        ),
        Funcionalidad(
            id: .hoySinDatos,
            pestana: .cuerpo,
            requiere: [],
            piezas: [.ayuda(seccion: .cuerpo)],
            desde: "1.85",
            mapa: ["hoy/vacio", "hoy/t4-sin-permiso", "hoy/t5-dormido"]
        ),
    ]
}
