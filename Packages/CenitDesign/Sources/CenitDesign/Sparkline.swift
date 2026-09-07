import SwiftUI
// MARK: - Sparkline
//
// La línea chiquita que cabe dentro de una ficha: la FC en vivo, la tendencia comprimida de un
// mosaico. Se traza con la rampa de color de su métrica, con un punto vivo en la última muestra y un
// lavado tenue por debajo. Opcionalmente carga una banda de referencia y una regla de promedio.

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

    public var values: [Double]
    public var gradient: Gradient
    /// Rango de valores explícito; si no, se ajusta solo con un respiro arriba y abajo.
    public var range: ClosedRange<Double>?

    // MARK: Referencias opcionales, siempre en tinta y nunca en color de dato

    /// Banda de referencia opcional (p. ej. un rango típico p25–p75) dibujada tenue DETRÁS de la
    /// línea, en tono de tinta — nunca un color de dato, para que el valor de hoy se lea en contexto
    /// en vez de competir con el fondo.
    public var referenceBand: ClosedRange<Double>?
    public var bandColor: Color
    /// Regla discontinua de promedio, sobre el mismo eje que la línea.
    public var meanLine: Double?
    public var meanLineColor: Color

    // MARK: Qué se dibuja

    public var lineWidth: CGFloat
    public var showsArea: Bool
    public var showsHead: Bool
    public var showsScrub: Bool

    // MARK: Cómo se lee

    public var valueFormat: (Double) -> String
    /// Etiqueta secundaria de una muestra por índice (p. ej. una hora). Si falta, dice «sample N».
    public var indexLabel: ((Int) -> String)?

    public init(
        values: [Double],
        gradient: Gradient = StrandPalette.recoveryGradient,
        range: ClosedRange<Double>? = nil,
        referenceBand: ClosedRange<Double>? = nil,
        bandColor: Color = InstrumentoTheme.base.hairlineStrong,
        meanLine: Double? = nil,
        meanLineColor: Color = InstrumentoTheme.base.hairlineStrong,
        lineWidth: CGFloat = 2,
        showsArea: Bool = true,
        showsHead: Bool = true,
        showsScrub: Bool = true,
        valueFormat: @escaping (Double) -> String = { Sparkline.defaultValueString($0) },
        indexLabel: ((Int) -> String)? = nil
    ) {
        (self.values, self.gradient, self.range) = (values, gradient, range)
        (self.referenceBand, self.bandColor) = (referenceBand, bandColor)
        (self.meanLine, self.meanLineColor) = (meanLine, meanLineColor)
        (self.lineWidth, self.showsArea, self.showsHead, self.showsScrub) = (lineWidth, showsArea, showsHead, showsScrub)
        (self.valueFormat, self.indexLabel) = (valueFormat, indexLabel)
    }

    @State private var hoverX: CGFloat? = nil

    /// Plano (sin halo ni destello) en el lenguaje claro de «Instrumento diurno».
    @Environment(\.instrumentoFlat) private var flat

    /// Entero cuando el valor es redondo; si no, con un decimal.
    public static func defaultValueString(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    public var body: some View {
        GeometryReader { geo in
            let trazo = Trazo(valores: values, extremos: extremos, lienzo: geo.size)
            ZStack {
                referencias(trazo)
                curva(trazo)
                cabeza(trazo)
                lupa(trazo)
            }
            .animation(StrandMotion.fade, value: hoverX)
            .contentShape(Rectangle())
            .scrubGesture(enabled: showsScrub, hoverX: $hoverX)
        }
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
            if showsArea {
                trazo.area.fill(
                    LinearGradient(
                        colors: [tinta(en: MedidasSpark.lecturaDelLavado).opacity(MedidasSpark.veloDelLavado), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            trazo.linea.stroke(
                LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
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
        if showsScrub, let x = hoverX,
           let indice = ChartScrubMath.nearestIndex(toX: x, count: values.count, width: trazo.lienzo.width),
           indice < trazo.puntos.count {
            let punto = trazo.puntos[indice]
            let tono = tinta(en: values.count > 1 ? Double(indice) / Double(values.count - 1) : 1.0)
            CrosshairRule(x: punto.x, height: trazo.lienzo.height)
            HighlightDot(color: tono, diameter: max(MedidasSpark.puntoRaspadoMinimo, lineWidth * 3)).position(punto)
            PositionedTooltip(
                anchor: punto, container: trazo.lienzo,
                tooltip: ChartTooltip(value: valueFormat(values[indice]),
                                      label: indexLabel?(indice) ?? String(localized: "sample \(indice + 1)", bundle: .main),
                                      accent: tono)
            )
        }
    }

    // MARK: - Ayudas

    private func disco(_ tono: Color, lado: CGFloat) -> some View {
        Circle().fill(tono).frame(width: lado, height: lado)
    }

    /// El color de la rampa en una posición normalizada del trazo.
    private func tinta(en posicion: Double) -> Color {
        StrandPalette.sample(stops: gradient.stops, at: posicion)
    }

    /// El recorrido de valores contra el que se dibuja, con la banda de referencia plegada dentro
    /// para que nunca quede cortada.
    private var extremos: (piso: Double, techo: Double) {
        if let range { return (range.lowerBound, range.upperBound) }

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

        let total = valores.count
        let recorrido = Swift.max(extremos.techo - extremos.piso, 0.0001)
        puntos = valores.enumerated().map { orden, valor in
            let x = total > 1 ? CGFloat(orden) / CGFloat(total - 1) * lienzo.width : lienzo.width / 2
            let alto = (valor - extremos.piso) / recorrido
            return CGPoint(x: x, y: lienzo.height - CGFloat(alto) * lienzo.height)
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
        var camino = Path()
        guard let arranque = puntos.first else { return camino }
        camino.move(to: arranque)
        puntos.dropFirst().forEach { camino.addLine(to: $0) }
        return camino
    }

    /// La misma polilínea, cerrada contra el piso del lienzo, para el lavado de área.
    var area: Path {
        var camino = linea
        guard let arranque = puntos.first, let final = puntos.last else { return camino }
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

#Preview("Sparkline") {
    let pulso = pulsoDeMuestra()
    return VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("64").font(StrandFont.number(34)).foregroundStyle(InstrumentoTheme.base.ink)
            Text("bpm").font(StrandFont.caption).foregroundStyle(InstrumentoTheme.base.inkTertiary)
            Spacer()
            Sparkline(values: pulso, valueFormat: { "\(Int($0.rounded())) bpm" }, indexLabel: { "\($0)s ago" })
                .frame(width: 160, height: 44)
        }
        Sparkline(values: pulso, gradient: StrandPalette.strainGradient).frame(height: 60)
        Text("Hover a sparkline to read the sample under the cursor.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
    }
    .padding(24)
    .frame(width: 380, height: 220)
    .background(InstrumentoTheme.base.surface).preferredColorScheme(.light)
}
#endif
