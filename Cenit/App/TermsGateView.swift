import SwiftUI
import CenitDesign

/// Gate de aceptación de primer arranque (clickwrap). Se muestra sobre TODO —antes del onboarding y
/// de cualquier acceso a los datos— hasta que se acepta la versión vigente (`Terms.currentVersion`),
/// y vuelve a salir si los términos cambian de fondo. Hay que encender el interruptor, que NO viene
/// pre-encendido, y pulsar el botón; la versión aceptada se guarda en el teléfono, que es el
/// equivalente en-dispositivo de un registro de consentimiento.
///
/// FER-241 — migrated to «Liquid Glass · El Eje» régimen sobrio, reusing the onboarding shell
/// (`OnbShell` + `OnbOverline` / `OnbTitular` / `OnbCuerpo`) and `LiquidGlassButton`. Logic
/// unchanged: the consent toggle still gates Accept, and `onAccept` still records the version.
struct TermsGateView: View {
    /// Graba la versión aceptada. Lo provee `ContentView`, que es quien la persiste.
    let onAccept: () -> Void

    @State private var aceptado = false

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()

            OnbShell(indicadores: true) {
                // La marca no se traduce: es un nombre propio (mismo criterio que OnbActoPromesa).
                OnbOverline("Cénit")
                OnbTitular(Terms.title)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(Terms.intro)
                    .padding(.top, LiquidSpace.s400)

                VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                    ForEach(Terms.points) { point in
                        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                            Text(point.title)
                                .font(LiquidType.titulo)
                                .foregroundStyle(LiquidColor.tinta900)
                                .fixedSize(horizontal: false,
                                           vertical: true)
                            OnbCuerpo(point.body)
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, LiquidSpace.s800)

                // FER-398: la letra chica ES el enlace al texto completo. Antes remitía a «TERMS.md,
                // shipped with Cénit» — cierto para quien clona el repo, falso para quien baja la app:
                // ese archivo no viaja en el bundle. Un `Link` sobre el mismo `OnbCuerpo` conserva la
                // tipografía del sistema y le da a VoiceOver el rasgo de enlace.
                Link(destination: Terms.fullTermsURL) {
                    OnbCuerpo(Terms.fine, tono: LiquidColor.tinta500)
                }
                .padding(.top, LiquidSpace.s550)
            } pie: {
                filaDeConsentimiento
                botonDeAceptar
            }
        }
    }

    /// El interruptor y su frase. La frase se lee UNA vez: es la etiqueta de VoiceOver del
    /// interruptor, y el texto visible de al lado se oculta para no repetirla.
    private var filaDeConsentimiento: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            Toggle("", isOn: $aceptado)
                .labelsHidden()
                .tint(LiquidColor.verdePrimario)
                .toggleStyle(.switch)
                .strandAnimation(LiquidMotion.glassOut(LiquidMotion.quick), value: aceptado)
                .accessibilityLabel(Text(Terms.consent))

            OnbCuerpo(Terms.consent, tono: LiquidColor.tinta900)
                .accessibilityHidden(true)
        }
        .padding(.bottom, LiquidSpace.s400)
    }

    /// Aceptar solo existe con el interruptor encendido: el consentimiento no se presupone.
    private var botonDeAceptar: some View {
        LiquidGlassButton(Terms.cta,
                          variant: .primary,
                          expands: true,
                          action: onAccept)
            .disabled(!aceptado)
            .keyboardShortcut(.defaultAction)
    }
}
