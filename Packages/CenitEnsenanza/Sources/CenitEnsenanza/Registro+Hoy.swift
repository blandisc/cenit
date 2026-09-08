import Foundation

// Entradas de la pestaña «hoy» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
// FER-433: las piezas `.vacio(clave:)` se añadieron a mano (el generador aún no las conoce).
// FER-439: `mapa:` (nodos del Mapa 100 %) se añadió a mano con el formato exacto que emite el generador.
extension Registro {
    public static let hoy: [Funcionalidad] = [
        Funcionalidad(
            id: .hoyPalabra,
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy)],
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
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/veredicto-acta", "onboarding/acta"]
        ),
        Funcionalidad(
            id: .hoyCalibracion,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/calibrando", "onboarding/calibrando"]
        ),
        Funcionalidad(
            id: .hoyPrimerVeredicto,
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy), .hito(id: "hoy.primer-veredicto")],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyBaseFirme,
            pestana: .hoy,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .hoy), .hito(id: "hoy.base-firme")],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyEcosistema,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [
                .ayuda(seccion: .hoy),
                .tip(id: "hoy.ecosistema"),
                .gestoConBoton(gesto: "tip.hoy.ecosistema.gesto", boton: "tip.hoy.ecosistema.boton"),
            ],
            desde: "1.85",
            mapa: ["hoy/apunto", "hoy/exigido", "hoy/equilibrado", "hoy/desgastado"]
        ),
        Funcionalidad(
            id: .hoyEjeAutonomico,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/autonomico"]
        ),
        Funcionalidad(
            id: .hoyGuardian,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/guardian"]
        ),
        Funcionalidad(
            id: .hoyManuales,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy), .tip(id: "hoy.manuales")],
            desde: "1.85",
            mapa: ["hoy/decide-manual", "hoy/contexto-manual"]
        ),
        Funcionalidad(
            id: .hoyMatriz,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/apunto", "hoy/exigido", "hoy/equilibrado", "hoy/desgastado"]
        ),
        Funcionalidad(
            id: .hoyScrub,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [
                .ayuda(seccion: .hoy),
                .tip(id: "hoy.scrub"),
                .gestoConBoton(gesto: "tip.hoy.scrub.gesto", boton: "tip.hoy.scrub.boton"),
            ],
            desde: "1.85",
            mapa: ["hoy/apunto", "hoy/exigido", "hoy/equilibrado", "hoy/desgastado"]
        ),
        Funcionalidad(
            id: .hoyHojaMetrica,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy), .tip(id: "hoy.hoja-metrica"), .vacio(clave: "vacio.hoja-metrica.tendencia.queEs"), .vacio(clave: "vacio.hoja-metrica.fc-hoy.queEs")],
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
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/metrica-hrv", "hoy/metrica-rhr"]
        ),
        Funcionalidad(
            id: .hoyDetalleRico,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy), .vacio(clave: "vacio.sueno.tendencia.queEs"), .vacio(clave: "vacio.sueno.anoche.queEs")],
            desde: "1.85",
            mapa: ["hoy/sueno", "hoy/esfuerzo", "hoy/estres", "hoy/temperatura"]
        ),
        Funcionalidad(
            id: .hoyAvisoMalestar,
            pestana: .hoy,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: []
        ),
        Funcionalidad(
            id: .hoyFranjas,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/t3-leyendo", "hoy/t3-sin-sync", "hoy/t3-noche-no-registrada"]
        ),
        Funcionalidad(
            id: .hoySincronizar,
            pestana: .hoy,
            requiere: [.permiso(.salud)],
            piezas: [
                .ayuda(seccion: .hoy),
                .tip(id: "hoy.sincronizar"),
                .gestoConBoton(gesto: "tip.hoy.sincronizar.gesto", boton: "tip.hoy.sincronizar.boton"),
            ],
            desde: "1.85",
            mapa: ["hoy/t3-sin-sync"]
        ),
        Funcionalidad(
            id: .hoySinDatos,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85",
            mapa: ["hoy/vacio", "hoy/t4-sin-permiso", "hoy/t5-dormido"]
        ),
    ]
}
