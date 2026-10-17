import SwiftUI
import CenitDesign

// MARK: - OnboardingWizard  ·  la bienvenida de dos pantallas (CEN-66, Camino C+)
//
// Pantalla 1: la promesa, sobre el lienzo de partículas. «Empezar» termina el onboarding y la app
// aterriza en la raíz de Fuerza, que sin plan ES la pantalla 2 (plantilla / arma la tuya / importa).
// No hay permiso de Salud aquí (se ofrece al cerrar la primera sesión, CEN-44), ni acta, ni perfil:
// los cinco actos anteriores se retiraron con el barrido 2 (CEN-65).

struct OnboardingWizard: View {

    /// Se llama cuando el usuario toca «Empezar».
    var onFinished: () -> Void

    /// 0…1 de cuánta materia hay en el lienzo; la promesa la sube con su rampa.
    @State private var densidad: Double = 0

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            OnbLienzo(densidad: densidad, tenido: 0, modo: .disperso, destino: nil, dosCentros: false)
                .ignoresSafeArea()
                .zIndex(0)
            OnbActoPromesa(densidad: $densidad, onEmpezar: onFinished)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
