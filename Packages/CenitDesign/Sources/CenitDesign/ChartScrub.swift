import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
// MARK: - La lupa de una gráfica
//   En iOS no hay puntero que pase por encima, así que «explorar el dato» es arrastrar el dedo y que
//   la lectura se pegue al dato más cercano. Este archivo es el ÚNICO lugar donde viven esa
//   matemática de pegado, la tarjeta de lectura, dónde se coloca, la raya vertical y el punto
//   resaltado — para que TrendChart, Sparkline, YearHeatStrip y la familia LiquidGlass se lean
//   igual en vez de reinventarse cada una la suya. En macOS eso lo maneja el puntero, no el dedo.

/// Las medidas de la lupa, con nombre. Un literal suelto repetido en tres vistas es exactamente lo
/// que este enum evita.
private enum MedidasDeLupa {
    static let acentoDiametro: CGFloat = 7
    static let acentoSeparacion: CGFloat = 8
    static let textoSeparacion: CGFloat = 1
    static let tarjetaRadio: CGFloat = 8
    static let tarjetaRelleno = EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
    static let filete: CGFloat = 1
    static let rayaCorta: [CGFloat] = [3, 3]
    /// Aire entre el dato y la tarjeta que lo nombra.
    static let holguraPorOmision: CGFloat = 12
    /// Tamaño supuesto de la tarjeta antes de que el primer layout la mida de verdad.
    static let tarjetaSinMedir = CGSize(width: 90, height: 40)
    static let puntoDiametro: CGFloat = 9
    /// Piso del diámetro de la manija plana, para que siga siendo tocable en papel cálido.
    static let manijaMinima: CGFloat = 13
}

private extension View {
    /// Cromo de lupa: se ve, no se toca. El gesto de arrastre pertenece a la gráfica de abajo.
    func inerte() -> some View { allowsHitTesting(false) }
}

// MARK: - Toque de selección

/// Un tic ligero de selección cuando el dedo se pega a un dato NUEVO (solo iOS; en macOS/watchOS no
/// hace nada). El generador se prepara una vez y se reutiliza, como pide la guía de Apple.
public enum ChartHaptics {
    #if canImport(UIKit) && os(iOS)
    @MainActor private static let generator = UISelectionFeedbackGenerator()
    #endif

    /// Llámalo al moverse a un dato nuevo (no nulo) — nunca al levantar el dedo.
    @MainActor public static func datumChanged() {
        #if canImport(UIKit) && os(iOS)
        generator.selectionChanged()
        generator.prepare()
        #endif
    }
}

// MARK: - La tarjeta de lectura

/// La lectura compacta que aparece junto al dato raspado: una línea de valor en negrita, una
/// etiqueta secundaria opcional, y un punto de acento que nombra el color que se está explicando.
struct ChartTooltip: View {
    var value: String
    var label: String?
    var accent: Color?

    @Environment(\.instrumentoFlat) private var flat

    init(value: String, label: String? = nil, accent: Color? = nil) {
        (self.value, self.label, self.accent) = (value, label, accent)
    }

    var body: some View { contenido.modifier(TarjetaDeLectura(flat: flat, vozDeVoiceOver: vozDeVoiceOver)) }

    /// Lo que VoiceOver lee: la tarjeta entera es UN elemento, no tres textos sueltos.
    private var vozDeVoiceOver: String { label.map { "\(value), \($0)" } ?? value }

    /// Punto de acento (si lo hay) + las dos líneas de texto.
    private var contenido: some View {
        HStack(alignment: .center, spacing: MedidasDeLupa.acentoSeparacion) {
            accent.map { tinta in
                Circle().fill(tinta)
                    .frame(width: MedidasDeLupa.acentoDiametro, height: MedidasDeLupa.acentoDiametro)
                    .shadow(color: flat ? .clear : tinta.opacity(0.8), radius: flat ? 0 : 3)
            }
            VStack(alignment: .leading, spacing: MedidasDeLupa.textoSeparacion) {
                Text(value).font(StrandFont.captionNumber).fontWeight(.semibold)
                    .foregroundStyle(LiquidColor.tinta900)
                label.map { texto in
                    Text(texto).font(StrandFont.footnote).foregroundStyle(LiquidColor.tinta700)
                }
            }
        }
    }
}

/// El envoltorio de la tarjeta: papel, canto, sombra y la etiqueta de accesibilidad. Va aparte del
/// contenido para que la receta de superficie no se mezcle con lo que se lee.
private struct TarjetaDeLectura: ViewModifier {
    let flat: Bool
    let vozDeVoiceOver: String

    private var canto: RoundedRectangle { RoundedRectangle(cornerRadius: MedidasDeLupa.tarjetaRadio, style: .continuous) }

    func body(content: Content) -> some View {
        content.padding(MedidasDeLupa.tarjetaRelleno)
            .background(canto.fill(LiquidColor.papelTarjeta))
            .overlay(canto.stroke(LiquidColor.tinta10, lineWidth: MedidasDeLupa.filete))
            .shadow(color: Color.black.opacity(flat ? 0.14 : 0.45), radius: flat ? 4 : 10, x: 0, y: flat ? 2 : 6)
            .fixedSize()
            .accessibilityElement(children: .ignore).accessibilityLabel(vozDeVoiceOver)
    }
}

// MARK: - Dónde cae la tarjeta

/// Coloca la tarjeta cerca de un ancla sin dejar que se salga del contenedor.
enum ChartTooltipPlacement {

    /// Prefiere quedar ARRIBA y centrada sobre el ancla; se voltea abajo si el borde superior la
    /// cortaría, y siempre termina recortada dentro de `container`.
    static func position(anchor: CGPoint, tooltipSize size: CGSize, in container: CGSize,
                         gap: CGFloat = MedidasDeLupa.holguraPorOmision) -> CGPoint {
        let mitad = Mitades(size)
        return CGPoint(x: mitad.xDentro(anchor.x, de: container),
                       y: mitad.yArribaOAbajo(de: anchor, holgura: gap, en: container))
    }

    /// El mismo contrato, pero empujada a UN COSTADO del ancla para no taparle el dato que nombra:
    /// centrarla puede cubrir justo el punto que se está explicando. Elige el lado con más aire, se
    /// voltea si ese lado no cabe, y solo cuando NINGUNO cabe (un plot más angosto que la tarjeta)
    /// cae de vuelta en `position`.
    static func positionBeside(anchor: CGPoint, tooltipSize size: CGSize, in container: CGSize,
                               gap: CGFloat = MedidasDeLupa.holguraPorOmision) -> CGPoint {
        let mitad = Mitades(size)
        let aLaDerecha = anchor.x + gap + mitad.ancho
        let aLaIzquierda = anchor.x - gap - mitad.ancho
        let cabeDerecha = aLaDerecha + mitad.ancho <= container.width
        let cabeIzquierda = aLaIzquierda - mitad.ancho >= 0
        guard cabeDerecha || cabeIzquierda else {
            return position(anchor: anchor, tooltipSize: size, in: container, gap: gap)
        }
        let sobraAireADerecha = (container.width - anchor.x) >= anchor.x
        let x = (sobraAireADerecha && cabeDerecha) || !cabeIzquierda ? aLaDerecha : aLaIzquierda
        return CGPoint(x: x, y: mitad.yArribaOAbajo(de: anchor, holgura: gap, en: container))
    }

    /// Las medias medidas de la tarjeta, con las dos reglas de encaje que ambas colocaciones
    /// comparten — antes estaban copiadas en las dos.
    private struct Mitades {
        let ancho, alto: CGFloat

        init(_ size: CGSize) { (ancho, alto) = (size.width / 2, size.height / 2) }

        /// X recortada para que la tarjeta quede entera dentro del contenedor.
        func xDentro(_ x: CGFloat, de container: CGSize) -> CGFloat {
            Self.recortar(x, entre: ancho, y: max(ancho, container.width - ancho))
        }

        /// Y arriba del ancla; abajo si arriba se cortaría. Siempre dentro del contenedor.
        func yArribaOAbajo(de anchor: CGPoint, holgura: CGFloat, en container: CGSize) -> CGFloat {
            var y = anchor.y - holgura - alto
            if y - alto < 0 { y = anchor.y + holgura + alto }
            return Self.recortar(y, entre: alto, y: max(alto, container.height - alto))
        }

        static func recortar(_ valor: CGFloat, entre piso: CGFloat, y techo: CGFloat) -> CGFloat {
            Swift.min(Swift.max(valor, piso), techo)
        }
    }
}

// MARK: - A qué dato se pega el dedo

/// La geometría que traduce dónde está el dedo al índice del dato más cercano.
enum ChartScrubMath {

    /// El índice más cercano entre `count` muestras repartidas parejo a lo ancho de `width`. Una x
    /// fuera de rango se pega a la muestra del extremo; con una sola muestra siempre da 0.
    static func nearestIndex(toX x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 1, width > 0 else { return count > 0 ? 0 : nil }
        let paso = width / CGFloat(count - 1)
        return Swift.min(Swift.max(Int((x / paso).rounded()), 0), count - 1)
    }

    /// El índice más cercano entre posiciones x arbitrarias (no repartidas parejo).
    static func nearestIndex(toX x: CGFloat, xs positions: [CGFloat]) -> Int? {
        positions.indices.min { abs(positions[$0] - x) < abs(positions[$1] - x) }
    }
}

// MARK: - La raya vertical

/// La raya discontinua que marca la x raspada. La comparten todas las gráficas para que el gesto se
/// lea idéntico en cualquier pantalla.
struct CrosshairRule: View {
    var x, height: CGFloat
    var color: Color = LiquidColor.tinta10

    var body: some View {
        Path { trazo in
            trazo.move(to: CGPoint(x: x, y: 0))
            trazo.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(color, style: StrokeStyle(lineWidth: MedidasDeLupa.filete, dash: MedidasDeLupa.rayaCorta))
        .inerte()
    }
}

// MARK: - El dato resaltado

/// El punto que marca la muestra raspada sobre una línea. En el sistema oscuro florece; sobre papel
/// cálido (`\.instrumentoFlat`) se lee como una manija plana más grande, sin halo.
struct HighlightDot: View {
    let color: Color
    let diameter: CGFloat

    @Environment(\.instrumentoFlat) private var flat

    init(color tono: Color, diameter lado: CGFloat = MedidasDeLupa.puntoDiametro) {
        (color, diameter) = (tono, lado)
    }

    var body: some View { cuerpo.inerte() }

    @ViewBuilder private var cuerpo: some View {
        if flat { manijaPlana } else { puntoQueFlorece }
    }

    /// Papel cálido: un aro grueso sobre fondo, sin halo — el brillo se ve sucio sobre papel.
    private var manijaPlana: some View {
        let lado = Swift.max(diameter + 4, MedidasDeLupa.manijaMinima)
        return Circle().fill(LiquidColor.fondoAlto).frame(width: lado, height: lado)
            .overlay(Circle().strokeBorder(color, lineWidth: 2.5).frame(width: lado, height: lado))
    }

    /// Sistema oscuro: halo difuminado + núcleo, para que el punto se despegue de la curva.
    private var puntoQueFlorece: some View {
        ZStack {
            halo
            disco(LiquidColor.fondoAlto, lado: diameter)
            disco(color, lado: diameter - 3)
        }
    }

    /// El halo: el mismo tono, más grande y difuminado, sumándose a la luz de abajo.
    private var halo: some View {
        disco(color, lado: diameter * 1.8)
            .blur(radius: diameter * 0.6).opacity(0.7).blendMode(.plusLighter)
    }

    private func disco(_ tono: Color, lado: CGFloat) -> some View {
        Circle().fill(tono).frame(width: lado, height: lado)
    }
}

// MARK: - La tarjeta, ya colocada

/// Envuelve una `ChartTooltip`, se mide a sí misma y se coloca cerca del ancla dentro del
/// contenedor — así `ChartTooltipPlacement` siempre trabaja con el tamaño REAL, no con una
/// suposición.
struct PositionedTooltip: View {
    let anchor: CGPoint
    let container: CGSize
    let tooltip: ChartTooltip

    @State private var medida: CGSize = .zero

    init(anchor ancla: CGPoint, container contenedor: CGSize, tooltip tarjeta: ChartTooltip) {
        (anchor, container, tooltip) = (ancla, contenedor, tarjeta)
    }

    /// Mientras la cinta no haya reportado nada, se coloca con un tamaño supuesto; en cuanto mide,
    /// se recoloca con el real.
    private var donde: CGPoint {
        ChartTooltipPlacement.position(anchor: anchor,
                                       tooltipSize: medida == .zero ? MedidasDeLupa.tarjetaSinMedir : medida,
                                       in: container)
    }

    var body: some View {
        tooltip.background { cinta }.position(donde).transition(.opacity).inerte()
    }

    /// Cinta métrica invisible: reporta el tamaño real de la tarjeta al primer layout y a cada
    /// cambio posterior.
    private var cinta: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { medida = proxy.size }
                .onChange(of: proxy.size) { _, nuevo in medida = nuevo }
        }
    }
}

#if DEBUG
#Preview("ChartTooltip") {
    let lecturas: [ChartTooltip] = [
        ChartTooltip(value: "Recovery 88", label: "Tue 3 Jun", accent: StrandPalette.recoveryColor(88)),
        ChartTooltip(value: "62 ms", label: "HRV · sample 14"),
        ChartTooltip(value: "18.7", label: "STRAIN · all-out", accent: StrandPalette.strainColor(18.7)),
    ]
    return VStack(spacing: 24) {
        ForEach(Array(lecturas.enumerated()), id: \.offset) { _, lectura in lectura }
    }
    .padding(40).frame(width: 320, height: 240)
    .background(LiquidColor.fondoAlto).preferredColorScheme(.light)
}
#endif
