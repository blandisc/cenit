import SwiftUI
import Charts
// MARK: - Gráfica de tendencia (§9.4)
//   La línea de una métrica a lo largo del tiempo, teñida con su propia rampa: recuperación, VFC,
//   FC en reposo, esfuerzo. Detrás puede llevar bandas de clasificación («Óptimo 7–9 h»); dentro,
//   una regla de referencia punteada y un punto marcado; encima, el raspado con cruz, punto y globo.

/// Una lectura de la serie: cuándo se midió y cuánto dio.
public struct TrendPoint: Identifiable, Sendable, Equatable {
    /// El instante que ancla la lectura sobre el eje del tiempo.
    public var date: Date
    /// El valor, en las unidades de quien lo pide.
    public var value: Double
    /// Identidad de pieza para SwiftUI: dos lecturas con el mismo dato siguen siendo dos puntos.
    public let id: UUID = .init()

    public init(date fecha: Date, value valor: Double) {
        self.date = fecha
        self.value = valor
    }
}

// MARK: - Classification bands

/// One classification band drawn behind a trend line (e.g. sleep "Optimal 7–9h"). Bounds form a
/// half-open interval `[lower, upper)`; `nil` on a side means open on that side, and BOTH `nil` means no
/// interval at all — such a band classifies NOTHING (an unbounded band must never silently swallow
/// every value a caller forgot to bound).
public struct TrendBand: Identifiable, Equatable {
    public let id = UUID()
    public var label: LocalizedStringKey
    public var lower: Double?
    public var upper: Double?
    public var isActive: Bool

    public init(label: LocalizedStringKey, lower: Double?, upper: Double?, isActive: Bool = false) {
        self.label = label
        self.lower = lower
        self.upper = upper
        self.isActive = isActive
    }

    /// Whether `value` falls in this band's half-open interval.
    public func contains(_ value: Double) -> Bool {
        guard lower != nil || upper != nil else { return false }
        return (lower == nil || value >= lower!) && (upper == nil || value < upper!)
    }
}

/// Pure band math (no SwiftUI), so it's unit-testable on its own.
public enum TrendBands {
    /// Index of the band containing `value`, or `nil` if none does.
    public static func index(containing value: Double, in bands: [TrendBand]) -> Int? {
        bands.firstIndex { $0.contains(value) }
    }

    /// The band the LAST value falls into, plus how many of `values` share that band.
    public static func activeBand(values: [Double], bands: [TrendBand]) -> (index: Int, count: Int)? {
        guard let last = values.last, let idx = index(containing: last, in: bands) else { return nil }
        let count = values.reduce(0) { $0 + (bands[idx].contains($1) ? 1 : 0) }
        return (idx, count)
    }

    /// Summarizes how `values` distribute across `bands`, and where `todayIndex` sits relative to the
    /// dominant one. Returns `nil` when there are no bands or no value lands in any of them.
    public static func summarize(values: [Double], bands: [TrendBand], todayIndex: Int?) -> BandTrendSummary? {
        guard !bands.isEmpty else { return nil }
        var counts = Array(repeating: 0, count: bands.count)
        var n = 0
        for value in values {
            if let i = index(containing: value, in: bands) { counts[i] += 1; n += 1 }
        }
        guard n > 0 else { return nil }

        // Ties break toward the LOWER band index, for a deterministic result.
        let ranked = counts.indices.sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
        let dominant = ranked[0]
        let second: Int? = (ranked.count > 1 && counts[ranked[1]] > 0) ? ranked[1] : nil
        let dominantCount = counts[dominant]
        let share = Double(dominantCount) / Double(n)

        let tier: BandTrendSummary.Tier
        if dominantCount == n {
            tier = .always
        } else if share >= 0.8 {
            tier = .almostAlways
        } else if share >= 0.5, second == nil || dominantCount > counts[second!] {
            tier = .mostly
        } else if let second, abs(dominant - second) == 1,
                  Double(dominantCount + counts[second]) / Double(n) >= 0.7 {
            tier = .alternating
        } else {
            tier = .scattered
        }

        let relation: BandTrendSummary.Relation?
        if let todayIndex {
            relation = todayIndex == dominant ? .same : (todayIndex < dominant ? .lower : .higher)
        } else {
            relation = nil
        }
        return BandTrendSummary(counts: counts, n: n, dominant: dominant, second: second,
                                 tier: tier, todayIndex: todayIndex, todayVsDominant: relation)
    }
}

/// A plain-language reading of how a windowed series sits across its bands, built by
/// `TrendBands.summarize`.
public struct BandTrendSummary: Equatable {
    public let counts: [Int]
    public let n: Int
    public let dominant: Int
    public let second: Int?
    public let tier: Tier
    public let todayIndex: Int?
    public let todayVsDominant: Relation?

    public init(counts: [Int], n: Int, dominant: Int, second: Int?, tier: Tier,
                todayIndex: Int?, todayVsDominant: Relation?) {
        self.counts = counts
        self.n = n
        self.dominant = dominant
        self.second = second
        self.tier = tier
        self.todayIndex = todayIndex
        self.todayVsDominant = todayVsDominant
    }

    /// How concentrated the window is in its dominant band.
    public enum Tier: Equatable {
        case always
        case almostAlways
        case mostly
        case alternating
        case scattered
    }

    /// Where today's reading sits relative to the dominant band, by band order.
    public enum Relation: Equatable { case same, lower, higher }
}

// MARK: - La gráfica

/// Las medidas del trazo, con nombre. Son geometría de dato —no fichas del sistema—: viven aquí
/// porque solo esta gráfica las usa, y con nombre para que un ajuste se haga en un lugar.
private enum MedidasTendencia {
    /// Grosor de la línea de valor.
    static let grosorDeLinea: CGFloat = 2.5
    /// Área del punto por muestra, y el techo de muestras a partir del cual se dejan de dibujar:
    /// arriba de eso los puntos son estorbo (y costo de trazado), no información.
    static let areaDelPunto: CGFloat = 18
    static let techoDePuntos = 60
    /// Área del punto marcado, sólido; y las dos del aro cuando se pide hueco.
    static let areaDelMarcado: CGFloat = 70
    static let areaDelAro: CGFloat = 92
    static let areaDelCentroDelAro: CGFloat = 34
    /// Opacidad del lavado de área bajo la curva.
    static let veloDelLavado = 0.28
    /// Canal derecho reservado cuando hay bandas rotuladas, y el respiro mínimo cuando no.
    static let canalDeRotulos: CGFloat = 64
    static let respiroMinimo: CGFloat = 8
    /// Relleno y filos de la banda activa.
    static let veloDeBandaActiva = 0.16
    static let filoDeBandaActiva = 0.5
    /// Alto en puntos que una banda inactiva necesita para ganarse su rótulo.
    static let altoMinimoParaRotular: CGFloat = 16
    /// Aire que el rótulo de banda deja contra el filo derecho del lienzo, y cuánto sube su base.
    static let sangriaDelRotulo: CGFloat = 6
    static let alzaDelRotulo: CGFloat = 8
    /// Opacidad de la retícula.
    static let veloDeReticula = 0.4
    /// Raya y grosor de la regla de referencia.
    static let rayaDeReferencia: [CGFloat] = [3, 3]
    static let grosorDeReferencia: CGFloat = 1
    /// Los cinco cortes del eje del tiempo, como fracción del tramo medido.
    static let cortesDelTiempo: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// Los dos quiebres que eligen la plantilla de fecha del eje: intradía y ~10 meses.
    static let tramoIntradia: TimeInterval = 36 * 3600
    static let tramoLargo: TimeInterval = 300 * 86_400
    /// Aire entre las piezas del muestrario del `#Preview`.
    static let aireDelMuestrario: CGFloat = 12
}

public struct TrendChart: View {

    // MARK: El dato y su escala
    //
    // Todo se fija al construir la gráfica —por eso son `let`— y nada de esto se muta después:
    // una gráfica distinta es otra gráfica, no la misma con otro valor encima.

    public let points: [TrendPoint]
    public let gradient: Gradient
    public let valueRange: ClosedRange<Double>

    // MARK: Qué se dibuja y qué tan alto

    public let showsArea: Bool
    public let height: CGFloat
    public let showsScrub: Bool

    // MARK: Cómo se lee

    public let valueFormat: (Double) -> String
    public let dateFormat: (Date) -> String
    public let axisLabelColor: Color
    public let gridLineColor: Color

    // MARK: Bandas de clasificación

    public let bands: [TrendBand]
    public let bandColor: Color
    public let yAxisValues: [Double]?
    /// Dibuja las bandas (relleno + filos) SIN su rótulo a la derecha, y suelta el canal que pedía.
    public let bandLabelsHidden: Bool

    // MARK: Señales sueltas sobre la curva

    /// Los puntos por debajo de este valor se pintan en `alertColor` y no con la rampa (p. ej. una
    /// noche de SpO₂ baja).
    public let alertThreshold: Double?
    public let alertColor: Color
    /// Regla horizontal punteada (p. ej. la FC en reposo de la noche bajo la curva de la noche).
    public let referenceLine: Double?
    public let referenceLineColor: Color
    /// Un punto enfatizado con un disco más grande (p. ej. el pico del día).
    public let markedPoint: TrendPoint?
    /// Dibuja `markedPoint` como aro hueco (centro relleno de `markedPointRingFill`) en vez de
    /// sólido, para que siga leyéndose como «hoy» aunque la banda resaltada sea OTRA.
    public let markedPointHollow: Bool
    public let markedPointRingFill: Color

    // MARK: Ajustes finos de marco y de voz

    /// Con esto y sin rótulos de banda a la derecha, el canal derecho se encoge a un respiro y la
    /// curva alcanza el filo.
    public let tightTrailing: Bool
    public let yTickCount: Int
    /// Se pega a la línea de valor del globo de raspado (p. ej. «prom 7 d»); nunca al eje Y.
    public let valueSuffix: String?
    public let accessibilityLabel: LocalizedStringKey?
    public let accessibilityValueText: String?

    public init(points puntos: [TrendPoint],
                gradient rampa: Gradient = CenitPalette.recoveryGradient,
                valueRange rango: ClosedRange<Double> = 0...100,
                showsArea conLavado: Bool = true,
                height alto: CGFloat = 220,
                showsScrub conRaspado: Bool = true,
                valueFormat formatoDeValor: @escaping (Double) -> String = { String(Int($0.rounded())) },
                dateFormat formatoDeFecha: @escaping (Date) -> String = { TrendChart.defaultDateString($0) },
                axisLabelColor tintaDeEje: Color = InstrumentoTheme.base.inkTertiary,
                gridLineColor tintaDeReticula: Color = InstrumentoTheme.base.hairline,
                bands bandas: [TrendBand] = [],
                bandColor tintaDeBanda: Color = .clear,
                yAxisValues cortesEnY: [Double]? = nil,
                alertThreshold umbralDeAlerta: Double? = nil,
                alertColor tintaDeAlerta: Color = .clear,
                referenceLine reglaDeReferencia: Double? = nil,
                referenceLineColor tintaDeLaRegla: Color = .clear,
                markedPoint puntoMarcado: TrendPoint? = nil,
                markedPointHollow marcadoHueco: Bool = false,
                markedPointRingFill rellenoDelAro: Color = .clear,
                bandLabelsHidden sinRotulosDeBanda: Bool = false,
                tightTrailing filoApretado: Bool = false,
                yTickCount cortesDeseadosEnY: Int = 4,
                valueSuffix sufijoDeValor: String? = nil,
                accessibilityLabel rotuloAccesible: LocalizedStringKey? = nil,
                accessibilityValueText valorAccesible: String? = nil) {
        // La serie llega en cualquier orden y la gráfica la asume cronológica: se ordena una vez, aquí.
        self.points = puntos.sorted(by: Self.enOrdenCronologico)
        (self.gradient, self.valueRange) = (rampa, rango)
        (self.showsArea, self.height, self.showsScrub) = (conLavado, alto, conRaspado)
        (self.valueFormat, self.dateFormat) = (formatoDeValor, formatoDeFecha)
        (self.axisLabelColor, self.gridLineColor) = (tintaDeEje, tintaDeReticula)
        (self.bands, self.bandColor, self.yAxisValues) = (bandas, tintaDeBanda, cortesEnY)
        self.bandLabelsHidden = sinRotulosDeBanda
        (self.alertThreshold, self.alertColor) = (umbralDeAlerta, tintaDeAlerta)
        (self.referenceLine, self.referenceLineColor) = (reglaDeReferencia, tintaDeLaRegla)
        (self.markedPoint, self.markedPointHollow) = (puntoMarcado, marcadoHueco)
        self.markedPointRingFill = rellenoDelAro
        (self.tightTrailing, self.yTickCount) = (filoApretado, cortesDeseadosEnY)
        self.valueSuffix = sufijoDeValor
        (self.accessibilityLabel, self.accessibilityValueText) = (rotuloAccesible, valorAccesible)
    }

    /// El criterio de orden de la serie, con nombre para que el `init` se lea de corrido.
    private static func enOrdenCronologico(_ izquierda: TrendPoint, _ derecha: TrendPoint) -> Bool {
        izquierda.date < derecha.date
    }

    // MARK: Estado del raspado

    /// Dónde está el dedo (o el cursor) sobre el lienzo. `nil` = nadie está raspando.
    @State private var dedoX: CGFloat?
    /// La muestra bajo el dedo, que es la que VoiceOver lee mientras se raspa.
    @State private var muestraBajoElDedo: TrendPoint?

    // MARK: Formato

    /// Un solo `DateFormatter` para todas las gráficas: construirlo es caro y el resultado no cambia.
    private static let formatoDiaCorto = Self.formateadorDeDia("EEE d MMM")

    /// Un `DateFormatter` con su plantilla ya puesta. Con nombre porque el eje arma el suyo aparte.
    private static func formateadorDeDia(_ plantilla: String) -> DateFormatter {
        let formateador = DateFormatter()
        formateador.dateFormat = plantilla
        return formateador
    }

    /// Formato por omisión del globo y del eje («EEE d MMM»).
    public static func defaultDateString(_ date: Date) -> String { formatoDiaCorto.string(from: date) }

    /// Lo que VoiceOver dice: el valor bajo el dedo si se está raspando, si no el último de la serie.
    private var resolvedAccessibilityValue: String {
        if let custom = accessibilityValueText { return custom }
        guard let reading = muestraBajoElDedo ?? points.last else { return "No data" }
        return "\(valorConSufijo(reading.value)), \(dateFormat(reading.date))"
    }

    /// El valor formateado, con el sufijo pegado cuando lo hay. Lo comparten VoiceOver y el globo,
    /// para que digan exactamente lo mismo.
    private func valorConSufijo(_ valor: Double) -> String {
        guard let valueSuffix else { return valueFormat(valor) }
        return "\(valueFormat(valor)) · \(valueSuffix)"
    }

    // MARK: Geometría

    /// Canal derecho de la escala X: ancho si hay una banda rotulada que llenar, el respiro mínimo
    /// si el llamador pidió que la curva alcance el filo, y el inset de casa en los demás casos.
    private var trailingInset: CGFloat {
        if !(bands.isEmpty || bandLabelsHidden) { return MedidasTendencia.canalDeRotulos }
        return tightTrailing ? MedidasTendencia.respiroMinimo : CenitMetrics.chartXTrailingInset
    }

    /// El valor llevado a 0...1 dentro del dominio, recortado a los extremos.
    private func fraccion(de valor: Double) -> Double {
        let piso = valueRange.lowerBound, techo = valueRange.upperBound
        guard techo > piso else { return 0 }
        return Swift.min(Swift.max((valor - piso) / (techo - piso), 0), 1)
    }

    /// La tinta que le toca a un valor dentro de la rampa de la métrica.
    private func tinta(de valor: Double) -> Color {
        CenitPalette.sample(stops: gradient.toStops(), at: fraccion(de: valor))
    }

    /// La rampa montada sobre el eje vertical: el trazo cambia de color según a qué altura va.
    private var rampaVertical: LinearGradient { .init(gradient: gradient, startPoint: .bottom, endPoint: .top) }

    /// El promedio de la serie, que decide con qué tinta se lava el área.
    private var promedioDeLaSerie: Double {
        let lecturas = points.map(\.value)
        guard !lecturas.isEmpty else { return valueRange.lowerBound }
        return lecturas.reduce(0, +) / Double(lecturas.count)
    }

    /// La muestra más cercana a una X del lienzo: se devuelve la X al eje del tiempo y se busca la
    /// lectura con la fecha menos lejana.
    private func muestraMasCercana(aX x: CGFloat, proxy: ChartProxy, lienzo: CGRect) -> TrendPoint? {
        guard !points.isEmpty, let instante: Date = proxy.value(atX: x - lienzo.minX) else { return nil }
        return points.min { izquierda, derecha in
            abs(izquierda.date.timeIntervalSince(instante)) < abs(derecha.date.timeIntervalSince(instante))
        }
    }

    // MARK: Las capas de la gráfica, de atrás hacia adelante

    @ChartContentBuilder
    private var capas: some ChartContent {
        capaDeReferencia
        capaDeLavado
        capaDeLinea
        capaDeMuestras
        capaDelPuntoMarcado
    }

    @ChartContentBuilder
    private var capaDeReferencia: some ChartContent {
        if let referenceLine {
            RuleMark(y: .value("Reference", referenceLine))
                .lineStyle(StrokeStyle(lineWidth: MedidasTendencia.grosorDeReferencia,
                                       dash: MedidasTendencia.rayaDeReferencia))
                .foregroundStyle(referenceLineColor)
        }
    }

    /// El lavado bajo la curva. Arranca en el PISO DEL DOMINIO y no en un cero implícito: con un
    /// dominio apretado (FC 64...145) el cero queda por debajo y el relleno se derramaría hasta el
    /// filo inferior del lienzo, justo detrás de las etiquetas del eje.
    @ChartContentBuilder
    private var capaDeLavado: some ChartContent {
        ForEach(showsArea ? points : []) { punto in
            AreaMark(x: .value("Date", punto.date),
                     yStart: .value("Floor", valueRange.lowerBound),
                     yEnd: .value("Value", punto.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(velo)
        }
    }

    /// El velo del lavado: la tinta del promedio arriba, desvaneciéndose a nada abajo.
    private var velo: LinearGradient {
        LinearGradient(colors: [tinta(de: promedioDeLaSerie).opacity(MedidasTendencia.veloDelLavado), .clear],
                       startPoint: .top, endPoint: .bottom)
    }

    /// La curva. `monotone` y no `catmullRom`: Catmull-Rom rebasa el dato en una serie que oscila
    /// apretado y hunde la curva por debajo del dominio.
    private var capaDeLinea: some ChartContent {
        ForEach(points) { punto in
            LineMark(x: .value("Date", punto.date), y: .value("Value", punto.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: MedidasTendencia.grosorDeLinea,
                                       lineCap: .round, lineJoin: .round))
                .foregroundStyle(rampaVertical)
        }
    }

    /// Un disco por muestra, solo en series cortas: una línea de varios meses los deja fuera.
    @ChartContentBuilder
    private var capaDeMuestras: some ChartContent {
        if points.count <= MedidasTendencia.techoDePuntos {
            ForEach(points) { punto in
                PointMark(x: .value("Date", punto.date), y: .value("Value", punto.value))
                    .symbolSize(MedidasTendencia.areaDelPunto)
                    .foregroundStyle(enAlerta(punto) ? alertColor : tinta(de: punto.value))
            }
        }
    }

    /// Si la muestra cae por debajo del umbral de alerta. Sin umbral, nada está en alerta.
    private func enAlerta(_ punto: TrendPoint) -> Bool {
        guard let alertThreshold else { return false }
        return punto.value < alertThreshold
    }

    /// El punto enfatizado: un disco sólido, o un aro (disco grande con el centro tapado) cuando
    /// hace falta que se lea como «este» aunque la banda resaltada sea otra.
    @ChartContentBuilder
    private var capaDelPuntoMarcado: some ChartContent {
        if let marked = markedPoint {
            let hue = tinta(de: marked.value)
            if markedPointHollow {
                disco(marked, area: MedidasTendencia.areaDelAro, relleno: hue)
                disco(marked, area: MedidasTendencia.areaDelCentroDelAro, relleno: markedPointRingFill)
            } else {
                disco(marked, area: MedidasTendencia.areaDelMarcado, relleno: hue)
            }
        }
    }

    private func disco(_ punto: TrendPoint, area: CGFloat, relleno: Color) -> some ChartContent {
        PointMark(x: .value("Date", punto.date), y: .value("Value", punto.value))
            .symbolSize(area)
            .foregroundStyle(relleno)
    }

    // MARK: El cuerpo

    public var body: some View { lienzo(alto: height) }

    private func lienzo(alto: CGFloat) -> some View {
        Chart { capas }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel ?? "Trend chart"))
            .accessibilityValue(Text(resolvedAccessibilityValue))
            // Cambiar la serie entera (p. ej. el selector de periodo) entra de golpe: nada de
            // remorfear punto por punto.
            .animation(.none, value: points)
            .chartYScale(domain: valueRange,
                         range: .plotDimension(startPadding: CenitMetrics.chartXLabelBand, endPadding: 0))
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: trailingInset))
            .chartXAxis(content: ejeDelTiempo)
            .chartYAxis(content: ejeDeValores)
            .chartBackground(content: fondoDeBandas)
            .chartOverlay(content: capaDeRaspado)
            .frame(height: alto)
    }

    // MARK: Los ejes

    /// Cinco cortes repartidos sobre el TRAMO REALMENTE MEDIDO: `.automatic` se pega a fronteras de
    /// calendario y puede amontonar los cinco de un solo lado en una ventana corta.
    @AxisContentBuilder
    private func ejeDelTiempo() -> some AxisContent {
        AxisMarks(values: xAxisTicks) { corte in
            AxisGridLine().foregroundStyle(gridLineColor.opacity(MedidasTendencia.veloDeReticula))
            AxisValueLabel(anchor: anclaDeCorte(corte.index, de: corte.count)) {
                if let fecha = corte.as(Date.self) { Text(xAxisLabel(fecha)) }
            }
            .font(CenitFont.footnote).foregroundStyle(axisLabelColor)
        }
    }

    /// Cortes explícitos cuando el llamador los da (los umbrales de banda sirven de pista); si no,
    /// los que Swift Charts elija alrededor de `yTickCount`.
    @AxisContentBuilder
    private func ejeDeValores() -> some AxisContent {
        if let yAxisValues {
            AxisMarks(position: .leading, values: yAxisValues) { corte in
                AxisGridLine().foregroundStyle(gridLineColor.opacity(MedidasTendencia.veloDeReticula))
                AxisValueLabel {
                    if let valor = corte.as(Double.self) { Text(valueFormat(valor)) }
                }
                .font(CenitFont.footnote).foregroundStyle(axisLabelColor)
            }
        } else {
            AxisMarks(position: .leading, values: .automatic(desiredCount: yTickCount)) { _ in
                AxisGridLine().foregroundStyle(gridLineColor.opacity(MedidasTendencia.veloDeReticula))
                AxisValueLabel().font(CenitFont.footnote).foregroundStyle(axisLabelColor)
            }
        }
    }

    /// Las cinco fechas de los cortes, a 0/25/50/75/100 % del tramo medido — ancladas al dato y no
    /// al calendario, para que las etiquetas cubran siempre todo el ancho.
    private var xAxisTicks: [Date] {
        guard let primera = points.first?.date, let ultima = points.last?.date else { return [] }
        let tramo = ultima.timeIntervalSince(primera)
        guard tramo > 0 else { return [primera] }
        return MedidasTendencia.cortesDelTiempo.map { primera.addingTimeInterval(tramo * $0) }
    }

    /// La primera etiqueta se alinea a la izquierda y la última a la derecha, para que ninguna se
    /// corte contra el filo; la retícula sigue cayendo exactamente sobre el corte.
    private func anclaDeCorte(_ indice: Int, de total: Int) -> UnitPoint {
        switch indice {
        case 0: return .topLeading
        case total - 1: return .topTrailing
        default: return .top
        }
    }

    /// La plantilla de fecha la elige el ancho de la ventana: intradía → hora; hasta ~10 meses →
    /// día y mes; más largo → mes y año.
    private func xAxisLabel(_ fecha: Date) -> String {
        let tramo = (points.last?.date.timeIntervalSince(points.first?.date ?? fecha)) ?? 0
        let formateador = TrendChart.formatoDeEje
        if tramo <= MedidasTendencia.tramoIntradia {
            formateador.setLocalizedDateFormatFromTemplate("ha")
        } else if tramo <= MedidasTendencia.tramoLargo {
            formateador.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            formateador.setLocalizedDateFormatFromTemplate("MMMyy")
        }
        return formateador.string(from: fecha)
    }

    private static let formatoDeEje = DateFormatter()

    // MARK: Las bandas, detrás de la curva

    private func fondoDeBandas(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let lienzo = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                ForEach(bands) { banda in bandLayer(banda, proxy: proxy, plot: lienzo) }
            }
        }
    }

    /// Dibuja una banda: la activa se lleva un velo suave y sus dos filos; el rótulo a la derecha lo
    /// gana cualquier banda con alto suficiente —y SIEMPRE la activa, aunque quede geométricamente
    /// delgada: la única banda que de verdad necesitas leer no puede ser la que se queda sin nombre.
    @ViewBuilder
    private func bandLayer(_ band: TrendBand, proxy: ChartProxy, plot: CGRect) -> some View {
        let top = min(band.upper ?? valueRange.upperBound, valueRange.upperBound)
        let bottom = max(band.lower ?? valueRange.lowerBound, valueRange.lowerBound)
        if let pTop = proxy.position(forY: top), let pBottom = proxy.position(forY: bottom) {
            let yTop = plot.minY + min(pTop, pBottom)
            let bandHeight = abs(pBottom - pTop)
            if band.isActive {
                franja(bandColor.opacity(MedidasTendencia.veloDeBandaActiva),
                       ancho: plot.width, alto: bandHeight, x: plot.minX, y: yTop)
                franja(bandColor.opacity(MedidasTendencia.filoDeBandaActiva),
                       ancho: plot.width, alto: 1, x: plot.minX, y: yTop)
                franja(bandColor.opacity(MedidasTendencia.filoDeBandaActiva),
                       ancho: plot.width, alto: 1, x: plot.minX, y: yTop + bandHeight - 1)
            }
            if !bandLabelsHidden, bandHeight >= MedidasTendencia.altoMinimoParaRotular || band.isActive {
                Text(band.label)
                    .font(CenitFont.footnote).fontWeight(band.isActive ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(band.isActive ? bandColor : axisLabelColor.opacity(0.8))
                    .frame(width: plot.width - MedidasTendencia.sangriaDelRotulo, alignment: .trailing)
                    .offset(x: plot.minX, y: yTop + bandHeight / 2 - MedidasTendencia.alzaDelRotulo)
            }
        }
    }

    /// Un rectángulo plano colocado en el lienzo: el relleno y los dos filos de la banda activa.
    private func franja(_ tinta: Color, ancho: CGFloat, alto: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Rectangle().fill(tinta).frame(width: ancho, height: alto).offset(x: x, y: y)
    }

    // MARK: El raspado, encima de la curva

    private func capaDeRaspado(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let lienzo = proxy.plotFrame.map { geo[$0] } ?? .zero
            let indiceBajoElDedo: Int? = (showsScrub ? dedoX : nil).flatMap { x in
                muestraMasCercana(aX: x, proxy: proxy, lienzo: lienzo).flatMap { points.firstIndex(of: $0) }
            }
            ZStack(alignment: .topLeading) {
                // Una capa transparente a todo lo ancho le da al gesto algo que tocar desde el primer
                // contacto: sin ella este ZStack mide 0×0 hasta que ya hay una muestra raspada.
                Color.clear.onChange(of: indiceBajoElDedo) { _, indice in seguir(indice) }
                if showsScrub, let x = dedoX,
                   let muestra = muestraMasCercana(aX: x, proxy: proxy, lienzo: lienzo),
                   let plotX = proxy.position(forX: muestra.date),
                   let plotY = proxy.position(forY: muestra.value) {
                    señales(de: muestra,
                            en: CGPoint(x: plotX + lienzo.minX, y: plotY + lienzo.minY),
                            dentro: geo.size)
                }
            }
            .animation(CenitMotion.fade, value: dedoX)
            .contentShape(.rect)
            .scrubGesture(enabled: showsScrub, hoverX: $dedoX)
        }
    }

    /// Cruz, disco y globo sobre la muestra que el dedo tiene encima.
    @ViewBuilder
    private func señales(de muestra: TrendPoint, en ancla: CGPoint, dentro contenedor: CGSize) -> some View {
        let color = tinta(de: muestra.value)
        CrosshairRule(x: ancla.x, height: contenedor.height)
        HighlightDot(color: color).position(ancla)
        PositionedTooltip(anchor: ancla, container: contenedor,
                          tooltip: ChartTooltip(value: valorConSufijo(muestra.value),
                                                label: dateFormat(muestra.date),
                                                accent: color))
    }

    /// Al cambiar de muestra: un golpecito háptico y la muestra que VoiceOver va a leer.
    private func seguir(_ indice: Int?) {
        guard let indice else {
            muestraBajoElDedo = nil
            return
        }
        ChartHaptics.datumChanged()
        muestraBajoElDedo = points[indice]
    }
}

// MARK: - El gesto de raspado, compartido por las gráficas del paquete
//
//   Vive aquí (interno al módulo, no fileprivate) para que Sparkline y compañía hereden EXACTAMENTE
//   la misma forma de raspar en vez de reimplementarla cada una.

/// Escribe la X del dedo sin animar. El cursor debe pegarse al dedo, no perseguirlo con un resorte.
private func fijarSinAnimar(_ destino: Binding<CGFloat?>, _ x: CGFloat?) {
    var transaccion = Transaction()
    transaccion.disablesAnimations = true
    withTransaction(transaccion) { destino.wrappedValue = x }
}

public extension View {
    /// Engancha el raspado: arrastre en iOS (sin distancia mínima, para que la cruz aparezca desde el
    /// primer contacto), cursor en macOS, y nada en watchOS —que nunca dibuja una gráfica raspable de
    /// este paquete, pero tiene que compilar igual. Las dos plataformas escriben el mismo `hoverX`
    /// que la capa de quien llama lee para pintar su cruz y su globo.
    ///
    /// En iOS es `highPriorityGesture` a propósito: estas gráficas viven dentro de un ScrollView y un
    /// `.gesture()` normal pierde el toque contra el arrastre vertical del padre.
    @ViewBuilder
    func scrubGesture(enabled: Bool, hoverX: Binding<CGFloat?>) -> some View {
        #if os(iOS)
        highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { arrastre in
                    if enabled { fijarSinAnimar(hoverX, arrastre.location.x) }
                }
                .onEnded { _ in
                    if enabled { fijarSinAnimar(hoverX, nil) }
                }
        )
        #elseif os(macOS)
        onContinuousHover(coordinateSpace: .local) { fase in
            guard enabled else { return }
            if case .active(let posicion) = fase {
                fijarSinAnimar(hoverX, posicion.x)
            } else {
                fijarSinAnimar(hoverX, nil)
            }
        }
        #else
        self
        #endif
    }
}

// MARK: - Puente de la rampa a sus paradas

fileprivate extension Gradient {
    /// Las paradas en orden, que es lo que el muestreador de `CenitPalette` sabe interpolar.
    /// Vive aquí y no en el módulo: solo esta gráfica necesita el puente.
    func toStops() -> [Gradient.Stop] { stops }
}

#if DEBUG
/// Una serie sintética con oscilación y ruido, para que la curva tenga forma de dato y no de seno.
private struct SerieDeMuestra {
    let piso: Double
    let vaiven: Double

    func dias(_ cuantos: Int) -> [TrendPoint] {
        let hoy = Date()
        return (0..<cuantos).map { paso in
            let atras = cuantos - 1 - paso
            let fecha = Calendar.current.date(byAdding: .day, value: -atras, to: hoy) ?? hoy
            let onda = vaiven * sin(Double(paso) / 3.0)
            let ruido = Double((paso * 17) % 9) - 4.0
            return TrendPoint(date: fecha, value: Swift.max(0, piso + onda + ruido))
        }
    }
}

/// La tarjeta del muestrario: un rótulo, una nota opcional y la gráfica sobre papel.
private struct TarjetaDeTendencia<Nota: View, Grafica: View>: View {
    let rotulo: String
    @ViewBuilder var nota: () -> Nota
    @ViewBuilder var grafica: () -> Grafica

    var body: some View {
        VStack(alignment: .leading, spacing: MedidasTendencia.aireDelMuestrario) {
            Text(rotulo).strandOverline()
            nota()
            grafica()
        }
        .padding(28).frame(width: 720, height: 340)
        .background(InstrumentoTheme.base.paper).preferredColorScheme(.light)
    }
}

#Preview("TrendChart · recuperación") {
    let serie = SerieDeMuestra(piso: 62, vaiven: 22).dias(30)
    return TarjetaDeTendencia(rotulo: "Recovery — 30 days") {
        Text(verbatim: "Raspa la línea: cruz, punto y globo con fecha y valor.")
            .font(CenitFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
    } grafica: {
        TrendChart(points: serie)
    }
}

#Preview("TrendChart · VFC") {
    let serie = SerieDeMuestra(piso: 58, vaiven: 14).dias(30)
    return TarjetaDeTendencia(rotulo: "HRV (ms) — 30 days") {
        EmptyView()
    } grafica: {
        TrendChart(points: serie, valueRange: 20...100, valueFormat: { "\(Int($0.rounded())) ms" })
    }
}
#endif
