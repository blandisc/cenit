#if os(iOS)
import SwiftUI
import CenitDesign
import CenitTraining
import CenitAnalytics
import CenitStore   // `WorkoutRow` — destino de detalle de actividad en la hoja de Progreso

// MARK: - CEN-43 · La raíz es la sesión (antes / durante / después)
//
// Decisión del dueño 2026-10-15 «Camino C+» (docs/DECISIONS.md): la sesión ES la app. Esta vista
// reemplaza a `RootTabView` como primera vista; el dock deja de montarse. Tres estados:
//
//   · ANTES   — la rutina de hoy con su «siguiente paso» por ejercicio (lo que ya calcula
//               `ProgressionPlanner` vía `repo.seedTodaySlots`, el MISMO método que usa el hub y el
//               reloj) y «Empezar». Sin rutina de hoy cae en el hub de Entrenar tal cual existe (la
//               puerta de plan: plantillas / importar / crear, y el descanso).
//   · DURANTE — la sesión en vivo existente (`RoutineSheet(.live)`) en pantalla completa.
//   · DESPUÉS — el acta existente dentro de esa misma sesión; su «Listo» cierra la sesión y deja la
//               raíz en ANTES (con la rutina de mañana o «hoy ya entrenaste»).
//
// Plan, Progreso y Ajustes son HOJAS desde ANTES, sin pestañas. Las pantallas de salud (Hoy, Cuerpo,
// Tendencias…) siguen en el árbol pero ya nada navega a ellas; se borran en la ola 0 · E.

struct FuerzaRootView: View {
    /// Hojas que abre ANTES. `Identifiable` para `.sheet(item:)`.
    private enum Hoja: Identifiable {
        case plan(abrir: RoutineEditorRoute?)
        case progreso(abrir: AnyHashable?)
        case ajustes

        var id: String {
            switch self {
            case .plan: return "plan"
            case .progreso: return "progreso"
            case .ajustes: return "ajustes"
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var tabRouter: TabRouter

    @State private var hoja: Hoja?
    /// El ✕ de la píldora pide confirmación aquí (pantalla completa), no en el frame de la píldora.
    @State private var confirmDiscardSession = false

    var body: some View {
        NavigationStack {
            FuerzaAntes(
                abrirPlan: { hoja = .plan(abrir: nil) },
                abrirRutina: { id in hoja = .plan(abrir: .routine(routineId: id)) },
                abrirProgreso: { hoja = .progreso(abrir: nil) },
                abrirAjustes: { hoja = .ajustes })
        }
        .activeSessionPillInset(model: appModel, confirmDiscard: $confirmDiscardSession)
        .tint(LiquidColor.verdePrimario)
        .sheet(item: $hoja) { hoja in contenido(de: hoja) }
        .modifier(FuerzaSesionEnVivo(confirmDiscardSession: $confirmDiscardSession))
        .modifier(FuerzaPermisoSalud())
        .modifier(FuerzaEntradas(abrirProgreso: { ruta in hoja = .progreso(abrir: ruta) }))
    }

    @ViewBuilder
    private func contenido(de hoja: Hoja) -> some View {
        switch hoja {
        case .plan(let abrir): FuerzaHojaPlan(abrir: abrir)
        case .progreso(let abrir): FuerzaHojaProgreso(abrir: abrir)
        case .ajustes: FuerzaHojaAjustes()
        }
    }
}

// MARK: - Durante / Después · la sesión en vivo

/// La sesión guiada de fuerza: un `fullScreenCover` sobre la raíz, más el confirm del ✕ de la píldora.
/// Misma composición que `RootTabView.rootChromeCovers` (FER-347/716): la sesión vive en `AppModel`, así
/// que cerrar el cover solo la minimiza (la píldora la reabre); el acta se cierra con
/// `closeStrengthSummary` en su «Listo», y ese cierre es el regreso a ANTES.
private struct FuerzaSesionEnVivo: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var tabRouter: TabRouter
    @Binding var confirmDiscardSession: Bool

    func body(content: Content) -> some View {
        @Bindable var appModel = appModel
        return content
            .liquidConfirm(
                isPresented: $confirmDiscardSession,
                title: String(localized: "Discard the workout?"),
                context: String(localized: "SESSION · IN PROGRESS"),
                message: String(localized: "You'll lose \(appModel.strengthSession?.doneCount ?? 0) logged set(s) today. This can't be undone."),
                actions: [
                    .init(String(localized: "Keep training"), role: .primary),
                    .init(String(localized: "Discard session"), role: .destructive) {
                        appModel.endStrengthSession(save: false)
                    }
                ]
            )
            .animation(LiquidMotion.suave, value: appModel.strengthSheetPresented)
            .animation(LiquidMotion.suave, value: appModel.strengthSession == nil)
            .fullScreenCover(isPresented: $appModel.strengthSheetPresented, onDismiss: {
                if appModel.strengthSession?.summary != nil { appModel.closeStrengthSummary() }
            }) {
                if appModel.strengthSession != nil {
                    RoutineSheet(origin: .today(routineId: appModel.strengthSession?.routineId), mode: .live)
                        .environment(appModel)
                        .environmentObject(tabRouter)
                }
            }
    }
}

// MARK: - El permiso de Apple Salud, al cerrar la primera sesión

/// CEN-44 · Camino C+: Apple Salud sale de la puerta de entrada. Ni el onboarding ni el arranque piden
/// nada; el permiso se ofrece UNA vez, en el momento en que la primera sesión de fuerza cierra su acta
/// (el paso de DESPUÉS a ANTES), con una tarjeta que dice qué se guarda y qué se lee. «Continuar» abre
/// el diálogo del sistema (`HealthKitBridge.requestAuthorization`: escribir entreno + energía activa,
/// leer FC, FC en reposo y sueño); «Ahora no» lo deja para Ajustes › Fuentes de datos › Conectar Apple
/// Health. Sin permiso, la sesión y la progresión funcionan completas. Quien ya conectó Salud (usuarios
/// de antes) o no tiene Salud no ve la tarjeta.
private struct FuerzaPermisoSalud: ViewModifier {
    /// Ya se mostró la tarjeta (se acepte o no): nunca se vuelve a ofrecer sola.
    static let ofrecidoKey = "health.firstSessionPromptShown"

    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var health: HealthKitBridge
    @State private var ofrecer = false

    func body(content: Content) -> some View {
        content
            .onChange(of: appModel.actasCerradas) { _, _ in
                guard health.auth == .unknown,
                      !UserDefaults.standard.bool(forKey: Self.ofrecidoKey) else { return }
                UserDefaults.standard.set(true, forKey: Self.ofrecidoKey)
                ofrecer = true
            }
            .liquidConfirm(
                isPresented: $ofrecer,
                title: String(localized: "Save your workouts in Apple Health?"),
                context: String(localized: "FIRST SESSION · DONE"),
                message: String(localized: "Cénit saves each workout and its active energy in Apple Health, and reads your heart rate, resting heart rate and sleep. Nothing leaves your iPhone. If you skip it, you can do it later in Settings › Data Sources."),
                actions: [
                    .init(String(localized: "Continue"), role: .primary) {
                        Task { await health.requestAuthorization() }
                    },
                    .init(String(localized: "Not now"))
                ]
            )
    }
}

// MARK: - Entradas externas (widget, Live Activity, reloj, «Ver mapa» del acta)

/// Lo que antes resolvía `RootTabView` con selección de pestañas, ahora sin pestañas: cada entrada
/// cae en ANTES o DURANTE, o abre la hoja de Progreso con su destino.
private struct FuerzaEntradas: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var tabRouter: TabRouter
    let abrirProgreso: (AnyHashable) -> Void

    func body(content: Content) -> some View {
        content
            // `cenit://session` — el deep link de la Live Activity de descanso (FER-398). Con sesión
            // viva reabre la hoja (DURANTE); sin ella no hace nada: la raíz ya es ANTES.
            .onOpenURL { url in
                guard url.scheme == "cenit", url.host == "session" else { return }
                appModel.resumeStrengthSession()   // ya es un no-op sin sesión viva
            }
            // Peticiones de pestaña de pantallas viejas (Cuerpo, Ayuda, onboarding): ya no hay pestañas.
            // Se consumen para que no queden pendientes; la raíz es la única «pestaña».
            .onReceive(tabRouter.$requested.compactMap { $0 }) { _ in tabRouter.requested = nil }
            // FER-810: «Ver recibo en iPhone» desde el reloj → el detalle de esa sesión en Progreso.
            .onChange(of: appModel.pendingReceiptRoute, initial: true) { _, route in
                guard let route else { return }
                abrirProgreso(AnyHashable(route))
                appModel.pendingReceiptRoute = nil
            }
            // FER-186: «Ver mapa» del acta → «Tu cuerpo» (el mapa de músculos) en Progreso.
            .onChange(of: tabRouter.openMuscleMapInTrain, initial: true) { _, abrir in
                guard abrir else { return }
                abrirProgreso(AnyHashable(MuscleVolumeRoute()))
                tabRouter.openMuscleMapInTrain = false
            }
    }
}

// MARK: - ANTES

/// La rutina de hoy tal como toca. Carga con los MISMOS métodos del repositorio que el hub de Entrenar
/// (`routines` / `routineSchedule` / `programServing` / `seedTodaySlots`); no deriva nada por su cuenta.
private struct FuerzaAntes: View {
    /// La rutina de hoy ya sembrada: lo que el usuario va a hacer y de dónde sale cada «siguiente paso».
    private struct HoyPlan {
        let routine: Routine
        let slots: [StrengthSessionModel.PlanSlot]
        let serving: ProgramServing.Context?
        let advice: TrainingRegulation.Advice
        let tono: LiquidTono
    }

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(AppModel.self) private var appModel
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw: String = UnitSystem.metric.rawValue

    let abrirPlan: () -> Void
    let abrirRutina: (String) -> Void
    let abrirProgreso: () -> Void
    let abrirAjustes: () -> Void

    @State private var cargado = false
    @State private var hoy: HoyPlan?
    /// Hoy ya hay una sesión terminada de la rutina de hoy (el acta cerró): «hoy ya entrenaste».
    @State private var yaEntrenaste = false
    /// «Siguiente: Pierna · jueves» — la próxima rutina del plan después de hoy.
    @State private var siguiente: String?
    /// Un «Empezar» del widget / Siri llegó antes de que terminara la carga.
    @State private var iniciarAlCargar = false
    /// El temporizador de intervalos (puerta «Otra forma» del descanso) se abre como hoja.
    @State private var mostrarIntervalos = false

    private var unitSystem: UnitSystem { .init(rawValue: unitSystemRaw) ?? .metric }
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) }

    var body: some View {
        // Con rutina de hoy (aún sin entrenar) o «hoy ya entrenaste»: la pantalla de ANTES. Sin rutina hoy
        // (primer uso, sin plan, descanso, error): el hub de Entrenar, que ya trae la puerta de plan
        // (plantillas / importar / crear) y el descanso, sin pasos nuevos.
        Group {
            if !cargado {
                Color.clear   // un instante: la lectura es local y casi inmediata
            } else if let hoy, !yaEntrenaste {
                antes(hoy)
            } else if hoy != nil {
                hoyYaEntrenaste
            } else {
                hubDePlan
            }
        }
        .pantallaFondo()
        .task(id: repo.refreshSeq) { await cargar() }
        // Al volver de una sesión (el acta cerró): la rutina de mañana o «hoy ya entrenaste».
        .onChange(of: appModel.strengthSession == nil) { _, sinSesion in
            if sinSesion { Task { await cargar() } }
        }
        .sheet(isPresented: $mostrarIntervalos) {
            NavigationStack { IntervalTimerView().fuerzaHoja(cerrar: { mostrarIntervalos = false }) }
        }
        .onAppear { atenderPeticiones() }
        .onChange(of: tabRouter.startTodaySession) { _, pide in if pide { atenderPeticiones() } }
        .onChange(of: tabRouter.startRoutineId) { _, id in if id != nil { atenderPeticiones() } }
    }

    // MARK: Estados

    /// ANTES con rutina: cabecera, la sesión de hoy, «Empezar» y las tres hojas.
    private func antes(_ h: HoyPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                cabecera
                EntrenarModulo(tono: h.tono, intensidad: EntrenarHubMetrics.heroIntensidad,
                               insets: EntrenarHubMetrics.heroInsets) {
                    VStack(alignment: .leading, spacing: .zero) {
                        kicker(h).entrenarCabeceraKicker().foregroundStyle(h.tono.rotulo)
                        Text(verbatim: h.routine.name)
                            .font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                            .foregroundStyle(LiquidColor.tinta900)
                            .lineLimit(2).minimumScaleFactor(0.7)
                            .padding(.top, EntrenarHubMetrics.heroKickerToTituloTop)
                        Text(verbatim: meta(h))
                            .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                            .padding(.top, EntrenarHubMetrics.heroTituloToMetaTop)
                        ForEach(Array(h.slots.enumerated()), id: \.offset) { _, slot in
                            fila(slot)
                        }
                        .padding(.top, LiquidSpace.s300)
                        LiquidGlassButton(String(localized: "Start"), variant: .primary, expands: true) { empezar() }
                            .accessibilityIdentifier("fuerza.empezar")
                            .padding(.top, LiquidSpace.s400)
                    }
                }
                .padding(.top, EntrenarMetrics.heroKickerTop)
                hojas.padding(.top, LiquidSpace.s600)
            }
            .padding(.top, LiquidSpace.pestanaContenidoTop)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// «Hoy ya entrenaste» — después del acta. Un toque por la rutina que viene, y las tres hojas.
    private var hoyYaEntrenaste: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                cabecera
                EntrenarModulo(tono: .neutro, intensidad: EntrenarHubMetrics.heroIntensidad,
                               insets: EntrenarHubMetrics.heroInsets) {
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(String(localized: "fuerza.antes.hecho.titulo", defaultValue: "You already trained today"))
                            .font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                            .foregroundStyle(LiquidColor.tinta900)
                            .fixedSize(horizontal: false, vertical: true)
                        if let siguiente {
                            Text(verbatim: siguiente)
                                .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                                .padding(.top, EntrenarHubMetrics.heroTituloToMetaTop)
                        }
                    }
                }
                .padding(.top, EntrenarMetrics.heroKickerTop)
                hojas.padding(.top, LiquidSpace.s600)
            }
            .padding(.top, LiquidSpace.pestanaContenidoTop)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Sin rutina de hoy: el hub de Entrenar existente (puerta de plan o descanso). Sus cierres abren las
    /// hojas de la raíz en vez de empujar a un `NavigationStack` de pestaña.
    private var hubDePlan: some View {
        EntrenarView(
            openRoutine: abrirRutina,
            openBreathe: nil, openIntervals: { mostrarIntervalos = true },
            openHistory: abrirProgreso,
            openWeeklyPlan: abrirPlan,
            openRoutines: abrirPlan,
            openWorkoutSession: { _ in abrirProgreso() },
            openMuscleMap: abrirProgreso,
            openMarcas: abrirProgreso,
            onPlanLoaded: { Task { await cargar() } },
            ocultarRecuperacion: true)
            // Plan · Progreso · Ajustes en TODO estado de la raíz (sin esto, sin rutina hoy Ajustes y
            // Progreso quedaban inalcanzables).
            .safeAreaInset(edge: .bottom, spacing: .zero) {
                hojas
                    .padding(.horizontal, LiquidSpace.s600)
                    .padding(.vertical, LiquidSpace.s300)
                    .background(LiquidColor.fondoAlto)
            }
    }

    // MARK: Piezas

    private var cabecera: some View {
        Text(String(localized: "Train · \(CenitFormat.weekdayHeading(Date()))"))
            .liquidKicker()
            .foregroundStyle(LiquidColor.tinta700)
    }

    /// Plan · Progreso · Ajustes: hojas desde ANTES, sin pestañas.
    private var hojas: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(String(localized: "Your plan"),
                              variant: .quiet, action: abrirPlan)
                .accessibilityIdentifier("fuerza.plan")
            LiquidGlassButton(String(localized: "Progress"), variant: .quiet, action: abrirProgreso)
                .accessibilityIdentifier("fuerza.progreso")
            LiquidGlassButton(String(localized: "Settings"), variant: .quiet, action: abrirAjustes)
                .accessibilityIdentifier("fuerza.ajustes")
        }
    }

    /// «Hoy · tu sesión», o «Semana ligera · N de M» en la última semana de un programa.
    private func kicker(_ h: HoyPlan) -> Text {
        guard let serving = h.serving, serving.isLight else { return Text("Today · your session") }
        return Text("Light week · \(serving.position.week) of \(serving.program.weeks)")
    }

    /// «6 ejercicios · 18 series · ~50 min · Pecho · Hombro» — la forma de la sesión y los músculos.
    private func meta(_ h: HoyPlan) -> String {
        let sets = h.slots.reduce(0) { $0 + max(0, $1.re.targetSets) }
        var parts = [String(localized: "\(h.slots.count) exercises")]
        if sets > 0 { parts.append(String(localized: "\(sets) sets")) }
        let minutos = estimarMinutos(h.slots)
        if minutos > 0 { parts.append(String(localized: "~\(minutos) min")) }
        var vistos = Set<String>()
        let musculos = h.slots.compactMap { $0.exercise?.primaryMuscles.first }
            .filter { vistos.insert($0).inserted }
            .prefix(3).map(StrengthDisplay.muscle)
        parts.append(contentsOf: musculos)
        return parts.joined(separator: " · ")
    }

    /// Misma aproximación transparente que el hub (`EntrenarLanding.estMinutes`): series planeadas ×
    /// ~40 s de trabajo + el descanso del slot, redondeado a 5 min. Un vistazo, no un reloj.
    private func estimarMinutos(_ slots: [StrengthSessionModel.PlanSlot]) -> Int {
        guard !slots.isEmpty else { return 0 }
        var sec = 0
        for s in slots {
            let rest = s.re.restMode == .fixed ? s.re.restSeconds : 90
            sec += max(1, s.re.targetSets) * (40 + rest)
        }
        return max(5, Int((Double(sec) / 60 / 5).rounded()) * 5)
    }

    /// Un ejercicio: nombre, receta y su «siguiente paso».
    private func fila(_ slot: StrengthSessionModel.PlanSlot) -> some View {
        let paso = siguientePaso(slot)
        return VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                Text(verbatim: slot.exercise.map(StrengthDisplay.name) ?? slot.re.exerciseId)
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(2)
                Spacer(minLength: LiquidSpace.s200)
                if let receta = receta(slot) {
                    Text(verbatim: receta)
                        .font(LiquidType.captionLectura).monospacedDigit()
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            paso.texto
                .font(LiquidType.captionLectura)
                .foregroundStyle(paso.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, LiquidSpace.s150)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// «3 × 8» cuando la receta trae series y repeticiones.
    private func receta(_ slot: StrengthSessionModel.PlanSlot) -> String? {
        guard slot.re.targetSets > 0 else { return nil }
        guard let reps = slot.re.targetReps else { return "\(slot.re.targetSets)" }
        return "\(slot.re.targetSets) × \(reps)"
    }

    /// El «siguiente paso» de un ejercicio, tal como lo calculó `ProgressionPlanner` al sembrar el slot:
    /// subida aplicada → «Sube a X»; subida ganada que hoy se retiene, o ritmo al límite → «Mantén X»;
    /// si no, el peso de la última vez; sin historia, «Primera vez». Nunca decide: solo lee el slot.
    private func siguientePaso(_ slot: StrengthSessionModel.PlanSlot) -> (texto: Text, color: Color) {
        if let raise = slot.raise {
            if raise.waiting {
                return (Text(String(format: String(localized: "fuerza.paso.mantiene", defaultValue: "Keep %@"),
                                    StrengthDisplay.weight(raise.fromKg, system: unitSystem))),
                        LiquidTono.ambar.rotulo)
            }
            return (Text(String(format: String(localized: "fuerza.paso.sube", defaultValue: "Raise to %@"),
                                StrengthDisplay.weight(raise.toKg, system: unitSystem))),
                    LiquidColor.verdeProfundo)
        }
        if case .atLimitHold(let kg)? = slot.raiseRhythmNote {
            return (Text(String(format: String(localized: "fuerza.paso.mantiene", defaultValue: "Keep %@"),
                                StrengthDisplay.weight(kg, system: unitSystem))),
                    LiquidTono.ambar.rotulo)
        }
        if let last = slot.lastSets.first {
            if let kg = last.weightKg, kg > 0 {
                return (Text(String(format: String(localized: "fuerza.paso.ultima", defaultValue: "Last time: %@"),
                                    StrengthDisplay.weight(kg, system: unitSystem))),
                        LiquidColor.tinta500)
            }
            if let reps = last.reps, reps > 0 {
                return (Text(String(format: String(localized: "fuerza.paso.ultima", defaultValue: "Last time: %@"),
                                    String(localized: "\(reps) reps"))),
                        LiquidColor.tinta500)
            }
        }
        return (Text(String(localized: "fuerza.paso.primera", defaultValue: "First time · find your weight")),
                LiquidColor.tinta500)
    }

    // MARK: Empezar

    /// «Empezar»: arranca la sesión con los slots sembrados. Si el consejo cambió desde la siembra
    /// (llegó tarde), se resiembra UNA vez antes — un intento, y luego se arranca pase lo que pase (FER-82).
    private func empezar() {
        guard let plan = hoy else { return }
        Task {
            var actual = plan
            if plan.advice != repo.trainingAdvice {
                if await cargar(), let nuevo = hoy {
                    actual = nuevo
                } else if !TrainingRegulation.allowsRaise(repo.trainingAdvice) {
                    // La reconstrucción no publicó: los slots son del pase anterior y pueden traer una
                    // subida aplicada bajo un consejo que hoy la retiene → se retiene aquí.
                    actual = HoyPlan(routine: plan.routine, slots: plan.slots.map { slot in
                        guard var raise = slot.raise, !raise.waiting else { return slot }
                        raise.waiting = true
                        var held = slot
                        held.raise = raise
                        return held
                    }, serving: plan.serving, advice: plan.advice, tono: plan.tono)
                }
            }
            iniciar(actual)
        }
    }

    private func iniciar(_ plan: HoyPlan) {
        guard !plan.slots.isEmpty else { abrirRutina(plan.routine.id); return }
        appModel.startStrengthSession(routineId: plan.routine.id, routineName: plan.routine.name,
                                      slots: plan.slots,
                                      programWeek: plan.serving.flatMap(\.stampWeek),
                                      deload: plan.serving.flatMap(\.stampDeload),
                                      lightWeekHint: ProgramServing.stalledHint(context: plan.serving))
    }

    /// «Empezar» del widget / Siri / Daily Brief (`TabRouter`): hoy → arranca; otra rutina → se abre lista
    /// para empezar, sin forzar (FER-522 · FER-85: aconsejar, no bloquear). Espera a que termine la carga.
    private func atenderPeticiones() {
        if tabRouter.startTodaySession {
            tabRouter.startTodaySession = false
            if cargado { if hoy != nil, !yaEntrenaste { empezar() } } else { iniciarAlCargar = true }
        }
        if let id = tabRouter.startRoutineId, cargado {
            tabRouter.startRoutineId = nil
            if id == hoy?.routine.id, !yaEntrenaste { empezar() } else { abrirRutina(id) }
        }
    }

    // MARK: Carga

    /// Lee la rutina de hoy y la siembra. `true` = este pase publicó (no lo ganó uno más nuevo).
    @discardableResult
    private func cargar() async -> Bool {
        let seq = repo.refreshSeq
        guard let store = await repo.storeHandle() else { cargado = true; return false }
        let rutinas = (try? await store.routines()) ?? []
        let agenda = (try? await store.routineSchedule()) ?? []
        let plan = Dictionary(agenda.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let porId = Dictionary(rutinas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var nuevoHoy: HoyPlan?
        if let tid = WeeklySplit.todayRoutineId(split: plan, todayWeekday: todayWeekday), let rutina = porId[tid] {
            // Un veredicto y una semana de programa por pase, leídos antes de sembrar (FER-82 / E10).
            let advice = repo.trainingAdvice
            let inventory = await MainActor.run { PlatesStore().inventory }
            let serving = await repo.programServing()
            let slots = await repo.seedTodaySlots(routineId: tid, advice: advice, inventory: inventory,
                                                  serving: serving)
            let musculos = slots.compactMap { $0.exercise?.primaryMuscles }
            let familia = RoutineClassifier.classify(primaryMusclesPerExercise: musculos)?.family ?? .push
            nuevoHoy = HoyPlan(routine: rutina, slots: slots, serving: serving, advice: advice, tono: familia.tono)
        }
        let recientes = (try? await store.recentSessions(limit: 20)) ?? []
        let entrenoHoy = nuevoHoy.map { plan in
            recientes.contains { s in
                s.endTs != nil && s.routineId == plan.routine.id
                    && Calendar.current.isDateInToday(Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            }
        } ?? false
        let proxima = proximaRutina(plan: plan, porId: porId)
        // Sin await de aquí en adelante: la publicación es atómica. Un pase que perdió la carrera no toca nada.
        guard seq == repo.refreshSeq else { return false }
        hoy = nuevoHoy
        yaEntrenaste = entrenoHoy
        siguiente = proxima
        cargado = true
        if iniciarAlCargar {
            iniciarAlCargar = false
            if hoy != nil, !yaEntrenaste { empezar() }
        }
        atenderPeticiones()
        return true
    }

    /// «Siguiente: Pierna · jueves» — la próxima rutina agendada después de hoy (hasta 7 días adelante).
    private func proximaRutina(plan: [Int: String], porId: [String: Routine]) -> String? {
        for offset in 1...7 {
            let wd = (todayWeekday - 1 + offset) % 7 + 1
            if let rid = plan[wd], let r = porId[rid] {
                let dia = Calendar.current.weekdaySymbols[wd - 1]
                // Mañana se dice «mañana»; a 7 días es el mismo día de la semana que hoy, y «Sigue: Empuje ·
                // sábado» dicho un sábado se lee como hoy → «el próximo sábado».
                if offset == 1 {
                    return String(format: String(localized: "fuerza.antes.siguiente.manana",
                                                 defaultValue: "Next: %@ · tomorrow"), r.name)
                }
                if offset == 7 {
                    return String(format: String(localized: "fuerza.antes.siguiente.proximo",
                                                 defaultValue: "Next: %@ · next %@"), r.name, dia)
                }
                return String(format: String(localized: "fuerza.antes.siguiente", defaultValue: "Next: %@ · %@"),
                              r.name, dia)
            }
        }
        return nil
    }
}

// MARK: - Hojas · Plan, Progreso, Ajustes

/// Destinos que comparten las hojas de Plan y Progreso.
private enum FuerzaDestino: Hashable {
    case biblioteca, historial, marcas
}

/// Plan: la semana y las rutinas (`WeeklyPlanEditorView`), con el editor de rutina y la biblioteca empujados.
private struct FuerzaHojaPlan: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ruta: NavigationPath

    init(abrir: RoutineEditorRoute?) {
        var path = NavigationPath()
        if let abrir { path.append(abrir) }
        _ruta = State(initialValue: path)
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            WeeklyPlanEditorView(
                openRoutine: { ruta.append(RoutineEditorRoute.routine(routineId: $0)) },
                openLibrary: { ruta.append(FuerzaDestino.biblioteca) },
                openDay: { ruta.append(RoutineEditorRoute.planDay(weekday: $0)) })
                .fuerzaHoja(cerrar: { dismiss() })
                .navigationDestination(for: FuerzaDestino.self) { _ in
                    ExerciseLibraryScreen().fuerzaPush()
                }
                .navigationDestination(for: RoutineEditorRoute.self) { route in
                    // La Hoja dibuja su propio encabezado y su CTA fijo: sin barra nativa.
                    RoutineSheet(origin: route, mode: .editing)
                        .fuerzaPush()
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}

/// Progreso: historial, marcas y biblioteca. «Ver mapa» del acta y «Ver recibo» del reloj llegan con su ruta.
private struct FuerzaHojaProgreso: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historial = WorkoutHistoryCoordinator()
    @State private var ruta: NavigationPath

    init(abrir: AnyHashable?) {
        var path = NavigationPath()
        if let abrir { Self.empujar(abrir, en: &path) }
        _ruta = State(initialValue: path)
    }

    /// `NavigationPath` solo acepta `Hashable` concretos: se reabre el tipo conocido.
    private static func empujar(_ valor: AnyHashable, en path: inout NavigationPath) {
        if let r = valor.base as? WorkoutSessionRoute { path.append(r) }
        else if let r = valor.base as? MuscleVolumeRoute { path.append(r) }
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            raiz
                .navigationDestination(for: FuerzaDestino.self) { destino in
                    switch destino {
                    case .biblioteca: ExerciseLibraryScreen().fuerzaPush()
                    case .historial:
                        WorkoutHistoryScreen(
                            initialFilter: .strength,
                            openWorkoutSession: { ruta.append($0) },
                            openCardio: { ruta.append($0) })
                            .fuerzaPush()
                    case .marcas: PersonalRecordsScreen().fuerzaPush()
                    }
                }
                .navigationDestination(for: WorkoutSessionRoute.self) { route in
                    WorkoutSessionDetailScreen(
                        route: route,
                        openRoutine: { ruta.append(RoutineEditorRoute.routine(routineId: $0)) })
                        .fuerzaPush()
                }
                .navigationDestination(for: RoutineEditorRoute.self) { route in
                    RoutineSheet(origin: route, mode: .editing)
                        .fuerzaPush()
                        .toolbar(.hidden, for: .navigationBar)
                }
                .navigationDestination(for: WorkoutRow.self) { row in
                    WorkoutDetailScreen(row: row, onChange: { historial.bumpReload() }).fuerzaPush()
                }
                .navigationDestination(for: MuscleVolumeRoute.self) { _ in TrainingBodyScreen().fuerzaPush() }
                .navigationDestination(for: SavedTicketsRoute.self) { _ in SavedTicketsScreen().fuerzaPush() }
                .navigationDestination(for: PersonalRecordsRoute.self) { _ in PersonalRecordsScreen().fuerzaPush() }
        }
        .environmentObject(historial)
    }

    private var raiz: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s600) {
                Text(String(localized: "Progress"))
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: .zero) {
                    LiquidListRow(title: String(localized: "My workouts")) { ruta.append(FuerzaDestino.historial) }
                    LiquidListRow(title: String(localized: "Records")) { ruta.append(FuerzaDestino.marcas) }
                    LiquidListRow(title: String(localized: "Exercise library"), divider: false) {
                        ruta.append(FuerzaDestino.biblioteca)
                    }
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pantallaFondo()
        .fuerzaHoja(cerrar: { dismiss() })
    }
}

/// Ajustes: `AjustesView` tal cual (su poda es la ola 0 · E).
private struct FuerzaHojaAjustes: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AjustesView()
                .fuerzaHoja(cerrar: { dismiss() })
        }
    }
}

private extension View {
    /// El «Listo» de una hoja de la raíz.
    func fuerzaHoja(cerrar: @escaping () -> Void) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done"), action: cerrar)
                        .foregroundStyle(LiquidColor.tinta900)
                }
            }
    }

    /// Cromo de una pantalla empujada dentro de una hoja: fondo de papel y barra clara (como `trainChrome`).
    func fuerzaPush() -> some View {
        self
            .pantallaFondo()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
    }
}
#endif
