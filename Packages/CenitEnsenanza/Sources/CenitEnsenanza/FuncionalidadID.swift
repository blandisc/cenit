// Los 68 ids estables del registro (épico FER-428, L4/FER-430). Un id nunca se
// renombra: también es el `id` de su `Tip` (TipKit lo pide así). Archivo generado por
// `Tools/gen-ensenanza.py` a partir de `Tools/ensenanza-semilla.json` — no editar a mano
// sin regenerar. SOLO este enum vive aquí: es el archivo que
// `Tools/check-ensenanza.py` grepea con
// `^\s*case\s+\w+\s*=\s*"([a-z][a-z0-9-]*(?:\.[a-z0-9-]+)+)"` para saber qué ids existen.
public enum FuncionalidadID: String, CaseIterable, Sendable {
    // MARK: - Hoy

    case hoyPalabra = "hoy.palabra"
    case hoyActa = "hoy.acta"
    case hoyCalibracion = "hoy.calibracion"
    case hoyPrimerVeredicto = "hoy.primer-veredicto"
    case hoyBaseFirme = "hoy.base-firme"
    case hoyEcosistema = "hoy.ecosistema"
    case hoyEjeAutonomico = "hoy.eje-autonomico"
    case hoyGuardian = "hoy.guardian"
    case hoyManuales = "hoy.manuales"
    case hoyMatriz = "hoy.matriz"
    case hoyScrub = "hoy.scrub"
    case hoyHojaMetrica = "hoy.hoja-metrica"
    case hoyTuPatron = "hoy.tu-patron"
    case hoyDetalleRico = "hoy.detalle-rico"
    case hoyAvisoMalestar = "hoy.aviso-malestar"
    case hoyFranjas = "hoy.franjas"
    case hoySincronizar = "hoy.sincronizar"
    case hoySinDatos = "hoy.sin-datos"

    // MARK: - Tendencias

    case tendenciasPestana = "tendencias.pestana"
    case tendenciasPeriodo = "tendencias.periodo"
    case tendenciasPreparacion = "tendencias.preparacion"
    case tendenciasDescansoCarga = "tendencias.descanso-carga"
    case tendenciasMapaDelDia = "tendencias.mapa-del-dia"
    case tendenciasCarga = "tendencias.carga"
    case tendenciasVitales = "tendencias.vitales"
    case tendenciasComparar = "tendencias.comparar"
    case tendenciasExplorar = "tendencias.explorar"
    case tendenciasDeporte = "tendencias.deporte"
    case tendenciasLongevidad = "tendencias.longevidad"
    case tendenciasFuentes = "tendencias.fuentes"

    // MARK: - Entrenar

    case entrenarPestana = "entrenar.pestana"
    case entrenarPrimerUso = "entrenar.primer-uso"
    case entrenarTaller = "entrenar.taller"
    case entrenarHero = "entrenar.hero"
    case entrenarOtraForma = "entrenar.otra-forma"
    case entrenarMosaico = "entrenar.mosaico"
    case entrenarPlan = "entrenar.plan"
    case entrenarProgresion = "entrenar.progresion"
    case entrenarRir = "entrenar.rir"
    case entrenarAmrapDrop = "entrenar.amrap-drop"
    case entrenarDescanso = "entrenar.descanso"
    case entrenarBiblioteca = "entrenar.biblioteca"
    case entrenarImportarPlan = "entrenar.importar-plan"
    case entrenarImportarCsv = "entrenar.importar-csv"
    case entrenarSesionViva = "entrenar.sesion-viva"
    case entrenarEsfuerzoEstimado = "entrenar.esfuerzo-estimado"
    case entrenarRecibo = "entrenar.recibo"
    case entrenarHistorial = "entrenar.historial"
    case entrenarMarcas = "entrenar.marcas"
    case entrenarMapaMuscular = "entrenar.mapa-muscular"
    case entrenarRespiraIntervalos = "entrenar.respira-intervalos"

    // MARK: - Ajustes

    case ajustesPerfil = "ajustes.perfil"
    case ajustesFuentes = "ajustes.fuentes"
    case ajustesRespaldo = "ajustes.respaldo"
    case ajustesVigilancia = "ajustes.vigilancia"
    case ajustesAvisos = "ajustes.avisos"
    case ajustesHistorialFa = "ajustes.historial-fa"
    case ajustesSesion = "ajustes.sesion"
    case ajustesExperimental = "ajustes.experimental"
    case ajustesAnimaciones = "ajustes.animaciones"
    case ajustesAyuda = "ajustes.ayuda"
    case ajustesNovedades = "ajustes.novedades"
    case ajustesApariencia = "ajustes.apariencia"

    // MARK: - Transversal

    case transversalWidgets = "transversal.widgets"
    case transversalLiveActivity = "transversal.live-activity"
    case transversalWatch = "transversal.watch"
    case transversalAvisos = "transversal.avisos"
    case transversalGestos = "transversal.gestos"
}
