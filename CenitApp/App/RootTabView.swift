#if os(iOS)
import SwiftUI
import CenitDesign
import CenitAnalytics
import CenitStore   // FER-202: `WorkoutRow` — destino de detalle de actividad en el trainStack (fusión de historiales)

/// iOS navigation shell — tres cuartos (FER-490): **Entrenar · Cuerpo · Ajustes** on the system
/// tab bar. Cuerpo folds the former Hoy and Tendencias screens into «Ahora | Tiempo»
/// (`CuerpoTabView`). Patrones (Coach) was archived in FER-240; En vivo opens from Hoy's beat cover.
///
/// Hub tabs reconnect screens which don't have a final home yet:
///   • **Entrenar** → Breathe · Intervals (+ strength hub).
///   • **Ajustes**  → Settings + orphan sheets (Explore · Workouts · Apple Health · Data Sources ·
///     Support). Sueño / Health / Stress live in Cuerpo/Tiempo. Nothing from the old shell becomes unreachable.
struct RootTabView: View {
    // FER-490: Hoy + Tendencias → Cuerpo (Ahora | Tiempo).
    private enum Tab: Hashable { case cuerpo, train, settings }

    /// Every screen reachable by pushing onto a hub tab's stack. Raw values match the `cenit.nav.<key>`
    /// debug-navigation keys (`ScreenshotNav.swift`) so screenshot automation still reaches each one.
    private enum SecondaryScreen: String, Hashable {
        case library                              // Entrenar hub — exercise library (FER-346)
        case workoutHistory = "workouthistory"    // Entrenar hub — «Mis entrenamientos» (FER-504)
        // FER-92 / FER-239: `dieta` retirada del enum y la pantalla huérfana archivada.
        case breathe, intervals                   // Entrenar hub
        case weeklyPlan = "weeklyplan"            // Entrenar hub — weekly plan editor (FER-533)
        case misRutinas = "misrutinas"           // Entrenar hub — routine + folder management (FER-534)
        case routineToday                         // Entrenar hub — «Rutina de hoy» (DEBUG screenshot-nav)
        // Reachable via DEBUG screenshot-nav (pushed onto the Ajustes stack). Explore/Workouts
        // also still open from Cuerpo's footer; the rest open as sheets from the Ajustes root (FER-337).
        case explore, workouts
        case applehealth, datasources, support
    }

    /// Whether Today is the active tab — published up to ContentView, which owns the color scheme
    /// (and with it the status bar): Today is light paper → dark status bar, the rest are dark.
    @Binding var isTodayActive: Bool

    /// App-level cross-tab navigation (FER-378). A screen can ask to jump tabs; we apply + clear it.
    @EnvironmentObject private var tabRouter: TabRouter

    /// The strength session lives here (FER-716): it presents as a full-screen cover (over the tab bar,
    /// no grabber) from ANY tab. Minimized, the pill sits in each tab's bottom safe area, above the
    /// system bar. Owned by AppModel so navigation never kills it — dismissing the cover only
    /// minimizes it (the pill re-opens).
    @Environment(AppModel.self) private var appModel

    /// The visible tab. Starts on Train (Entrenar), the launch screen (FER-488).
    @State private var selection: Tab = .train
    /// Tabs whose content has been shown at least once. Only Train is built at launch (FER-488); the one heavy
    /// lazy tab — Cuerpo (`CuerpoTabView` / `CuerpoView` runs its own `.task` data load on appear) — is
    /// deferred until first selected, then kept in the set so switching back doesn't rebuild from scratch.
    /// The hub tabs (Entrenar/Ajustes) are plain lists whose destinations build on `NavigationLink` tap,
    /// so they stay eager (cheap). Avoids widening the launch gap — FER-31.
    @State private var visited: Set<Tab> = [.train]
    /// One type-erased path per hub. `NavigationPath` (not a homogeneous `[SecondaryScreen]`) because
    /// the Ajustes stack carries Explore, which pushes `MetricDescriptor` values onto it — a typed
    /// path crossing a second value type crashed SwiftUI (FER-171).
    @State private var trainStack = NavigationPath()
    @State private var settingsStack = NavigationPath()
    /// Bridges the workout-history list and the session detail (siblings in `trainStack`) so a delete or
    /// edit in the detail surfaces «Undo» / a reload on the list (FER-556).
    @StateObject private var workoutHistory = WorkoutHistoryCoordinator()
    /// El ✕ del pill pide confirmación aquí (pantalla completa), no en el frame del pill.
    @State private var confirmDiscardSession = false

    // FER-981: `body` kept thin so type-check stays under the long-function budget. Tab shell,
    // heavy tabs, and the modifier chain each type-check in their own scope.
    // Inject: hooks en el struct NO privado del archivo (regla PR#1036) para iterar
    // el shell en vivo durante las sesiones /inject.
    @ObserveInjection private var inject

    var body: some View {
        rootChrome(rootTabs)
            .enableInjection()
    }

    /// Three-tab shell (FER-490). Extracted from `body` (FER-981) so TabView + tags type-check apart from chrome.
    @ViewBuilder
    private var rootTabs: some View {
        TabView(selection: $selection) {
            // FER-240: Patrones (former Coach tab) archived — screen deleted, not just off-dock.
            trainTab
            lazyTab(.cuerpo, "Body", "chart.xyaxis.line") { CuerpoTabView() }
            settingsTab
        }
        // iOS 26 puede encoger la tab bar al hacer scroll. La píldora de sesión se ancla
        // al área segura, no a una altura medida: si la barra se encoge, la píldora queda
        // en el aire, y ese seguimiento no se puede comprobar aquí. La barra se queda fija.
        // En iPhone Duo la barra del sistema se acomoda sola; no volver a un padding inferior fijo.
        .tabBarPinned()
    }

    // Entrenar — the redesigned light «Instrumento» hub (FER-343 + FER-346): the «Hoy» card +
    // recovery band, «Mis rutinas» (build / edit), the exercise library, and the Respira /
    // Intervalos / Dieta / En-vivo tools (FER-39 epic). Like Cuerpo/Ajustes the visible hub
    // navigates by pushing onto this tab's NavigationStack; that stack also lets DEBUG
    // screenshot-nav reach «Rutina de hoy» / Biblioteca / Respira / Intervalos / Dieta. Warm
    // paper throughout, so there's no light-tab → dark-screen status-bar bridge to manage.
    @ViewBuilder
    private var trainTab: some View {
        NavigationStack(path: $trainStack) {
            EntrenarView(
                openRoutine: { id in trainStack.append(RoutineEditorRoute.today(routineId: id)) },
                openBreathe: { trainStack.append(SecondaryScreen.breathe) },
                openIntervals: { trainStack.append(SecondaryScreen.intervals) },
                openHistory: { trainStack.append(SecondaryScreen.workoutHistory) },
                openWeeklyPlan: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openRoutines: { trainStack.append(SecondaryScreen.weeklyPlan) },
                openWorkoutSession: { trainStack.append($0) },
                openMuscleMap: { trainStack.append(MuscleVolumeRoute()) },
                openMarcas: { trainStack.append(PersonalRecordsRoute()) }
            )
            .navigationDestination(for: SecondaryScreen.self) { screen in
                trainChrome(secondaryDestination(screen))
            }
            .navigationDestination(for: RoutineEditorRoute.self) { route in
                // «La Hoja» (FER-166, F1): crear = editar, la misma hoja en frío para todo origen
                // (hoy / día del plan / Mis rutinas). Sustituye a `RoutineEditorScreen` (FER-839).
                // Draws its own back/cancel header + pinned CTA, so the native nav bar is hidden.
                trainChrome(RoutineSheet(origin: route, mode: .editing))
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: WorkoutSessionRoute.self) { route in
                trainChrome(WorkoutSessionDetailScreen(
                    route: route,
                    openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) }))
            }
            // Decisión Fer (2026-07-16): «Ver mapa» abre «Tu cuerpo» real (las siluetas de
            // Tendencias), empujado — FER-91 · E10 fusionó el mapa y el volumen en una sola
            // pantalla, así que las dos rutas viejas convergen aquí.
            .navigationDestination(for: MuscleVolumeRoute.self) { _ in
                trainChrome(TrainingBodyScreen())
            }
            .navigationDestination(for: SavedTicketsRoute.self) { _ in
                trainChrome(SavedTicketsScreen())
            }
            .navigationDestination(for: PersonalRecordsRoute.self) { _ in
                trainChrome(PersonalRecordsScreen())
            }
            // FER-202 (fusión «Historial unificado»): el detalle de una fila de ACTIVIDAD (cardio/manual,
            // `WorkoutRow`) — `WorkoutHistoryScreen.openCardio` lo empuja aquí. Antes lo registraba
            // `WorkoutsView` (retirada); ahora vive en el trainStack como una ruta más (path heterogéneo,
            // no un stack anidado: sin riesgo FER-171).
            .navigationDestination(for: WorkoutRow.self) { row in
                // `onChange` bumpea el coordinador para que la lista unificada se recargue al volver de
                // una edición/borrado (paridad con lo que hacía `WorkoutsView.reload`).
                trainChrome(WorkoutDetailScreen(row: row,
                                                onChange: { workoutHistory.bumpReload() }))
            }
        }
        .environmentObject(workoutHistory)
        .activeSessionPillInset(model: appModel, confirmDiscard: $confirmDiscardSession)
        .tabItem { Label("Train", systemImage: "figure.strengthtraining.functional") }
        .tag(Tab.train)
    }

    // Ajustes — the redesigned light «Instrumento» Settings root (FER-337). Replaces the old
    // list → SettingsView indirection AND the «Más» drawer: the tab now opens directly here.
    // The visible UI navigates by SHEET (AjustesView), like Cuerpo; the NavigationStack here
    // exists only so DEBUG screenshot-nav can still push a secondary screen — its path only
    // ever carries `SecondaryScreen` (one value type), so there's no FER-171 mixed-path crash.
    // Explore · Workouts are gone from Ajustes (they open from Cuerpo now); Compare was retired (FER-489).
    @ViewBuilder
    private var settingsTab: some View {
        NavigationStack(path: $settingsStack) {
            AjustesView()
                .navigationDestination(for: SecondaryScreen.self) { screen in
                    secondaryDestination(screen)
                        .pantallaFondo()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
                }
        }
        .activeSessionPillInset(model: appModel, confirmDiscard: $confirmDiscardSession)
        // Misma clave que el título de la pantalla («Settings» → «Ajustes» en es).
        // «Ajustes» como clave era una isla: en un teléfono en inglés la barra decía Ajustes.
        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        .tag(Tab.settings)
    }

    /// Overlays, covers, and lifecycle observers on the tab shell. Composed from three
    /// smaller modifier helpers so no single chain type-checks over the long-function budget (FER-981).
    private func rootChrome<Content: View>(_ content: Content) -> some View {
        rootChromeLifecycle(rootChromeCovers(rootChromeOverlays(content)))
    }

    /// `.tint` colorea el ítem seleccionado de la tab bar del sistema — ese es su papel —
    /// y los links y controles de las pantallas. No pinta el fondo de la barra.
    ///
    /// FER-985: no partas esta cadena para “bajar” el type-check. Medido, mover el acceso
    /// a `AppModel` entre funciones vecinas empeora el costo en vez de bajarlo.
    private func rootChromeOverlays<Content: View>(_ content: Content) -> some View {
        content
            .tint(LiquidColor.verdePrimario)
    }

    /// Confirm discard, session animations, and the guided-strength fullScreenCover (FER-347/716).
    /// Own `@Bindable` for FER-984 (`$appModel.strengthSheetPresented`).
    private func rootChromeCovers<Content: View>(_ content: Content) -> some View {
        // FER-984: `appModel` es `@Environment` (sin `$` publishers); este `@Bindable` local habilita el
        // binding `$appModel.strengthSheetPresented` del fullScreenCover de la sesión de fuerza (abajo).
        @Bindable var appModel = appModel
        return content
        // El ConfirmCard del ✕ del pill vive AQUÍ (pantalla completa): colgado del host del pill se
        // anclaba a su frame angosto — velo recortado y esquinas rotas (bug Fer 2026-07-16).
        // Handoff V10 (FER-139): título + mensaje alineados al prototipo, con el conteo REAL de
        // series de hoy y su plural correcto. Los rótulos de acción se quedan en «Seguir
        // entrenando»/«Descartar sesión» — no «Cancelar»/«Descartar» a secas — porque `ConfirmCard`
        // (CenitDesign, FER-836) documenta como ley que esos dos genéricos no existen en este
        // sistema; cada acción nombra lo que hace.
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
        // The guided strength session (FER-347/716): a full-screen cover so it covers the dock with no
        // grabber, opened from any tab. The session lives in AppModel, so dismissing the cover only hides
        // it (the pill re-opens); the summary is ended by `closeStrengthSummary` on its «Listo».
        .fullScreenCover(isPresented: $appModel.strengthSheetPresented, onDismiss: {
            if appModel.strengthSession?.summary != nil { appModel.closeStrengthSummary() }
        }) {
            // FER-167 (F2): La Hoja viva sustituye a `LiveStrengthSheet` como superficie montada —
            // ese tipo sigue vivo (modo Foco + acta), compuesto desde `HojaSesionViva`.
            if appModel.strengthSession != nil {
                RoutineSheet(origin: .today(routineId: appModel.strengthSession?.routineId), mode: .live)
                    .environment(appModel)
                    .environmentObject(tabRouter)
            }
        }
    }

    /// Preference, tab selection, cross-tab routing, watch receipt, and DEBUG nav observers.
    private func rootChromeLifecycle<Content: View>(_ content: Content) -> some View {
        content
        // Color scheme lo decide ContentView (cercano a la raíz) según `isTodayActive`; aquí solo lo
        // mantenemos en papel claro — las cuatro pestañas viven en Liquid Glass · El Eje.
        .onChange(of: selection) { _, newValue in
            visited.insert(newValue)
            isTodayActive = true
        }
        .onAppear { isTodayActive = true }
        // FER-398 — `cenit://session`, el deep link de la Live Activity de descanso (su `widgetURL`).
        // En AMBOS modos, no solo en Debug: en la app de la tienda ese tap no llevaba a ningún lado
        // porque el único manejador del esquema vivía bajo `#if DEBUG` (`ScreenshotNav`), que además
        // ignora `session` a propósito para que los dos no reaccionen a la misma URL.
        //
        // Con sesión viva: Entrenar + reabrir la hoja (el mismo camino que toca la píldora flotante).
        // Sin sesión viva: solo Entrenar — nunca inventa una sesión que no existe.
        .onOpenURL { url in
            guard url.scheme == "cenit", url.host == "session" else { return }
            selection = .train
            appModel.resumeStrengthSession()   // ya es un no-op sin sesión viva
        }
        // Cross-tab navigation requests (FER-378 / FER-490). One-shot: apply + clear.
        .onReceive(tabRouter.$requested.compactMap { $0 }) { req in
            switch req {
            case .cuerpo:   selection = .cuerpo
            case .train:    selection = .train
            case .settings: selection = .settings
            }
            tabRouter.requested = nil
        }
        // FER-810: «Ver recibo en iPhone» from the Apple Watch → switch to Entrenar and push the saved
        // workout's history detail. One-shot: apply + clear.
        // FER-984: `@Observable` no expone `$` publishers; se reacciona al cambio de la propiedad con
        // `onChange` en vez del `onReceive` del publisher. `initial: true` reemplaza la emisión inmediata
        // del publisher de Combine al suscribirse — así una ruta YA presente al montar (cold-launch desde
        // el watch, FER-810) también se atiende. One-shot: aplica al primer valor no-nil y limpia.
        .onChange(of: appModel.pendingReceiptRoute, initial: true) { _, route in
            guard let route else { return }
            selection = .train
            trainStack.append(route)
            appModel.pendingReceiptRoute = nil
        }
        // FER-186: strength summary «Ver mapa» → Entrenar + push `MuscleVolumeRoute` (same stack as
        // the hub MAPA door). Mirrors `pendingReceiptRoute`: apply + clear on the train stack owner.
        .onChange(of: tabRouter.openMuscleMapInTrain, initial: true) { _, open in
            guard open else { return }
            selection = .train
            trainStack.append(MuscleVolumeRoute())
            tabRouter.openMuscleMapInTrain = false
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .cenitDebugNav)) { note in
            guard let screen = note.object as? String else { return }
            // Alias keys (FER-490 A3): today → Cuerpo/Ahora; body/trends/sleep → Cuerpo/Tiempo.
            let tab: Tab? = switch screen {
            case "today":              .cuerpo
            case "body", "trends", "sleep": .cuerpo
            // FER-240: «coach» / Patrones archived — key ignored (falls through to nil via default).
            case "train", "entrenar":  .train
            case "settings", "ajustes", "more": .settings
            default:                   nil
            }
            if let tab {
                selection = tab
                if tab == .cuerpo {
                    tabRouter.cuerpoModo = (screen == "today") ? .ahora : .tiempo
                }
                trainStack = NavigationPath(); settingsStack = NavigationPath()
                return
            }
            // Secondary screens: select the owning hub and push the screen onto its stack.
            if let sec = SecondaryScreen(rawValue: screen) {
                let owner = hub(for: sec)
                selection = owner
                var path = NavigationPath(); path.append(sec)
                switch owner {
                case .train:    trainStack = path
                default:        settingsStack = path
                }
            }
        }
        // FER-381: `-cenit.route <familia/clave>` lleva la captura del mapa a una pantalla sin atajo
        // `nav`. La Ola 1 solo selecciona la TAB por la familia; cada pantalla consume su propia clave
        // (`DebugRoute.key(for:)`) y empuja su destino en su ola de captura.
        .onAppear {
            switch DebugRoute.family {
            case "hoy":
                selection = .cuerpo
                tabRouter.cuerpoModo = .ahora
            case "tendencias", "cuerpo", "body":
                selection = .cuerpo
                tabRouter.cuerpoModo = .tiempo
            case "entrenar", "train":
                selection = .train
                // FER-386/388 (mapa 100 % · Entrenar): marcas/volumen/tickets no tienen atajo `nav`
                // (son rutas empujadas por closure, sin tab-level key) — el push vive AQUÍ porque
                // `EntrenarView` no es dueño de `trainStack`. Push directo, sin pasar por la pantalla
                // que normalmente los abre (el hub / el historial).
                switch DebugRoute.key(for: "entrenar") {
                case "marcas":  trainStack.append(PersonalRecordsRoute())
                case "volumen": trainStack.append(MuscleVolumeRoute())
                case "tickets": trainStack.append(SavedTicketsRoute())
                default:        break
                }
            case "ajustes", "settings":    selection = .settings
            default:                       break
            }
        }
        #endif
        // NOTE: the launch refresh is owned by AppModel.init (one source of truth). A second
        // `.task { repo.refresh() }` here ran a full-history load concurrently with that one at
        // launch — double DB work + an extra refreshSeq bump that re-fired TodayView.loadAll.
    }

    /// The hub tab that owns a given secondary screen (for debug navigation).
    ///
    /// Exhaustive on purpose — no `default`. A screen routed to the wrong hub lands on a stack that
    /// doesn't inject that hub's environment objects, and SwiftUI answers a missing `@EnvironmentObject`
    /// with a `fatalError`, not a fallback: `.workoutHistory` used to fall through `default` to Ajustes,
    /// whose destination lacks the `.environmentObject(workoutHistory)` the Entrenar stack applies, so
    /// screenshot-nav to it crashed the app. Listing every case makes that a compile error instead.
    private func hub(for screen: SecondaryScreen) -> Tab {
        switch screen {
        case .library, .workoutHistory, .breathe, .intervals, .weeklyPlan, .misRutinas,
             .routineToday:
            return .train
        case .explore, .workouts, .applehealth, .datasources, .support:
            return .settings
        }
    }

    /// A tab whose real content is built only once its tag has been visited (kept alive afterward),
    /// so non-selected screens don't construct their body or fire their launch `.task` at startup.
    @ViewBuilder
    private func lazyTab<V: View>(_ tag: Tab, _ title: LocalizedStringKey, _ icon: String,
                                  @ViewBuilder _ content: @escaping () -> V) -> some View {
        Group {
            if visited.contains(tag) {
                content()
            } else {
                Color.clear   // placeholder until first selected; never visible (selecting builds it)
            }
        }
        .pantallaFondo()
        // La píldora va en el raíz de la pestaña, no en cada destino: así sigue visible
        // al empujar y el scroll de la página se detiene encima de ella. Vacía, no abre hueco.
        .activeSessionPillInset(model: appModel, confirmDiscard: $confirmDiscardSession)
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }

    /// Chrome for a screen pushed onto the Entrenar stack: warm-paper background and a light
    /// navigation bar (the whole tab is «Instrumento» paper — FER-343). The system tab bar
    /// insets the stack; the session pill is on the `NavigationStack`, not here.
    @ViewBuilder
    private func trainChrome<V: View>(_ screen: V) -> some View {
        screen
            .pantallaFondo()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    @ViewBuilder
    private func secondaryDestination(_ screen: SecondaryScreen) -> some View {
        switch screen {
        case .library:      ExerciseLibraryScreen()
        // FER-90: el toque de un día del calendario empuja SU sesión. El agente cableó esto en
        // `AppMap.swift` (el arnés de desarrollo) y no aquí, que es la navegación real: en la app
        // el día se habría podido tocar y no habría pasado nada. `WorkoutSessionRoute` ya tiene su
        // `navigationDestination` registrado arriba, así que basta empujarla a la pila.
        // FER-202: la puerta de Entrenar abre el «Historial unificado» filtrado a Fuerza (la bitácora
        // rica); una fila de actividad de la línea mixta empuja su detalle Apple (`openCardio`).
        case .workoutHistory: WorkoutHistoryScreen(
            initialFilter: .strength,
            openWorkoutSession: { trainStack.append($0) },
            openCardio: { trainStack.append($0) })
        case .breathe:      BreathingView()
        case .intervals:    IntervalTimerView()
        // FER-890: «Tu Plan» is one unified screen (week + routines). Both routes resolve to it — the old
        // `.misRutinas` key stays so DEBUG screenshot-nav still reaches the routines home (now unified).
        case .weeklyPlan, .misRutinas:
            WeeklyPlanEditorView(
                openRoutine: { id in trainStack.append(RoutineEditorRoute.routine(routineId: id)) },
                openLibrary: { trainStack.append(SecondaryScreen.library) },
                openDay: { wd in trainStack.append(RoutineEditorRoute.planDay(weekday: wd)) })
        case .routineToday: RoutineSheet(origin: .today(routineId: nil), mode: .editing)
        case .explore:      MetricExplorerView()
        // FER-202: `WorkoutsView` se retiró (fusionada en `WorkoutHistoryScreen`). Esta clave solo la
        // alcanza la navegación de screenshots DEBUG (`ScreenshotNav`, rawValue «workouts»), así que
        // apunta al historial unificado en «Todo» con su propio coordinador (no cuelga de un stack que
        // lo inyecte). Sin clausuras: no necesita navegar en ese camino de captura.
        case .workouts:     WorkoutHistoryScreen(initialFilter: .all)
                                .environmentObject(WorkoutHistoryCoordinator())
        case .applehealth:  AppleHealthView()
        case .datasources:  DataSourcesView()
        case .support:      SupportView()
        }
    }
}

private extension View {
    /// iOS 26 puede encoger la tab bar. La píldora no sigue esa altura (no se puede
    /// comprobar aquí), así que la barra no se encoge. En iOS 17–25 el modificador no existe.
    @ViewBuilder
    func tabBarPinned() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }

    /// Píldora de sesión minimizada, en el área segura inferior de la pestaña.
    /// Sin sesión (o con la hoja abierta) el contenido mide cero y `spacing` es cero:
    /// no se suma un hueco encima de la tab bar del sistema.
    func activeSessionPillInset(model: AppModel, confirmDiscard: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom, spacing: .zero) {
            ActiveSessionPillSlot(model: model, confirmDiscard: confirmDiscard)
        }
    }
}

/// El `if` vive en una vista propia para no leer `AppModel` dentro de la cadena de
/// `RootTabView` (FER-985). Vacío, el `safeAreaInset` no reserva alto.
private struct ActiveSessionPillSlot: View {
    @Bindable var model: AppModel
    @Binding var confirmDiscard: Bool

    var body: some View {
        if model.strengthSession != nil && !model.strengthSheetPresented {
            ActiveSessionPillHost(model: model, confirmDiscard: $confirmDiscard)
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.bottom, LiquidSpace.s200)
                .transition(LiquidMotion.risingFadeTransition)
        }
    }
}

/// Hosts the `SessionPill` with a live-ticking clock (FER-716): a `TimelineView` recomputes the
/// elapsed time each second, and the BPM is the Apple Watch live mirror (`model.watchBpm` — the same
/// source as the session header; nil = no watch reading, so the pill drops its ♥ segment instead
/// of freezing a stale sample). Tapping re-opens the session. The routine hue is the indigo
/// (`dataSleep`) — the prototype's 6px pill dot (handoff V10 · FER-139), not the effort ember.
private struct ActiveSessionPillHost: View {
    @Bindable var model: AppModel
    /// Decisión Fer (2026-07-16): el ✕ del pill DESCARTA — destructivo, así que siempre confirma.
    /// El ConfirmCard vive en el RootTabView (pantalla completa); aquí solo se dispara.
    @Binding var confirmDiscard: Bool
    var body: some View {
        if let session = model.strengthSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // FER-952: pause-aware clock (the raw now−start kept ticking while paused).
                let elapsed = SessionClock.format(session.elapsedSeconds(now: context.date))
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                // FER-167 ronda 2 (R20, Grok 14 + QA O2): «Serie N de M» — la MISMA palabra y el
                // MISMO «N de N · completa» que la cabecera de la Hoja viva (`HojaCabeceraSesion`),
                // nunca dos fuentes que puedan divergir en la unidad de avance.
                let isComplete = total > 0 && session.pendingCount == 0
                let detail: String? = total == 0 ? nil : (isComplete
                    ? String(localized: "\(total) of \(total) · complete")
                    : String(localized: "Set \(min(session.doneCount + 1, total)) of \(total)"))
                SessionPill(
                    routineName: session.routineName,
                    elapsed: elapsed,
                    bpm: model.watchBpm,
                    detail: detail,
                    paused: session.paused,
                    hue: LiquidColor.indigo,
                    accessibilityLabel: pillLabel(session.routineName, elapsed, model.watchBpm),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onDiscard: { confirmDiscard = true },
                    discardAccessibilityLabel: Text("Discard session")
                )
            }
        }
    }

    /// VoiceOver label for the pill — localized here because the CenitDesign package has no catalog.
    private func pillLabel(_ name: String, _ elapsed: String, _ bpm: Int?) -> Text {
        if let bpm { return Text("Active session: \(name), \(elapsed), heart rate \(bpm)") }
        return Text("Active session: \(name), \(elapsed)")
    }
}
#endif
