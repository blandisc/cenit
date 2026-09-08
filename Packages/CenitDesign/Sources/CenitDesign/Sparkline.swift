import SwiftUI
// MARK: - Sparkline
//   La línea chiquita que cabe dentro de una ficha: la FC en vivo, la tendencia comprimida de un
//   mosaico. Se traza con la rampa de color de su métrica, con un punto vivo en la última muestra y
//   un lavado tenue por debajo. Opcionalmente carga una banda de referencia y una regla de promedio.

/// Las proporciones del trazo, con nombre. Son geometría de dato, no fichas del sistema: viven aquí
/// porque solo esta pieza las usa.
private enum MedidasSpark {
    /// Aire que se le deja arriba y abajo a la serie cuando nadie fija el rango (12 % del recorrido).
    static let respiroDelRango = 0.12
    /// Opacidad del velo de la banda de referencia.
    static let veloDeBanda = 0.18
    /// Dónde se lee la rampa para teñir el lavado de área, y con cuánta opacidad.
    static let lecturaDelLavado = 0.7
    static let veloDelLavado = 0.22
    static let rayaDelPromedio: [CGFloat] = [3, 3]
    static let grosorDelPromedio: CGFloat = 1
    /// Multiplicadores del grosor de línea que dan el tamaño de la cabeza, plana y con halo.
    static let cabezaPlana: CGFloat = 2.4
    static let cabezaHalo: CGFloat = 3.2
    static let cabezaNucleo: CGFloat = 1.6
    static let cabezaDesenfoque: CGFloat = 1.2
    /// Piso del punto de raspado, para que siga siendo visible en una línea muy delgada.
    static let puntoRaspadoMinimo: CGFloat = 7
}

public struct Sparkline: View {

    // MARK: El dato y su rampa
    //
    // Todo se fija al construir la línea —por eso son `let`—: otra serie es otra Sparkline, no la
    // misma con un valor distinto encima.

    public let values: [Double]
    public let gradient: Gradient
    /// Rango de valores explícito; si no, se ajusta solo con un respiro arriba y abajo.
    public let range: ClosedRange<Double>?

    // MARK: Referencias opcionales, siempre en tinta y nunca en color de dato

    /// Banda de referencia opcional (p. ej. un rango típico p25–p75) dibujada tenue DETRÁS de la
    /// línea, en tono de tinta — nunca un color de dato, para que el valor de hoy se lea en contexto
    /// en vez de competir con el fondo.
    public let referenceBand: ClosedRange<Double>?
    public let bandColor: Color
    /// Regla discontinua de promedio, sobre el mismo eje que la línea.
    public let meanLine: Double?
    public let meanLineColor: Color

    // MARK: Qué se dibuja

    public let lineWidth: CGFloat
    public let showsArea: Bool
    public let showsHead: Bool
    public let showsScrub: Bool

    // MARK: Cómo se lee

    public let valueFormat: (Double) -> String
    /// Etiqueta secundaria de una muestra por índice (p. ej. una hora). Si falta, dice «sample N».
    public let indexLabel: ((Int) -> String)?

    public init(values serie: [Double],
                gradient rampa: Gradient = CenitPalette.recoveryGradient,
                range rangoFijo: ClosedRange<Double>? = nil,
                referenceBand banda: ClosedRange<Double>? = nil,
                bandColor tintaDeBanda: Color = InstrumentoTheme.base.hairlineStrong,
                meanLine promedio: Double? = nil,
                meanLineColor tintaDelPromedio: Color = InstrumentoTheme.base.hairlineStrong,
                lineWidth grosor: CGFloat = 2,
                showsArea conLavado: Bool = true,
                showsHead conCabeza: Bool = true,
                showsScrub conRaspado: Bool = true,
                valueFormat formatoDeValor: @escaping (Double) -> String = { Sparkline.defaultValueString($0) },
                indexLabel rotuloDeMuestra: ((Int) -> String)? = nil) {
        (values, gradient, range) = (serie, rampa, rangoFijo)
        (referenceBand, bandColor) = (banda, tintaDeBanda)
        (meanLine, meanLineColor) = (promedio, tintaDelPromedio)
        (lineWidth, showsArea) = (grosor, conLavado)
        (showsHead, showsScrub) = (conCabeza, conRaspado)
        (valueFormat, indexLabel) = (formatoDeValor, rotuloDeMuestra)
    }

    /// Dónde está el dedo (o el cursor) sobre la línea. `nil` = nadie está raspando.
    @State private var dedoX: CGFloat?

    /// Plano (sin halo ni destello) en el lenguaje claro de «Instrumento diurno».
    @Environment(\.instrumentoFlat) private var flat

    /// Entero cuando el valor es redondo; si no, con un decimal.
    public static func defaultValueString(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    public var body: some View { lienzo }

    /// El lienzo mide, proyecta la serie una sola vez y apila encima las cuatro capas del dibujo.
    private var lienzo: some View {
        GeometryReader { geo in
            capas(sobre: Trazo(valores: values, extremos: extremos, lienzo: geo.size))
        }
    }

    private func capas(sobre trazo: Trazo) -> some View {
        ZStack {
            referencias(trazo)
            curva(trazo)
            cabeza(trazo)
            lupa(trazo)
        }
        .animation(CenitMotion.fade, value: dedoX)
        .contentShape(.rect)
        .scrubGesture(enabled: showsScrub, hoverX: $dedoX)
    }

    // MARK: - Las cuatro capas del dibujo

    /// Lo que va DETRÁS de la línea: la banda de referencia y la regla de promedio.
    @ViewBuilder private func referencias(_ trazo: Trazo) -> some View {
        if let banda = referenceBand {
            let arriba = trazo.y(de: banda.upperBound), abajo = trazo.y(de: banda.lowerBound)
            Rectangle().fill(bandColor.opacity(MedidasSpark.veloDeBanda))
                .frame(height: Swift.max(1, abajo - arriba))
                .position(x: trazo.lienzo.width / 2, y: (arriba + abajo) / 2)
        }
        if let promedio = meanLine, trazo.puntos.count > 1 {
            let y = trazo.y(de: promedio)
            Path { raya in
                raya.move(to: CGPoint(x: 0, y: y))
                raya.addLine(to: CGPoint(x: trazo.lienzo.width, y: y))
            }
            .stroke(meanLineColor, style: StrokeStyle(lineWidth: MedidasSpark.grosorDelPromedio,
                                                      dash: MedidasSpark.rayaDelPromedio))
        }
    }

    /// El lavado de área y la línea misma. Una serie de un solo punto no dibuja ninguno de los dos:
    /// no hay recorrido que trazar.
    @ViewBuilder private func curva(_ trazo: Trazo) -> some View {
        if trazo.puntos.count > 1 {
            if showsArea { trazo.area.fill(velo) }
            trazo.linea.stroke(rampaHorizontal, style: pluma)
        }
    }

    /// El lavado bajo la línea: la rampa leída a dos tercios, desvaneciéndose a nada hacia abajo.
    private var velo: LinearGradient {
        LinearGradient(colors: [tinta(en: MedidasSpark.lecturaDelLavado).opacity(MedidasSpark.veloDelLavado), .clear],
                       startPoint: .top, endPoint: .bottom)
    }

    /// La rampa tendida a lo largo del tiempo: la línea cambia de color conforme avanza.
    private var rampaHorizontal: LinearGradient {
        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
    }

    /// La pluma con la que se traza la línea, de puntas y codos redondos.
    private var pluma: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    /// El punto vivo en la última muestra: plano sobre papel, con halo en el sistema oscuro.
    @ViewBuilder private func cabeza(_ trazo: Trazo) -> some View {
        if showsHead, let punta = trazo.puntos.last {
            let tono = tinta(en: 1.0)
            if flat {
                disco(tono, lado: lineWidth * MedidasSpark.cabezaPlana).position(punta)
            } else {
                disco(tono, lado: lineWidth * MedidasSpark.cabezaHalo)
                    .blur(radius: lineWidth * MedidasSpark.cabezaDesenfoque)
                    .opacity(0.8).blendMode(.plusLighter).position(punta)
                disco(.white, lado: lineWidth * MedidasSpark.cabezaNucleo).position(punta)
            }
        }
    }

    /// El cromo de raspado: raya vertical, punto resaltado y la tarjeta que lo nombra.
    @ViewBuilder private func lupa(_ trazo: Trazo) -> some View {
        if showsScrub, let x = dedoX,
           let indice = ChartScrubMath.nearestIndex(toX: x, count: values.count, width: trazo.lienzo.width),
           indice < trazo.puntos.count {
            let punto = trazo.puntos[indice]
            let tono = tinta(en: values.count > 1 ? Double(indice) / Double(values.count - 1) : 1.0)
            CrosshairRule(x: punto.x, height: trazo.lienzo.height)
            HighlightDot(color: tono, diameter: ladoDelPuntoRaspado).position(punto)
            PositionedTooltip(anchor: punto, container: trazo.lienzo, tooltip: globo(indice, tono: tono))
        }
    }

    /// Diámetro del punto de raspado: proporcional al grosor, con un piso para que una línea muy
    /// delgada no lo deje invisible.
    private var ladoDelPuntoRaspado: CGFloat {
        Swift.max(MedidasSpark.puntoRaspadoMinimo, lineWidth * 3)
    }

    /// Lo que dice el globo de una muestra: su valor formateado y cómo se llama esa muestra.
    private func globo(_ indice: Int, tono: Color) -> ChartTooltip {
        let nombre = indexLabel?(indice) ?? String(localized: "sample \(indice + 1)", bundle: .main)
        return ChartTooltip(value: valueFormat(values[indice]), label: nombre, accent: tono)
    }

    // MARK: - Ayudas

    private func disco(_ tono: Color, lado: CGFloat) -> some View {
        Circle().fill(tono).frame(width: lado, height: lado)
    }

    /// El color de la rampa en una posición normalizada del trazo.
    private func tinta(en posicion: Double) -> Color {
        CenitPalette.sample(stops: gradient.stops, at: posicion)
    }

    /// El recorrido de valores contra el que se dibuja, con la banda de referencia plegada dentro
    /// para que nunca quede cortada.
    private var extremos: (piso: Double, techo: Double) {
        // Un rango explícito manda: nadie recalcula lo que el llamador ya decidió.
        guard range == nil else { return (range!.lowerBound, range!.upperBound) }

        var piso = values.min()
        var techo = values.max()
        if let banda = referenceBand {
            piso = Swift.min(piso ?? banda.lowerBound, banda.lowerBound)
            techo = Swift.max(techo ?? banda.upperBound, banda.upperBound)
        }
        guard let piso, let techo else { return (0, 1) }
        guard piso != techo else { return (piso - 1, techo + 1) }

        let respiro = (techo - piso) * MedidasSpark.respiroDelRango
        return (piso - respiro, techo + respiro)
    }
}

// MARK: - La proyección
//
// Toda la geometría del trazo en un valor aparte: se calcula UNA vez por pasada de layout y las
// cuatro capas del dibujo la comparten, en vez de reproyectar la serie cada una por su cuenta.
private struct Trazo {
    let lienzo: CGSize
    let puntos: [CGPoint]
    private let piso, techo: Double

    init(valores: [Double], extremos: (piso: Double, techo: Double), lienzo: CGSize) {
        self.lienzo = lienzo
        (piso, techo) = extremos
        puntos = Self.proyectar(valores, entre: extremos, en: lienzo)
    }

    /// Reparte las muestras parejo a lo ancho y las cuelga de su valor. Una sola muestra se planta a
    /// media anchura: no hay reparto que hacer con un punto.
    private static func proyectar(_ valores: [Double],
                                  entre extremos: (piso: Double, techo: Double),
                                  en lienzo: CGSize) -> [CGPoint] {
        let total = valores.count
        let recorrido = Swift.max(extremos.techo - extremos.piso, 0.0001)
        return valores.enumerated().map { orden, valor in
            let x = total > 1 ? CGFloat(orden) / CGFloat(total - 1) * lienzo.width : lienzo.width / 2
            let alto = CGFloat((valor - extremos.piso) / recorrido)
            return CGPoint(x: x, y: lienzo.height - alto * lienzo.height)
        }
    }

    /// La y de un valor cualquiera sobre el MISMO eje que los puntos — así la banda de referencia y
    /// la regla de promedio comparten escala con la línea.
    func y(de valor: Double) -> CGFloat {
        let recorrido = Swift.max(techo - piso, 0.0001)
        return lienzo.height - CGFloat((valor - piso) / recorrido) * lienzo.height
    }

    /// La polilínea que une las muestras.
    var linea: Path {
        Path { camino in
            guard let arranque = puntos.first else { return }
            camino.move(to: arranque)
            puntos.dropFirst().forEach { camino.addLine(to: $0) }
        }
    }

    /// La misma polilínea, cerrada contra el piso del lienzo, para el lavado de área.
    var area: Path {
        guard let arranque = puntos.first, let final = puntos.last else { return linea }
        var camino = linea
        camino.addLine(to: CGPoint(x: final.x, y: lienzo.height))
        camino.addLine(to: CGPoint(x: arranque.x, y: lienzo.height))
        camino.closeSubpath()
        return camino
    }
}

#if DEBUG
/// Una FC sintética con oscilación y ruido, para que la línea tenga forma de dato y no de seno.
private func pulsoDeMuestra(_ muestras: Int = 48) -> [Double] {
    (0..<muestras).map { tic -> Double in
        let oscilacion: Double = 10 * sin(Double(tic) / 4.0)
        let ruido = Double((tic * 13) % 7)
        return 58 + oscilacion + ruido
    }
}

/// Las medidas del muestrario: solo se usan en el `#Preview` de abajo.
private enum MedidasDelMuestrario {
    static let lineaEnFicha = CGSize(width: 160, height: 44)
    static let numeral: CGFloat = 34
    static let aireEnFicha: CGFloat = 8
}

/// Un numeral con su unidad y, pegada a la derecha, la línea comprimida: el caso de una ficha real.
private struct FichaConLinea: View {
    let pulso: [Double]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MedidasDelMuestrario.aireEnFicha) {
            Text(verbatim: "64").font(CenitFont.number(MedidasDelMuestrario.numeral))
                .foregroundStyle(InstrumentoTheme.base.ink)
            Text(verbatim: "bpm").font(CenitFont.caption)
                .foregroundStyle(InstrumentoTheme.base.inkTertiary)
            Spacer(minLength: 0)
            Sparkline(values: pulso,
                      valueFormat: { "\(Int($0.rounded())) bpm" },
                      indexLabel: { "\($0)s ago" })
                .frame(width: MedidasDelMuestrario.lineaEnFicha.width,
                       height: MedidasDelMuestrario.lineaEnFicha.height)
        }
    }
}

#Preview("Sparkline · pulso en vivo") {
    let pulso = pulsoDeMuestra()
    return VStack(alignment: .leading, spacing: 20) {
        FichaConLinea(pulso: pulso)
        Sparkline(values: pulso, gradient: CenitPalette.strainGradient).frame(height: 60)
        Text(verbatim: "Raspa una línea para leer la muestra que queda bajo el cursor.")
            .font(CenitFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
    }
    .padding(24).frame(width: 380, height: 220)
    .background(InstrumentoTheme.base.surface).preferredColorScheme(.light)
}
#endif
