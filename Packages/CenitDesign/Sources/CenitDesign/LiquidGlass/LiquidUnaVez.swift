import SwiftUI
import TipKit

// MARK: - LiquidUnaVez (épico FER-428 · D4/D2) — la tarjeta de una vez
//
// La familia visual de los HITOS del motor (FER-436: primera lectura, base firme, primera
// tendencia, carga leída, primera sesión, primer récord) y de la NOVEDAD MAYOR de una versión
// (FER-435: «Nuevo en esta versión»). TipKit pone la lógica de «una sola vez»
// (`Tip.MaxDisplayCount(1)` + `invalidate`); esta pieza pone el dibujo: un `TipView` vestido como
// un módulo más de la columna del huésped — mismo vidrio, mismo margen, kicker callado — y no un
// banner que llega de fuera («Huésped, no anuncio», ficha de UI FER-435/436).
//
// Contrato TipKit → anatomía:
//   · `title`         → kicker (`regla` MAYÚSCULAS, color `tono.rotulo`)
//   · `message`       → cuerpo (`cuerpoLista`, tinta700; la negrita de la primera frase la trae
//                       el propio `Tip` en su `Text`, el estilo no la inventa)
//   · `actions.first` → la PUERTA: acción de texto en `verdeProfundo` + chevron de fila;
//                       invalida con `.actionPerformed` además de correr su `handler`
//   · «Entendido»     → lo pone el estilo (`init(entendido:)`, como `LiquidConsejo`), tinta500,
//                       SIEMPRE a la derecha; invalida con `.tipClosed`
//
// Régimen = el de la pantalla huésped. Hoy/Tendencias `.sobrio`: la superficie queda clara y el
// único color de la tarjeta es la puerta — voz de marca, nunca juicio (`verdeProfundo` aunque el
// veredicto del día sea ámbar o rojo). Entrenar `.mosaico`: se tiñe como cualquier tesela del hub.
// El kicker lleva `tono.rotulo` en los dos regímenes: en sobrio con `.neutro` es tinta500 (la
// misma voz callada que la `regla` de los módulos de Hoy); con identidad de señal (`.verde` para
// la carga) habla la señal, como permite DESIGN §8.4 regla 2.
//
// Se aplica EN CADA SITIO de anclaje — `TipView(HitoTip(), arrowEdge: nil)
// .tipViewStyle(LiquidUnaVezTipStyle(tono:regimen:entendido:))` — no en la raíz: la raíz sigue
// siendo `LiquidConsejoTipStyle` para los consejos.
//
// Sin ícono, sin ilustración, sin «×», sin confeti; nunca modal; nunca encima del héroe. Sin
// animación propia: la pantalla decide y Reduce Motion la apaga (`transaction` nulo, como
// `LiquidConsejo`; el fundido interno de TipKit no tiene API pública — GAP heredado documentado ahí).

/// Constantes de la receta — fuera de la View para que los tests no toquen MainActor (patrón
/// `LiquidAvisoMetrics`). Todo sale de tokens; el único número es el chevron de fila.
enum LiquidUnaVezMetrics {
    /// Padding arriba y a los lados `s400`; abajo `s200` (la fila de acciones ya trae su aire).
    static let paddingArriba: CGFloat = LiquidSpace.s400
    static let paddingLados: CGFloat = LiquidSpace.s400
    static let paddingAbajo: CGFloat = LiquidSpace.s200
    /// Kicker → cuerpo.
    static let kickerACuerpo: CGFloat = LiquidSpace.s150
    /// Cuerpo → fila de acciones.
    static let cuerpoAAcciones: CGFloat = LiquidSpace.s200
    /// Rótulo de la puerta → chevron.
    static let puertaGap: CGFloat = LiquidSpace.s150
    /// Puerta ↔ «Entendido» cuando caben lado a lado.
    static let accionesGap: CGFloat = LiquidSpace.s400
    /// Puerta ↔ «Entendido» apiladas (Dynamic Type grande): sin gap — cada una ya mide 44.
    static let apiladoGap: CGFloat = 0
    /// Alto mínimo de cada acción — el objetivo táctil HIG (`LiquidControl.hitTarget`).
    static let accionAltura: CGFloat = LiquidControl.hitTarget
    /// Chevron de la puerta — el mismo que el de la fila de lista (`LiquidListRow`: 12).
    static let chevron: CGFloat = 12
    /// Fuente de la puerta y de «Entendido». La ficha de UI pide `tituloFilaLectura` (13/600 que
    /// escala con Dynamic Type); ese token NO nace en este lane (decisión del director, FER-436):
    /// hasta que exista se usa su base fija `tituloFila`, y el cambio es esta sola línea.
    static let accionFuente: Font = LiquidType.tituloFila
}

/// La tarjeta de una vez (hitos del motor, novedad mayor). Épico FER-428 · D4/D2.
public struct LiquidUnaVezTipStyle: TipViewStyle {
    /// Tono del vidrio y del kicker: la pantalla pasa el de su pestaña/señal; `.neutro` por defecto.
    let tono: LiquidTono
    /// Régimen del huésped: `.sobrio` por defecto (Hoy/Tendencias); `.mosaico` en el hub de Entrenar.
    let regimen: LiquidRegimen
    /// «Entendido» lo pone la APP (FER-429): `CenitDesign` no tiene catálogo de cadenas, así que
    /// un literal declarado aquí no se traduce. El default solo sirve al `#Preview` del paquete.
    let entendido: Text

    public init(tono: LiquidTono = .neutro,
                regimen: LiquidRegimen = .sobrio,
                entendido: Text = Text(verbatim: "Got it")) {
        self.tono = tono
        self.regimen = regimen
        self.entendido = entendido
    }

    public func makeBody(configuration: TipViewStyle.Configuration) -> some View {
        LiquidUnaVezBody(configuration: configuration, tono: tono, regimen: regimen,
                         entendido: entendido)
    }
}

/// Vista propia (en vez de un `View` anónimo) para que `@Environment` — Reduce Motion — funcione
/// sin ambigüedad dentro de `makeBody` (mismo patrón que `LiquidConsejoBody`).
private struct LiquidUnaVezBody: View {
    let configuration: TipViewStyle.Configuration
    let tono: LiquidTono
    let regimen: LiquidRegimen
    let entendido: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidUnaVezMetrics.cuerpoAAcciones) {
            texto
            acciones
        }
        .padding(.top, LiquidUnaVezMetrics.paddingArriba)
        .padding(.horizontal, LiquidUnaVezMetrics.paddingLados)
        .padding(.bottom, LiquidUnaVezMetrics.paddingAbajo)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(tono: tono, regimen: regimen)
        // VoiceOver: kicker + cuerpo (una parada) → puerta → «Entendido», en ese orden.
        .accessibilityElement(children: .contain)
        // Nada propio que animar — ver el GAP de arriba sobre la transición interna de TipKit.
        .transaction { t in if reduceMotion { t.animation = nil } }
    }

    /// Kicker + cuerpo: UNA parada de VoiceOver («Primera lectura. Ya te leo…»).
    private var texto: some View {
        VStack(alignment: .leading, spacing: LiquidUnaVezMetrics.kickerACuerpo) {
            if let title = configuration.title {
                title.liquidRegla().foregroundStyle(tono.rotulo)
            }
            if let message = configuration.message {
                message.font(LiquidType.cuerpoLista).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Puerta a la izquierda, «Entendido» a la derecha. Cuando los dos rótulos no caben en una
    /// línea (Dynamic Type grande), se apilan: puerta arriba, «Entendido» abajo, cada uno 44 pt.
    private var acciones: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LiquidUnaVezMetrics.accionesGap) {
                puerta
                Spacer()
                botonEntendido
            }
            VStack(alignment: .leading, spacing: LiquidUnaVezMetrics.apiladoGap) {
                puerta
                botonEntendido
            }
        }
    }

    /// La primera `Tips.Action` del tip: texto en voz de marca + chevron de fila. Corre su
    /// `handler` (navega) y cierra el tip como acción cumplida.
    @ViewBuilder
    private var puerta: some View {
        if let accion = configuration.actions.first {
            Button {
                accion.handler()
                configuration.tip.invalidate(reason: .actionPerformed)
            } label: {
                HStack(spacing: LiquidUnaVezMetrics.puertaGap) {
                    accion.label()
                        .font(LiquidUnaVezMetrics.accionFuente)
                        .foregroundStyle(LiquidColor.verdeProfundo)
                    LiquidIcon(.chevron, size: LiquidUnaVezMetrics.chevron,
                               color: LiquidColor.verdeProfundo)
                }
                .frame(minHeight: LiquidUnaVezMetrics.accionAltura)
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        }
    }

    private var botonEntendido: some View {
        Button {
            configuration.tip.invalidate(reason: .tipClosed)
        } label: {
            entendido
                .font(LiquidUnaVezMetrics.accionFuente)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(minHeight: LiquidUnaVezMetrics.accionAltura)
                .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityLabel(entendido)
    }
}

#if DEBUG
// Copy ilustrativo (es-MX) del preview aprobado `fer-436-tarjeta-una-vez.html`; el copy real lo
// fija el catálogo de la app. La negrita de arranque la trae el `Tip` en su propio `Text`.
private struct PrimeraLecturaPreviewTip: Tip {
    var title: Text { Text(verbatim: "Primera lectura") }
    var message: Text? {
        Text(verbatim: "Ya te leo.").bold()
            + Text(verbatim: " Esta palabra salió de tus 4 noches con el reloj. A las 14 conozco tu normal y dejo de avisarte la confianza.")
    }
    var actions: [Tips.Action] { [Tips.Action(id: "acta") { Text(verbatim: "De qué salió") }] }
}

private struct CargaLeidaPreviewTip: Tip {
    var title: Text { Text(verbatim: "Carga leída") }
    var message: Text? {
        Text(verbatim: "Ya leo tu carga:").bold()
            + Text(verbatim: " unas dos semanas de esfuerzo bastan. Toca la tarjeta para ver la colina.")
    }
}

private struct PrimeraSesionPreviewTip: Tip {
    var title: Text { Text(verbatim: "Primera sesión") }
    var message: Text? {
        Text(verbatim: "Tu primera sesión quedó registrada.").bold()
            + Text(verbatim: " Abajo van tus músculos trabajados y tu bitácora; cuando cumplas tus reps, te propongo subir.")
    }
    var actions: [Tips.Action] { [Tips.Action(id: "historial") { Text(verbatim: "Tu historial") }] }
}

private struct NovedadMayorPreviewTip: Tip {
    var title: Text { Text(verbatim: "Nuevo en esta versión") }
    var message: Text? {
        Text(verbatim: "Cénit 1.86 trae Ayuda y Novedades.").bold()
            + Text(verbatim: " Ahora puedes volver a ver todo lo que enseña la app y saber qué cambió.")
    }
    var actions: [Tips.Action] { [Tips.Action(id: "novedades") { Text(verbatim: "Ver novedades") }] }
}

private let entendidoPreview = Text(verbatim: "Entendido")

#Preview("Una vez · hito de Hoy con puerta · novedad mayor") {
    ScrollView {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            // Hoy (lienzo blanco, sobrio): el único color es la puerta.
            TipView(PrimeraLecturaPreviewTip(), arrowEdge: nil)
                .tipViewStyle(LiquidUnaVezTipStyle(entendido: entendidoPreview))
            TipView(NovedadMayorPreviewTip(), arrowEdge: nil)
                .tipViewStyle(LiquidUnaVezTipStyle(entendido: entendidoPreview))
        }
        .padding(LiquidSpace.s400)
    }
    .background(LiquidColor.fondoAlto)
    .task {
        try? Tips.resetDatastore()
        try? Tips.configure()
    }
}

#Preview("Una vez · verde sobrio (Tendencias) · verde mosaico (Entrenar)") {
    ScrollView {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            // Tendencias, pegada al módulo de carga: sobrio ignora el tono en la superficie,
            // el kicker sí lo lleva (identidad de carga). Sin puerta: solo «Entendido».
            TipView(CargaLeidaPreviewTip(), arrowEdge: nil)
                .tipViewStyle(LiquidUnaVezTipStyle(tono: .verde, regimen: .sobrio,
                                                   entendido: entendidoPreview))
            // Hub de Entrenar: una tesela más del mosaico.
            TipView(PrimeraSesionPreviewTip(), arrowEdge: nil)
                .tipViewStyle(LiquidUnaVezTipStyle(tono: .verde, regimen: .mosaico,
                                                   entendido: entendidoPreview))
        }
        .padding(LiquidSpace.s400)
    }
    .background(LiquidColor.fondoGradient)
    .task {
        try? Tips.resetDatastore()
        try? Tips.configure()
    }
}

#Preview("Una vez · Dynamic Type AX") {
    ScrollView {
        TipView(PrimeraLecturaPreviewTip(), arrowEdge: nil)
            .tipViewStyle(LiquidUnaVezTipStyle(entendido: entendidoPreview))
            .padding(LiquidSpace.s400)
    }
    .background(LiquidColor.fondoAlto)
    .dynamicTypeSize(.accessibility3)
    .task {
        try? Tips.resetDatastore()
        try? Tips.configure()
    }
}
#endif
