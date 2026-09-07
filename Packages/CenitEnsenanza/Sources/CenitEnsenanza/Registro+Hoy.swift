import Foundation

// Entradas de la pestaña «hoy» del registro (semilla del épico FER-428, L4/FER-430).
// Generado por `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json`.
extension Registro {
    public static let hoy: [Funcionalidad] = [
        Funcionalidad(
            id: .hoyPalabra,
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyActa,
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyCalibracion,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyPrimerVeredicto,
            pestana: .hoy,
            requiere: [.watch, .noches(4)],
            piezas: [.ayuda(seccion: .hoy), .hito(id: "hoy.primer-veredicto")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyBaseFirme,
            pestana: .hoy,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .hoy), .hito(id: "hoy.base-firme")],
            desde: "1.85"
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
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyEjeAutonomico,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyGuardian,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyManuales,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy), .tip(id: "hoy.manuales")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyMatriz,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
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
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyHojaMetrica,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy), .tip(id: "hoy.hoja-metrica")],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyTuPatron,
            pestana: .hoy,
            requiere: [.watch],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyDetalleRico,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyAvisoMalestar,
            pestana: .hoy,
            requiere: [.watch, .noches(14)],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoyFranjas,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
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
            desde: "1.85"
        ),
        Funcionalidad(
            id: .hoySinDatos,
            pestana: .hoy,
            requiere: [],
            piezas: [.ayuda(seccion: .hoy)],
            desde: "1.85"
        ),
    ]
}
