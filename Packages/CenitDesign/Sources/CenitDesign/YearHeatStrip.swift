import SwiftUI
// MARK: - La franja de calor de un año
//   Un calendario al estilo GitHub: cada columna es una semana, cada fila un día de la semana
//   (empezando en lunes). Un día con lectura se tiñe con la rampa que le pase quien la usa; un día
//   dentro del rango pero sin lectura dibuja un cuadro hueco. Pasar el dedo/puntero saca un aro y
//   una tarjeta de lectura; y como `onContinuousHover` nunca dispara en pantalla táctil, un
//   manejador de toque opcional agrega la selección por dedo.

/// El puntaje de un día. `score == nil` significa que ese día no tiene lectura.
public struct RecoveryDay: Sendable, Identifiable {
    /// Identidad de pieza para SwiftUI, independiente de la fecha.
    public let id: UUID = .init()
    public var date: Date
    public var score: Double?

    public init(date: Date, score: Double?) { (self.date, self.score) = (date, score) }
}

/// Las medidas de la franja, con nombre. Geometría de dato: solo esta pieza las usa.
private enum MedidasFranja {
    /// Canal izquierdo donde van los rótulos de día de la semana.
    static let canal: CGFloat = 24
    /// Alto de la tira de rótulos de mes, arriba de la rejilla.
    static let rotuloDeMes: CGFloat = 10
    /// Filas de la rejilla: los siete días de la semana.
    static let filas = 7
    /// Radio y grosor del aro que marca la celda bajo el dedo, y cuánto crece sobre la celda.
    static let aroRadio: CGFloat = 3
    static let aroGrosor: CGFloat = 1.5
    static let aroCrecimiento: CGFloat = 3
    /// Lo mismo para el aro de selección por toque, un punto más grueso y más grande.
    static let seleccionGrosor: CGFloat = 2
    static let seleccionCrecimiento: CGFloat = 4
    /// Filete del cuadro hueco de un día sin lectura.
    static let hueco: CGFloat = 0.5
    /// Cuánto se atenúan las demás celdas mientras una está bajo el dedo.
    static let atenuadas = 0.78
    /// Piso, techo y refugio del tamaño de celda de la ventana móvil.
    static let celdaMinima: CGFloat = 8
    static let celdaMaxima: CGFloat = 22
    static let celdaSinAncho: CGFloat = 14
    /// Aire entre las piezas del muestrario del `#Preview`.
    static let aireDelMuestrario: CGFloat = 12
}

struct YearHeatStrip: View {

    // MARK: El dato

    var days: [RecoveryDay]

    // MARK: Geometría de la rejilla

    var cellSize: CGFloat
    var spacing: CGFloat
    var cellCornerRadius: CGFloat
    var showsMonthLabels: Bool
    var showsScrub: Bool

    // MARK: Cómo se pinta

    /// Tiñe la celda de un día a partir de su puntaje. Por omisión, la rampa de recuperación.
    var tint: (Double) -> Color
    var emptyFill: Color
    var emptyStroke: Color
    var labelColor: Color
    var selectionColor: Color

    // MARK: Cómo se lee

    var valueFormat: (Double) -> String
    /// La palabra de la métrica que se lee en el `.help`/VoiceOver («<fecha> · <palabra> 67»).
    var valueWord: String
    /// Si está puesto, tocar un día lo llama — la contraparte táctil del puntero.
    var onSelect: ((RecoveryDay) -> Void)?

    init(days lecturas: [RecoveryDay],
         cellSize lado: CGFloat = 12, spacing aire: CGFloat = 3,
         showsMonthLabels conMeses: Bool = true, showsScrub conRaspado: Bool = true,
         tint rampa: @escaping (Double) -> Color = { CenitPalette.recoveryColor($0) },
         emptyFill rellenoHueco: Color = InstrumentoTheme.base.hairline,
         emptyStroke filoHueco: Color = InstrumentoTheme.base.hairline.opacity(0.6),
         labelColor tintaDeRotulo: Color = InstrumentoTheme.base.inkTertiary,
         onSelect alSeleccionar: ((RecoveryDay) -> Void)? = nil,
         selectionColor tintaDeSeleccion: Color = InstrumentoTheme.base.hairlineStrong,
         cellCornerRadius cantoDeCelda: CGFloat = 2.5,
         valueFormat formatoDeValor: @escaping (Double) -> String = { "Recovery \(Int($0.rounded()))" },
         valueWord palabraDeValor: String = "recovery") {
        // Ordenados por fecha desde la entrada: toda la construcción de semanas de abajo asume que
        // los días llegan en orden, y arreglarlo aquí es una sola vez en vez de una por pasada.
        self.days = lecturas.sorted(by: Self.enOrdenCronologico)
        (cellSize, spacing, cellCornerRadius) = (lado, aire, cantoDeCelda)
        (showsMonthLabels, showsScrub) = (conMeses, conRaspado)
        (tint, emptyFill, emptyStroke) = (rampa, rellenoHueco, filoHueco)
        (labelColor, selectionColor) = (tintaDeRotulo, tintaDeSeleccion)
        (valueFormat, valueWord, onSelect) = (formatoDeValor, palabraDeValor, alSeleccionar)
    }

    /// El criterio de orden de los días, con nombre para que el `init` se lea de corrido.
    private static func enOrdenCronologico(_ izquierda: RecoveryDay, _ derecha: RecoveryDay) -> Bool {
        izquierda.date < derecha.date
    }

    // MARK: - La ventana móvil de 90 días

    /// Cuántas columnas puede llegar a ocupar una ventana móvil de 90 días (12.86 semanas → 13 o 14
    /// según el día en que arranque). Se fija en el tope para que TODO calendario de 90 días se
    /// dibuje con la MISMA celda, sin importar en qué día de la semana empiece su ventana.
    static let rollingWindowColumns = 14

    /// El tamaño de celda que llena `width` con una rejilla fija de 14 columnas. Es función del
    /// ancho y de nada más, así que dos calendarios de 90 días en pantalla siempre coinciden, un día
    /// y el siguiente. Con ancho 0 cae en 14 pt.
    static func rollingCellSize(width: CGFloat, spacing: CGFloat = 4, gutter: CGFloat = 24) -> CGFloat {
        guard width > 0 else { return MedidasFranja.celdaSinAncho }
        let columnas = CGFloat(rollingWindowColumns)
        let crudo = (width - gutter - spacing - (columnas - 1) * spacing) / columnas
        return max(MedidasFranja.celdaMinima, min(MedidasFranja.celdaMaxima, crudo))
    }

    // MARK: - Estado vivo

    @State private var celdaBajoElDedo: Rejilla.Coordenada? = nil
    @State private var seleccionada: UUID? = nil

    // MARK: - El dibujo

    var body: some View {
        let semanas = Rejilla.semanas(de: days)
        let cuadricula = Cuadricula(celda: cellSize, aire: spacing,
                                    conRotulosDeMes: showsMonthLabels, columnas: semanas.count)
        return contenido(semanas, cuadricula)
            .frame(width: cuadricula.ancho, height: cuadricula.alto, alignment: .topLeading)
            .overlay(aroYTarjeta(semanas, cuadricula))
            .contentShape(.rect)
            #if os(iOS)
            .onContinuousHover(coordinateSpace: .local) { fase in
                guard showsScrub else { return }
                switch fase {
                case .active(let punto): celdaBajoElDedo = cuadricula.coordenada(en: punto)
                case .ended: celdaBajoElDedo = nil
                }
            }
            #endif
    }

    /// La tira de meses arriba, el canal de días de la semana a la izquierda, y las columnas.
    private func contenido(_ semanas: [Rejilla.Semana], _ cuadricula: Cuadricula) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if showsMonthLabels { tiraDeMeses(semanas, cuadricula) }
            rejilla(semanas)
        }
    }

    /// El canal de días a la izquierda y, a su derecha, una columna por semana.
    private func rejilla(_ semanas: [Rejilla.Semana]) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            canalDeDias
            ForEach(Array(semanas.enumerated()), id: \.element.id) { orden, semana in
                columna(semana, en: orden)
            }
        }
    }

    /// Una semana, de lunes arriba a domingo abajo.
    private func columna(_ semana: Rejilla.Semana, en orden: Int) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<MedidasFranja.filas, id: \.self) { fila in
                celda(semana.dias[fila],
                      resaltada: celdaBajoElDedo == Rejilla.Coordenada(columna: orden, fila: fila))
            }
        }
    }

    /// Un rótulo de mes sobre la primera semana de cada mes; el resto va en blanco.
    private func tiraDeMeses(_ semanas: [Rejilla.Semana], _ cuadricula: Cuadricula) -> some View {
        HStack(spacing: spacing) {
            Color.clear.frame(width: cuadricula.origenX - spacing, height: MedidasFranja.rotuloDeMes)
            ForEach(semanas) { semana in
                rotulo(semana.rotuloDeMes ?? "").frame(width: cellSize, alignment: .leading)
            }
        }
    }

    /// La voz de los rótulos de la franja: meses arriba, días a la izquierda, la misma ficha.
    private func rotulo(_ texto: String) -> some View {
        Text(texto).font(CenitFont.footnote).foregroundStyle(labelColor)
    }

    /// El canal izquierdo: solo lun/mié/vie/dom llevan rótulo, para que no se apelmace.
    private var canalDeDias: some View {
        VStack(alignment: .trailing, spacing: spacing) {
            ForEach(Array(Rejilla.rotulosDeFila.enumerated()), id: \.offset) { _, dia in
                rotulo(dia).frame(width: MedidasFranja.canal, height: cellSize, alignment: .trailing)
            }
        }
    }

    /// Una celda: teñida si hay lectura, hueca si el día está en rango pero sin dato, transparente
    /// si la columna todavía no llega a ese día.
    @ViewBuilder
    private func celda(_ dia: RecoveryDay?, resaltada: Bool) -> some View {
        let canto = RoundedRectangle(cornerRadius: cellCornerRadius)
        cuerpoDeCelda(dia, canto: canto, resaltada: resaltada)
            .overlay { if dia.map({ $0.id == seleccionada }) ?? false { aroDeSeleccion } }
            .modifier(TappableCell(
                enabled: onSelect != nil && dia != nil,
                label: dia.map(vozDeVoiceOver) ?? Text(""),
                action: { if let dia { seleccionada = dia.id; onSelect?(dia) } }
            ))
    }

    @ViewBuilder private func cuerpoDeCelda(_ dia: RecoveryDay?, canto: RoundedRectangle,
                                            resaltada: Bool) -> some View {
        if let dia, let puntaje = dia.score {
            canto.fill(tint(puntaje)).enCelda(cellSize)
                .opacity(resaltada || celdaBajoElDedo == nil ? 1.0 : MedidasFranja.atenuadas)
                .help(vozDeAyuda(dia, puntaje: puntaje))
        } else if dia != nil {
            canto.fill(emptyFill).overlay(canto.stroke(emptyStroke, lineWidth: MedidasFranja.hueco))
                .enCelda(cellSize)
        } else {
            canto.fill(Color.clear).enCelda(cellSize)
        }
    }

    /// Lo que dice el `.help` (y VoiceOver de escritorio) de un día con lectura.
    private func vozDeAyuda(_ dia: RecoveryDay, puntaje: Double) -> String {
        "\(CalendarFormatters.day.string(from: dia.date)) · \(valueWord) \(Int(puntaje.rounded()))"
    }

    private var aroDeSeleccion: some View {
        RoundedRectangle(cornerRadius: MedidasFranja.aroRadio, style: .continuous)
            .stroke(selectionColor, lineWidth: MedidasFranja.seleccionGrosor)
            .frame(width: cellSize + MedidasFranja.seleccionCrecimiento,
                   height: cellSize + MedidasFranja.seleccionCrecimiento)
    }

    /// El aro y la tarjeta de lectura de la celda bajo el dedo, en una capa encima de la rejilla.
    /// No recibe toques: es información sobre la rejilla, no otra cosa que tocar.
    @ViewBuilder private func aroYTarjeta(_ semanas: [Rejilla.Semana],
                                          _ cuadricula: Cuadricula) -> some View {
        if showsScrub, let donde = celdaBajoElDedo, donde.columna < semanas.count,
           let dia = semanas[donde.columna].dias[donde.fila], let puntaje = dia.score {
            let centro = cuadricula.centro(de: donde)
            ZStack(alignment: .topLeading) {
                aroDeRaspado.position(centro)
                PositionedTooltip(anchor: centro,
                                  container: CGSize(width: cuadricula.ancho, height: cuadricula.alto),
                                  tooltip: globo(dia, puntaje: puntaje))
            }
            .animation(CenitMotion.fade, value: donde)
            .allowsHitTesting(false)
        }
    }

    /// El aro que enmarca la celda bajo el dedo, un poco más grande que ella.
    private var aroDeRaspado: some View {
        RoundedRectangle(cornerRadius: MedidasFranja.aroRadio, style: .continuous)
            .stroke(InstrumentoTheme.base.hairlineStrong, lineWidth: MedidasFranja.aroGrosor)
            .frame(width: cellSize + MedidasFranja.aroCrecimiento,
                   height: cellSize + MedidasFranja.aroCrecimiento)
    }

    /// Lo que dice la tarjeta: el valor formateado y, abajo, la fecha con el estado en palabras.
    private func globo(_ dia: RecoveryDay, puntaje: Double) -> ChartTooltip {
        let fecha = CalendarFormatters.day.string(from: dia.date)
        return ChartTooltip(value: valueFormat(puntaje),
                            label: "\(fecha) · \(CenitPalette.recoveryState(puntaje))",
                            accent: tint(puntaje))
    }

    /// Lo que VoiceOver lee de una celda seleccionable.
    private func vozDeVoiceOver(_ dia: RecoveryDay) -> Text {
        let fecha = CalendarFormatters.day.string(from: dia.date)
        guard let puntaje = dia.score else { return Text("\(fecha) · no reading") }
        return Text("\(fecha) · \(valueWord) \(Int(puntaje.rounded()))")
    }
}

// MARK: - Calendario: de una lista de días a columnas de semana
//
// Aparte de la vista a propósito: repartir días en semanas que empiezan en lunes es aritmética de
// calendario, no dibujo, y así se lee (y se corrige) sin abrir el `body`.
private enum Rejilla {

    /// Dónde está una celda dentro de la rejilla.
    struct Coordenada: Equatable {
        let columna, fila: Int
    }

    /// Una columna: siete huecos indexados por fila lunes-primero, y el rótulo de mes si esa semana
    /// estrena mes.
    struct Semana: Identifiable {
        let id = UUID()
        var dias: [RecoveryDay?]
        var rotuloDeMes: String?
    }

    /// Lunes primero, siempre — el calendario del sistema podría empezar en domingo.
    static var calendario: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    /// Los rótulos del canal: solo lun/mié/vie/dom. `shortWeekdaySymbols` viene siempre indexado
    /// desde el domingo sin importar el idioma, así que se toman los índices [1,3,5,0] para las
    /// filas lunes-primero.
    static var rotulosDeFila: [String] {
        let simbolos = Calendar.current.shortWeekdaySymbols
        return [simbolos[1], "", simbolos[3], "", simbolos[5], "", simbolos[0]]
    }

    /// La fila (0 = lunes … 6 = domingo) que le toca a una fecha.
    static func fila(de fecha: Date) -> Int {
        let diaDeLaSemana = calendario.component(.weekday, from: fecha) // 1=dom … 7=sáb
        return (diaDeLaSemana + 5) % 7
    }

    /// Reparte los días —ya ordenados— en columnas de semana. Cada lunes abre columna nueva; la
    /// primera puede empezar a media semana, con los huecos previos vacíos.
    static func semanas(de dias: [RecoveryDay]) -> [Semana] {
        guard let primera = dias.first?.date else { return [] }
        var columnas: [Semana] = []
        var enCurso = vacia()
        var mesVisto = -1
        var llenos = fila(de: primera)

        for dia in dias {
            let hueco = fila(de: dia.date)
            if hueco == 0 && llenos > 0 {
                columnas.append(enCurso)
                enCurso = vacia()
                llenos = 0
            }
            enCurso.dias[hueco] = dia
            let mes = calendario.component(.month, from: dia.date)
            if mes != mesVisto {
                enCurso.rotuloDeMes = CalendarFormatters.month.string(from: dia.date)
                mesVisto = mes
            }
            llenos += 1
        }
        if llenos > 0 { columnas.append(enCurso) }
        return columnas
    }

    private static func vacia() -> Semana {
        Semana(dias: Array(repeating: nil, count: MedidasFranja.filas), rotuloDeMes: nil)
    }
}

// MARK: - Geometría de la rejilla
//
// El paso entre celdas, el origen del área dibujada, y las dos traducciones que la vista necesita:
// de un punto a una coordenada (para el puntero) y de una coordenada a un centro (para el aro).
private struct Cuadricula {
    let celda, aire: CGFloat
    let origenX, origenY: CGFloat
    let ancho, alto: CGFloat
    private let columnas: Int

    init(celda: CGFloat, aire: CGFloat, conRotulosDeMes: Bool, columnas: Int) {
        (self.celda, self.aire, self.columnas) = (celda, aire, columnas)
        origenX = MedidasFranja.canal + aire
        origenY = conRotulosDeMes ? MedidasFranja.rotuloDeMes + aire : 0
        ancho = origenX + CGFloat(columnas) * (celda + aire) - aire
        alto = origenY + CGFloat(MedidasFranja.filas) * (celda + aire) - aire
    }

    private var paso: CGFloat { celda + aire }

    /// La coordenada bajo un punto, o `nil` si el punto cayó fuera de la rejilla o en el aire entre
    /// celdas — un acierto en la ranura no cuenta como acierto en la celda.
    func coordenada(en punto: CGPoint) -> Rejilla.Coordenada? {
        let x = punto.x - origenX, y = punto.y - origenY
        guard x >= 0, y >= 0 else { return nil }
        let columna = Int(x / paso), fila = Int(y / paso)
        guard columna >= 0, columna < columnas, fila >= 0, fila < MedidasFranja.filas else { return nil }
        guard x - CGFloat(columna) * paso <= celda, y - CGFloat(fila) * paso <= celda else { return nil }
        return Rejilla.Coordenada(columna: columna, fila: fila)
    }

    /// El centro de una celda, en el mismo espacio en que se dibuja la rejilla.
    func centro(de donde: Rejilla.Coordenada) -> CGPoint {
        CGPoint(x: origenX + CGFloat(donde.columna) * paso + celda / 2,
                y: origenY + CGFloat(donde.fila) * paso + celda / 2)
    }
}

/// Agrega selección por toque y un botón de VoiceOver SOLO cuando `enabled` — las celdas de quien
/// únicamente usa el puntero quedan exactamente igual, sin blanco de toque ni elemento extra.
private struct TappableCell: ViewModifier {
    let enabled: Bool
    let label: Text
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(.rect)
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

private extension View {
    /// Fija el cuadro de una celda: el mismo lado en alto y ancho, en un solo lugar.
    func enCelda(_ lado: CGFloat) -> some View { frame(width: lado, height: lado) }
}

private enum CalendarFormatters {
    static let month: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

#if DEBUG
/// Un año sintético con huecos cada 23 días, para que se vea tanto el día teñido como el hueco.
private func anoDeMuestra(_ total: Int = 365) -> [RecoveryDay] {
    let hoy = Date()
    return (0..<total).map { orden -> RecoveryDay in
        let fecha = Calendar.current.date(byAdding: .day, value: -(total - 1 - orden), to: hoy) ?? hoy
        let curva: Double = 28.0 * sin(Double(orden) / 11.0)
        let temblor = Double((orden * 31) % 17) - 8.0
        let lectura = Swift.min(Swift.max(55.0 + curva + temblor, 2.0), 99.0)
        return RecoveryDay(date: fecha, score: orden.isMultiple(of: 23) ? nil : lectura)
    }
}

#Preview("YearHeatStrip · un año") {
    VStack(alignment: .leading, spacing: MedidasFranja.aireDelMuestrario) {
        Text(verbatim: "Recuperación — el último año").strandOverline()
        Text(verbatim: "Pasa el cursor por un día: aro, fecha, puntaje y estado en palabras.")
            .font(CenitFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
        YearHeatStrip(days: anoDeMuestra())
    }
    .padding(28).frame(width: 900, height: 240)
    .background(InstrumentoTheme.base.paper).preferredColorScheme(.light)
}
#endif
