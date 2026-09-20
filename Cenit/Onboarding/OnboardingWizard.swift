import SwiftUI
import CenitDesign
import CenitAnalytics

// MARK: - OnboardingWizard  ·  el onboarding en cinco actos (FER-109 · FER-113 · FER-520)
//
// El primer arranque dejó de ser un wizard de formularios y pasó a ser una sola escena que se
// transforma sobre EL MISMO lienzo de partículas. Lo que hay que entender antes de tocar este
// archivo:
//
//   1. **Un solo suelo: `LiquidColor.fondoGradient`.** Mismo lienzo Liquid Glass · El Eje que
//      Cuerpo, para que el último acto no salte de color al aterrizar en la app.
//
//   2. **El orbe se llena con TU evidencia, no con el reloj.** La densidad del lienzo la manda
//      `OnboardingLanding.densidadHonesta`, nunca cuánto tiempo llevas mirando la pantalla.
//
//   3. **El color llega como REVELACIÓN.** El lienzo va en tinta neutra durante los primeros
//      actos; el veredicto lo tiñe UNA vez, en el encendido.
//
//   4. **Después de la palabra viene el ACTA (+ perfil-coda), nunca un formulario suelto.** El
//      perfil se captura DENTRO del Acta (FER-520); «Tu sesión» es el acto 5 post-permiso.
//
//   5. **El permiso sigue siendo el ÚNICO gate (FER-251).** Ninguna rama es callejón; el perfil
//      se captura en TODAS las ramas (FER-113).
//
// Los actos viven en archivos hermanos; aquí está la escena, el lienzo y el cableado.

struct OnboardingWizard: View {

    /// Se llama cuando el usuario termina (o se salta al final de) el onboarding.
    var onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        #if os(iOS) && DEBUG
        // FER-391 (mapa 100 %): `-cenit.onboardingActo <acto>` MUESTRA el wizard directo en ese
        // acto — el opuesto de `-cenit.onboarded YES`, que lo SALTA entero (`ContentView` agrega
        // el OR que lo deja entrar). `-cenit.onboardingLanding <caso>` fija además el desenlace.
        let d = UserDefaults.standard
        let actoForzado = d.string(forKey: "cenit.onboardingActo").flatMap(OnbActo.debugFixture)
        let landingForzado = d.string(forKey: "cenit.onboardingLanding").flatMap(OnboardingLanding.debugFixture)
        _acto = State(initialValue: actoForzado ?? .promesa)
        _landing = State(initialValue: landingForzado)
        if let landingForzado, (actoForzado ?? .encendido) == .encendido {
            // `correr()` en `OnbActoEncendido` salta el sync SOLO cuando `landing` ya no es
            // `nil` (ver su primer `if`), pero eso corre dentro de un `.task` — un cuadro
            // DESPUÉS del primero. Fijando `revelado`/`densidad`/`tenido` aquí, el primer cuadro
            // capturable ya nace en el desenlace correcto, sin ese parpadeo intermedio.
            _revelado = State(initialValue: true)
            _densidad = State(initialValue: landingForzado.densidadHonesta)
            _tenido = State(initialValue: landingForzado.revelaColor ? 1 : 0)
        }
        #endif
    }

    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter
    /// Solo para saber si el perfil sigue INTACTO cuando Salud se conecta tarde (ver
    /// `replantearAutollenado`). La coda del perfil es quien lo edita.
    @EnvironmentObject private var profile: ProfileStore

    @State private var acto: OnbActo = .promesa
    /// 0…1 de cuánta materia hay en el lienzo. Ver la regla 2 de la cabecera.
    @State private var densidad: Double = 0
    /// 0 = tinta neutra · 1 = el color del veredicto. Ver la regla 3.
    @State private var tenido: Double = 0
    /// El desenlace, en cuanto se conoce. `nil` hasta que la sincronización termina.
    @State private var landing: OnboardingLanding?
    /// El acto 3→4 ya reveló: el lienzo pasa de `.convergencia` a `.dentro`.
    @State private var revelado = false

    // El Acta(+coda) es la ÚLTIMA parada común de TODAS las ramas antes de «Tu sesión», así que
    // de dónde vino y a dónde va se fijan al entrar (`irAActa`) en vez de que el acto los adivine.
    @State private var actaAtras: OnbActo = .encendido
    @State private var actaLuego: OnbPerfilLuego = .ciclo
    /// A dónde sale «Tu sesión» (FER-431 / FER-520). En la ruta con reloj queda `.ciclo` y
    /// `terminar()` sigue sin Entrenar; en `.sinRitmoEnReposo` / `.sinDatos` / «Ahora no» guarda
    /// el `.entrar` / `.entrenar` que eligió la rama.
    @State private var sesionLuego: OnbPerfilLuego = .ciclo
    /// Lo que dejó el autollenado del perfil. Vive aquí y no en la coda porque volver al Acta
    /// (desde la sesión) lo reconstruye en blanco: sin este sello afuera, el autollenado correría
    /// una segunda vez y pisaría lo que la persona acaba de corregir.
    @State private var perfilSello: OnbPerfilSello?

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()

            OnbLienzo(densidad: densidad, tenido: tenido, modo: modo,
                      destino: destinoTinte, dosCentros: acto == .sesion)
                .ignoresSafeArea()
                .zIndex(0)

            contenido
                .id(acto)
                .transition(LiquidMotion.fadeTransition)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(LiquidMotion.glassOut(LiquidMotion.gentle), value: acto)
        // Conectar Salud DESPUÉS de haber pasado por la coda (ruta real: «Ahora no» → acta →
        // Atrás → reconsiderar → Conectar) dejaba el sello ya puesto, así que el autollenado no
        // volvía a correr. El sello se invalida aquí, en el wizard, porque la coda ni siquiera
        // está en pantalla cuando el permiso cambia. Vive aquí también la excepción que protege
        // la doctrina: si la persona ya corrigió algo, su corrección GANA y el sello se queda.
        .onChange(of: health.auth) { _, nuevo in
            guard nuevo == .authorized else { return }
            replantearAutollenado()
        }
    }

    // MARK: El acto en turno

    @ViewBuilder
    private var contenido: some View {
        switch acto {
        case .promesa:
            OnbActoPromesa(densidad: $densidad, onEmpezar: { ir(a: .permiso) })
        case .permiso:
            OnbActoPermiso(
                onAtras: { ir(a: .promesa) },
                onConectar: {
                    await health.requestAuthorization()
                    ir(a: .encendido)
                },
                onAhoraNo: { ir(a: .salida) })
        case .encendido:
            // Con palabra → Acta (anatomía + coda). Sin palabra → Acta (coda-only) con el destino
            // que eligió el CTA (Entrenar / Entrar). El permiso ya se concedió; el perfil se
            // captura SIEMPRE dentro del Acta (FER-113 / FER-520).
            OnbActoEncendido(
                densidad: $densidad,
                tenido: $tenido,
                landing: $landing,
                revelado: $revelado,
                onContinuar: { irAActa(desde: .encendido, luego: .ciclo) },
                onEntrenar: { irAActa(desde: .encendido, luego: .entrenar) },
                onEntrar: { irAActa(desde: .encendido, luego: .entrar) })
        case .acta:
            OnbActoActa(
                landing: landing,
                sello: $perfilSello,
                desdeSalida: actaAtras == .salida,
                onAtras: { ir(a: actaAtras) },
                onContinuar: { salirDelActa() })
        case .sesion:
            OnbActoSesion(
                landing: landing,
                destinoEntrenar: sesionLuego == .entrenar,
                onAtras: { ir(a: .acta) },
                onEntrar: { terminar(irAEntrenar: sesionLuego == .entrenar) })
        case .salida:
            OnbActoSalida(
                onReconsiderar: { ir(a: .permiso) },
                onEntrar: { irAActa(desde: .salida, luego: .entrar) })
        }
    }

    // MARK: El lienzo, acto por acto

    private var modo: AcumulacionSimulacion.Modo {
        switch acto {
        case .promesa:            return .disperso
        case .permiso, .salida:   return .quieto
        case .encendido:          return revelado ? .dentro : .convergencia
        // Acta con anatomía (vino del encendido con palabra) → descomposición. Acta coda-only
        // sin encendido («Ahora no», landing nil) → quieto: formar la esfera dibujaría un orbe
        // que ninguna evidencia sostiene. Acta coda-only tras encendido sin palabra → hereda
        // la esfera formada (`.dentro`) si ya reveló.
        case .acta:
            if actaAtras == .salida || landing == nil { return .quieto }
            if case .lectura = landing { return .descomposicion }
            return revelado ? .dentro : .quieto
        case .sesion:             return .circulacion
        }
    }

    /// El color al que el lienzo se tiñe cuando hay veredicto. La familia de PARTÍCULA (más
    /// profunda que los semánticos), la misma que usa el héroe de Cuerpo. Sin palabra no hay
    /// tinte: el orbe se queda gris en vez de apostar un color.
    private var destinoTinte: (r: Double, g: Double, b: Double)? {
        guard let landing, landing.revelaColor else { return nil }
        guard case let .lectura(verdict, _, _) = landing else { return nil }
        switch verdict {
        case .full:      return LiquidColor.ParticulaRGB.verde
        case .caution:   return LiquidColor.ParticulaRGB.ambar
        case .easy:      return LiquidColor.ParticulaRGB.roja
        case .lowSignal: return nil
        }
    }

    // MARK: Navegación

    private func ir(a destino: OnbActo) {
        withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)) { acto = destino }
    }

    /// Entra al Acta(+coda) dejando dicho de dónde vino (para «Atrás») y a dónde sale «Tu sesión».
    /// Su CTA es el mismo botón que la persona acaba de tocar, así que el paso se mete en el
    /// camino sin cambiarle el destino.
    private func irAActa(desde: OnbActo, luego: OnbPerfilLuego) {
        actaAtras = desde
        actaLuego = luego
        ir(a: .acta)
    }

    private func salirDelActa() {
        // Todas las ramas pasan por «Tu sesión» (FER-520). El destino final (Entrenar vs Cénit)
        // viaja en `sesionLuego`; `esSinReloj` / landing nil eligen la variante de la pantalla.
        sesionLuego = actaLuego
        ir(a: .sesion)
    }

    /// Salud se conectó DESPUÉS de que la coda ya corrió su autollenado: el sello se tira para
    /// que vuelva a correr, ahora sí con la puerta abierta. La excepción es lo que sostiene la
    /// regla —lo que la persona edita GANA—: si algún campo ya no coincide con el sello, hubo
    /// corrección a mano y el sello se queda como está.
    private func replantearAutollenado() {
        guard let s = perfilSello else { return }
        let intacto = profile.age == s.edad && profile.sex == s.sexo
            && profile.weightKg == s.pesoKg && profile.heightCm == s.estaturaCm
        if intacto { perfilSello = nil }
    }

    /// El final del flujo. «Ir a Entrenar» aterriza en la pestaña que sí funciona sin reloj,
    /// vía el mismo `TabRouter` que usan las demás pantallas.
    private func terminar(irAEntrenar: Bool = false) {
        if irAEntrenar { tabRouter.requested = .train }
        onFinished()
    }
}

// MARK: - Los cinco actos (+ la salida)

enum OnbActo: Hashable {
    /// 1 · La promesa.
    case promesa
    /// 2 · El permiso, que es también el diagrama de pesos. Único gate (FER-251).
    case permiso
    /// 3 · La conexión y la lectura: LA MISMA pantalla, que se transforma sin corte.
    case encendido
    /// 4 · El acta (+ perfil-coda FER-520): de qué está hecha la palabra, y los cuatro datos
    /// que el motor necesita de ti. Se captura en TODAS las ramas (FER-113).
    case acta
    /// 5 · Tu sesión · cierre: el `DosePlan` del día + «Entrenar hace. Cuerpo entiende.»
    case sesion
    /// La salida de «Ahora no».
    case salida
}

#if os(iOS) && DEBUG
extension OnbActo {
    /// El acto que pide `-cenit.onboardingActo <acto>`, para el mapa 100 % (FER-391). Claves = los
    /// nombres del enum, tal cual — sin alias ni abreviaturas que memorizar aparte.
    /// Sub-desenlaces del acto 5 se combinan con `-cenit.onboardingLanding` (lectura-full /
    /// calibrando / sinritmo / sindatos) y con el estado vacío natural (sin rutina en el store).
    static func debugFixture(_ raw: String) -> OnbActo? {
        switch raw {
        case "promesa":   return .promesa
        case "permiso":   return .permiso
        case "encendido": return .encendido
        case "acta":      return .acta
        case "sesion":    return .sesion
        case "salida":    return .salida
        // Alias de migración del mapa: capturas viejas que aún pidan el nombre anterior.
        case "ciclo":     return .sesion
        default:          return nil
        }
    }
}
#endif

// MARK: - El lienzo

/// El campo de partículas de fondo, con `densidad` y `teñido` ANIMABLES.
///
/// `LiquidOrbeAcumulacion` recibe la densidad como un `Double` cualquiera, y SwiftUI no interpola
/// los parámetros de una vista que no declara `Animatable`: un `withAnimation` sobre la densidad
/// la hacía SALTAR al valor final en el siguiente cuadro. Con `animatableData` el sistema vuelve a
/// evaluar este `body` en cada cuadro del tramo, que es lo que convierte «se llenó» en «se está
/// llenando». El teñido viaja en el mismo par porque el guion del encendido los encadena.
private struct OnbLienzo: View, Animatable {
    var densidad: Double
    var tenido: Double
    let modo: AcumulacionSimulacion.Modo
    let destino: (r: Double, g: Double, b: Double)?
    let dosCentros: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(densidad, tenido) }
        set { densidad = newValue.first; tenido = newValue.second }
    }

    var body: some View {
        LiquidOrbeAcumulacion(
            modo: modo,
            densidad: densidad,
            tinte: destino.map { LiquidColor.particulaTeñida(hacia: $0, k: tenido) },
            centroRelativo: dosCentros ? UnitPoint(x: 0.28, y: 0.30) : UnitPoint(x: 0.5, y: 0.34),
            centroSecundario: dosCentros ? UnitPoint(x: 0.72, y: 0.30) : nil)
    }
}

// MARK: - Preview

#if DEBUG
private struct OnboardingPreview: View {
    @State private var model = AppModel.preview
    var body: some View {
        OnboardingWizard(onFinished: {})
            .environment(model)
            .environmentObject(model.repo)
            .environmentObject(model.profile)
            .environmentObject(TabRouter())
            .environmentObject(HealthKitBridge(repo: model.repo,
                                               appleDeviceId: "preview-apple"))
            .frame(width: 390, height: 800)
    }
}

#Preview("Onboarding · cinco actos") { OnboardingPreview() }
#endif
