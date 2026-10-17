import SwiftUI
import CenitDesign

// MARK: - Actos 1 y 2 (+ la salida)  ·  FER-109
//
// El acto 1 promete y el 2 pide. Entre los dos no hay pantalla de relleno: el 2 ES el diagrama de
// pesos, así que quien concede el permiso ya sabe qué firma y con qué peso entra cada señal.
//
// El campo de partículas se comporta distinto en cada uno, y eso también es contenido:
//   · acto 1 `.disperso` — la materia se junta sola mientras lees. Todavía no hay evidencia
//     ninguna; lo que se ve es el campo presentándose, y por eso topa a la mitad y no cuaja.
//   · acto 2 `.quieto` — CONGELADO. Nada avanza hasta que la persona decide el permiso, que es
//     exactamente la verdad del momento: sin su sí, la app no puede dar un paso más.

// MARK: - Acto 1 · La promesa

struct OnbActoPromesa: View {
    @Binding var densidad: Double
    let onEmpezar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrancada = false

    var body: some View {
        OnbShell {
            Spacer(minLength: LiquidSpace.s800)

            // La marca no se traduce ni entra al catálogo: es un nombre propio.
            OnbOverline("Cénit")
            OnbTitular(OnbCopy.promesaTitular)
                .padding(.top, LiquidSpace.s250)
            OnbCuerpo(OnbCopy.promesaCuerpo)
                .padding(.top, LiquidSpace.s400)

            Spacer(minLength: LiquidSpace.s800)

            // La privacidad es UNA LÍNEA, no una tarjeta: convertirla en tarjeta la vuelve un
            // aviso legal, y aquí es una invitación a comprobarlo (modo avión) en el momento.
            OnbCuerpo(OnbCopy.promesaPrivacidad, tono: LiquidColor.tinta500)
                .padding(.bottom, LiquidSpace.s400)

            LiquidGlassButton(OnbCopy.empezar, variant: .primary, expands: true, action: onEmpezar)
        }
        .task {
            guard !arrancada else { return }
            arrancada = true
            // Reduce Motion: el mismo destino, sin rampa larga. Un fundido no es movimiento
            // (la propia simulación hace crossfade de densidad ahí), así que el beat no se pierde.
            let anim = reduceMotion
                ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                : LiquidMotion.ambient(OnbGuion.acumulacionPromesa)
            withAnimation(anim) { densidad = OnbGuion.densidadPromesa }
        }
    }
}
