import SwiftUI
import CenitDesign
import CenitAnalytics

// MARK: - Acto 4 · El acta + perfil-coda (FER-109 · FER-520)
//
// De qué está hecha la palabra. El lienzo entra en `.descomposicion`: el orbe se desarma en tres
// pozos, uno por eje, DELANTE del usuario — es el mismo gesto que el acta explica en texto, y por
// eso la pantalla no necesita un diagrama aparte.
//
// FER-520: el Perfil deja de ser acto navegable y entra como **coda** al pie (separada por
// `LiquidSpace.s800`). Si no hubo palabra (calibrando / sin ritmo / sin datos / «Ahora no»), se
// omite la anatomía y se muestra un encabezado honesto corto + la coda: el perfil SIEMPRE se
// captura (FER-113).
//
// Dos cosas que este acto NO hace, a propósito:
//   · **No inventa un puntaje.** No hay 0 a 100 en ninguna parte de la app, y el acto lo dice en
//     su primera línea en vez de dejar que el usuario lo suponga.
//   · **No re-escribe las cuatro palabras.** Salen de `LiquidHoyBuilder` (las mismas claves del
//     catálogo que dice el héroe). Aquí solo viven sus GLOSAS, que son de este acto.
//
// El titular es la palabra del veredicto, teñida, pero a talla de titular (22): la única talla de
// 30 en todo el flujo es el reveal del acto 3→4, y repetirla aquí le quitaría lo que la hace única.

struct OnbActoActa: View {

    let landing: OnboardingLanding?
    @Binding var sello: OnbPerfilSello?
    /// ¿Se llegó por «Ahora no»? Lo sabe el wizard (`actaAtras == .salida`).
    let desdeSalida: Bool
    let onAtras: () -> Void
    let onContinuar: () -> Void

    /// ¿Hay palabra teñida que descomponer? Misma puerta que `revelaColor` / `.lectura`.
    private var hayPalabra: Bool {
        if case .lectura = landing { return true }
        return false
    }

    var body: some View {
        // Los `Group` son puramente estructurales: SwiftUI tope los hijos de un builder en 10 y
        // el acta+coda desborda. `Group` es transparente para el layout, así que cada renglón sigue
        // siendo hermano directo del `VStack` del shell.
        //
        // Acto largo por construcción: enseña su barra de scroll.
        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                if hayPalabra {
                    anatomia
                } else {
                    encabezadoSinPalabra
                }
            }

            Group {
                OnbPerfilCoda(sello: $sello, landing: landing, desdeSalida: desdeSalida)
                    .padding(.top, LiquidSpace.s800)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(OnbCopy.actaCta, variant: .primary, expands: true,
                                  action: onContinuar)
            }
        }
    }

    // MARK: - Anatomía (ruta con palabra)

    @ViewBuilder
    private var anatomia: some View {
        // Los `Group` son estructurales (tope de 10 hijos por builder); transparentes al layout.
        Group {
            OnbOverline(OnbCopy.actaOverline)
                .padding(.top, LiquidSpace.s250)
            OnbTitular(palabra, tono: tono)
                .padding(.top, LiquidSpace.s250)
            OnbCuerpo(OnbCopy.actaIntro)
                .padding(.top, LiquidSpace.s300)
        }

        // Las cuatro palabras. Los títulos son los del catálogo; las glosas, de este acto.
        Group {
            OnbOverline(OnbCopy.actaOverlinePalabras)
                .padding(.top, LiquidSpace.s800)
            OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.full),
                    tono: LiquidColor.verdeTexto, glosa: OnbCopy.actaGlosaFull)
            OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.caution),
                    tono: LiquidColor.atencionTexto, glosa: OnbCopy.actaGlosaCaution)
            OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.easy),
                    tono: LiquidColor.negativo, glosa: OnbCopy.actaGlosaEasy)
            OnbFila(nombre: LiquidHoyBuilder.palabraCalibrando,
                    tono: nil, glosa: OnbCopy.actaGlosaCalibrando)
        }

        // Los TRES votos que cuenta el motor: autonómico, sueño y el centinela.
        Group {
            OnbOverline(OnbCopy.actaOverlineEjes)
                .padding(.top, LiquidSpace.s800)
            OnbFila(nombre: OnbCopy.actaEjeAutonomico, tono: LiquidColor.rosa,
                    glosa: OnbCopy.actaEjeAutonomicoGlosa, etiqueta: OnbCopy.etiquetaManda)
            OnbFila(nombre: OnbCopy.actaEjeSueno, tono: LiquidColor.indigo,
                    glosa: OnbCopy.actaEjeSuenoGlosa, etiqueta: OnbCopy.etiquetaVota)
            OnbFila(nombre: OnbCopy.actaEjeTemp, tono: LiquidColor.doradoTemp,
                    glosa: OnbCopy.actaEjeTempGlosa, etiqueta: OnbCopy.etiquetaEnPar)
            OnbFila(nombre: OnbCopy.actaResp, tono: LiquidColor.azul,
                    glosa: OnbCopy.actaRespGlosa, etiqueta: OnbCopy.etiquetaEnPar)
        }

        // Dentro del eje que manda: aquí sí aparecen los PESOS.
        Group {
            OnbOverline(OnbCopy.actaOverlineDentro)
                .padding(.top, LiquidSpace.s800)
            OnbFila(nombre: OnbCopy.actaRhr, tono: LiquidColor.rosa,
                    glosa: OnbCopy.actaRhrGlosa, peso: Self.pesoCompleto,
                    etiqueta: OnbCopy.etiquetaEspina)
            OnbFila(nombre: OnbCopy.actaVfcNoche, tono: LiquidColor.cian,
                    glosa: OnbCopy.actaVfcNocheGlosa, peso: Self.pesoMitad,
                    etiqueta: OnbCopy.etiquetaAcompana)
        }

        // Lo que no pesa, y por qué. Sin hue: la ausencia de identidad de color ES el dato.
        Group {
            OnbOverline(OnbCopy.actaOverlineNoPesa)
                .padding(.top, LiquidSpace.s800)
            OnbFila(nombre: OnbCopy.actaVfcDia, tono: nil, glosa: OnbCopy.actaVfcDiaGlosa,
                    etiqueta: OnbCopy.etiquetaFuera)
            OnbFila(nombre: OnbCopy.actaPasos, tono: nil, glosa: OnbCopy.actaPasosGlosa,
                    etiqueta: OnbCopy.etiquetaNunca)
        }

        // Contra qué te comparo.
        Group {
            OnbTarjeta {
                OnbOverline(OnbCopy.actaOverlineContra)
                OnbCuerpo(OnbCopy.actaContra)
            }
            .padding(.top, LiquidSpace.s800)

            OnbCuerpo(OnbCopy.actaPie, tono: LiquidColor.tinta500)
                .padding(.top, LiquidSpace.s600)
        }
    }

    // MARK: - Sin palabra (calibrando / sin ritmo / sin datos / salida)

    @ViewBuilder
    private var encabezadoSinPalabra: some View {
        OnbOverline(OnbCopy.actaOverline)
            .padding(.top, LiquidSpace.s250)
        OnbCuerpo(OnbCopy.actaSinPalabra)
            .padding(.top, LiquidSpace.s300)
    }

    /// El peso de la FC en reposo dentro del eje autonómico (`wRHR`) y el de la VFC nocturna.
    /// Son etiquetas del DATO, no copy: no se traducen.
    private static let pesoCompleto = "1.0"
    private static let pesoMitad = "0.5"

    /// La palabra que se está descomponiendo. Solo se consulta con `hayPalabra`.
    private var palabra: String {
        guard case let .lectura(verdict, _, _) = landing else {
            return LiquidHoyBuilder.palabraCalibrando
        }
        return LiquidHoyBuilder.palabraVeredicto(verdict)
    }

    private var tono: Color {
        guard case let .lectura(verdict, _, _) = landing else { return LiquidColor.tinta700 }
        switch verdict {
        case .full:      return LiquidColor.verdePrimario
        // El ámbar de dato no alcanza AA en texto; su hermano de lectura sí.
        case .caution:   return LiquidColor.atencionTexto
        case .easy:      return LiquidColor.negativo
        case .lowSignal: return LiquidColor.tinta700
        }
    }
}
