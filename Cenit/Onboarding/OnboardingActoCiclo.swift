import SwiftUI
import CenitDesign
import StrandAnalytics

// MARK: - Acto 7 · El ciclo y la mañana (FER-109)
//
// El último acto contesta la única pregunta que queda: «y con eso, qué». La lectura no es un dato
// para archivar; es lo que decide el día, y quien lo ejecuta es Entrenar.
//
// El lienzo entra en `.circulacion`, con DOS centros: las motas viajan de un orbe al otro sin
// parar. Es el ciclo hecho movimiento, y es la única vez en todo el flujo que el campo tiene dos
// casas — exactamente las dos que el dock de abajo enseña.
//
// Sin confeti y sin celebración: el veredicto de mañana puede ser «Recupera», y un onboarding que
// termina en fiesta le pone un tono a la app que la app no sostiene al día siguiente.
//
// FER-431: las ramas `.sinRitmoEnReposo` / `.sinDatos` también llegan aquí, con una variante que
// nombra las cuatro pestañas sin reloj y no ofrece el aviso matutino.

struct OnbActoCiclo: View {

    let landing: OnboardingLanding?
    /// CTA final aterriza en Entrenar cuando es `true` (FER-431). La ruta con reloj pasa `false`.
    let destinoEntrenar: Bool
    let onAtras: () -> Void
    let onEntrar: () -> Void

    /// Variante adaptada para quien no tiene reloj (FER-431). Una sola definición vía
    /// `OnboardingLanding.esSinReloj`.
    private var sinReloj: Bool { landing?.esSinReloj == true }

    var body: some View {
        if sinReloj {
            cuerpoSinReloj
        } else {
            cuerpoConReloj
        }
    }

    // MARK: Con reloj (cuerpo histórico — no mover)

    @ViewBuilder
    private var cuerpoConReloj: some View {
        // Los `Group` son puramente estructurales (tope de 10 hijos por builder); son
        // transparentes para el layout, así que cada pieza sigue siendo hermana directa del
        // `VStack` del shell y los `Spacer` siguen empujando el CTA al pie.
        //
        // Acto largo (traducción + tarjeta + cierre + dock): enseña su barra de scroll.
        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.cicloOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(OnbCopy.cicloTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.cicloCuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            // Cómo se traduce: los mismos títulos del catálogo del acta, ahora con lo que HACEN.
            Group {
                OnbOverline(OnbCopy.cicloOverlineTraduce)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.full),
                        tono: LiquidColor.verdePrimario, glosa: OnbCopy.cicloFull)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.caution),
                        tono: LiquidColor.atencionTexto, glosa: OnbCopy.cicloCaution)
                OnbFila(nombre: LiquidHoyBuilder.palabraVeredicto(.easy),
                        tono: LiquidColor.negativo, glosa: OnbCopy.cicloEasy)
            }

            Group {
                OnbTarjeta {
                    OnbCuerpo(OnbCopy.cicloTarjetaFuerte, fuerte: true)
                    OnbCuerpo(OnbCopy.cicloTarjetaCuerpo)
                }
                .padding(.top, LiquidSpace.s600)

                OnbCuerpo(OnbCopy.cicloPie, tono: LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s300)
            }

            // El cierre vive en el MISMO acto, abajo: el ritual de la noche es la consecuencia de
            // todo lo anterior, no una pantalla más que despedir.
            Group {
                OnbTitular(conReloj ? OnbCopy.cierreTitular : OnbCopy.cierreTitularSinReloj)
                    .padding(.top, LiquidSpace.s800)
                OnbCuerpo(conReloj ? OnbCopy.cierreCuerpo : OnbCopy.cierreCuerpoSinReloj)
                    .padding(.top, LiquidSpace.s300)
                // El aviso solo se ofrece donde puede existir: sin PALABRA no hay lectura que
                // anunciar y `MorningReadingScheduler.plan` sale vacío (`hayLectura`), así que en
                // `.calibrando` sería un recordatorio prometido que nunca va a sonar (FER-429: antes
                // se ofrecía con `conReloj`, que es cierto también mientras calibra).
                if hayLectura {
                    OnbCuerpo(OnbCopy.cierreAviso, tono: LiquidColor.tinta500)
                        .padding(.top, LiquidSpace.s250)
                }
            }

            // El dock REAL, no un dibujo: lo que se promete arriba es lo que se toca abajo.
            Group {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    Text(OnbCopy.cicloDock)
                        .groteskOverline()
                        .foregroundStyle(LiquidColor.tinta500)
                    LiquidTabBar(active: .hoy, rotulos: .cenit)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    OnbCuerpo(OnbCopy.cicloDockPie, tono: LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(OnbCopy.entrar, variant: .primary, expands: true, action: onEntrar)
            }
        }
    }

    // MARK: Sin reloj (FER-431 · D3 = A)

    @ViewBuilder
    private var cuerpoSinReloj: some View {
        let sinDatos: Bool = {
            if case .sinDatos = landing { return true }
            return false
        }()
        let destino: LiquidTab = destinoEntrenar ? .entrenar : .hoy
        let cta = destinoEntrenar ? OnbCopy.sinFcCta : OnbCopy.entrar

        OnbShell(indicadores: true) {
            Group {
                OnbAtras(accion: onAtras)

                OnbOverline(OnbCopy.cicloSinRelojOverline)
                    .padding(.top, LiquidSpace.s250)
                OnbTitular(OnbCopy.cicloSinRelojTitular)
                    .padding(.top, LiquidSpace.s250)
                OnbCuerpo(OnbCopy.cicloSinRelojCuerpo)
                    .padding(.top, LiquidSpace.s300)
            }

            Group {
                OnbOverline(OnbCopy.cicloSinRelojOverlineMapa)
                    .padding(.top, LiquidSpace.s800)
                OnbFila(nombre: OnbCopy.pestanaHoy,
                        tono: nil,
                        glosa: sinDatos ? OnbCopy.cicloSinRelojHoySinSalud : OnbCopy.cicloSinRelojHoy)
                OnbFila(nombre: OnbCopy.pestanaTendencias,
                        tono: nil,
                        glosa: OnbCopy.cicloSinRelojTendencias)
                OnbFila(nombre: OnbCopy.pestanaEntrenar,
                        tono: LiquidColor.verdePrimario,
                        glosa: OnbCopy.cicloSinRelojEntrenar)
                OnbFila(nombre: OnbCopy.pestanaAjustes,
                        tono: nil,
                        glosa: sinDatos ? OnbCopy.cicloSinRelojAjustesSinSalud : OnbCopy.cicloSinRelojAjustes)
            }

            Group {
                OnbTarjeta {
                    OnbCuerpo(OnbCopy.cicloTarjetaFuerte, fuerte: true)
                    OnbCuerpo(OnbCopy.cicloTarjetaCuerpo)
                }
                .padding(.top, LiquidSpace.s600)
            }

            Group {
                VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                    Text(OnbCopy.cicloDock)
                        .groteskOverline()
                        .foregroundStyle(LiquidColor.tinta500)
                    LiquidTabBar(active: destino, rotulos: .cenit)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    OnbCuerpo(OnbCopy.cicloDockPie, tono: LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, LiquidSpace.s600)

                Spacer(minLength: LiquidSpace.s600)

                LiquidGlassButton(cta, variant: .primary, expands: true, action: onEntrar)
            }
        }
    }

    /// ¿Hay noches con el reloj puesto? Decide qué cierre es honesto en la ruta CON reloj.
    /// En `.calibrando(0)` —alguien CON reloj (hay FC en reposo) pero sin noches nocturnas—
    /// el cierre «sin reloj» le habla a quien tiene reloj y no ha dormido con él. Las ramas
    /// `.sinRitmoEnReposo` / `.sinDatos` ya no pasan por aquí (van a `cuerpoSinReloj`, FER-431).
    private var conReloj: Bool {
        switch landing {
        case let .lectura(_, noches, _):     return noches > 0
        case let .calibrando(noches, _, _):  return noches > 0
        default:                              return false
        }
    }

    /// ¿Ya hay palabra? Solo entonces el aviso matutino tiene algo que anunciar. Es la misma verdad
    /// que `MorningReadingScheduler.hayLectura`: en `.calibrando` el plan sale vacío y el aviso no
    /// suena, así que ofrecerlo ahí sería mentir (FER-429).
    private var hayLectura: Bool {
        if case .lectura = landing { return true }
        return false
    }
}

// MARK: - Predicado «sin reloj» (FER-431)

extension OnboardingLanding {
    /// `true` para `.sinRitmoEnReposo` y `.sinDatos`: decide el Ciclo adaptado (FER-431).
    var esSinReloj: Bool {
        switch self {
        case .sinRitmoEnReposo, .sinDatos: return true
        default: return false
        }
    }
}
