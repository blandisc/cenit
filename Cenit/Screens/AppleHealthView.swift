import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - Apple Health · dossier por fuente (Liquid Glass · El Eje)
//
// Lector de UNA fuente: enseña, sin adornos, todo lo que «apple-health» dejó en la base local de
// este iPhone. No sincroniza, no escribe y no sale a ningún lado — la puerta de entrada es
// «Ver datos importados ›» en Fuentes de datos.
//
// Tres capas, deliberadamente separadas:
//   1. `AppleHealthSpan`     — el vocabulario de ventanas (W · M · 3M · 6M · 1Y · ALL).
//   2. `AppleHealthDossier`  — el recorte, resuelto UNA vez por carga y por toque del selector.
//      Ahí vive toda la aritmética de ventanas; el render solo consulta.
//   3. Las vistas            — encabezado, tarjetas de estado, rejilla de tiles y grupos de gráfica.
//
// El color y el nombre de cada métrica salen del puente único de claves de ingesta
// (`MetricIdentity.identity(forIngestKey:)` + `MetricCatalog.descriptor(forIngestKey:)`), nunca de
// rótulos inventados aquí.

// MARK: - Ventanas

/// Las seis ventanas del selector. El orden de `allCases` es a la vez el que ve el usuario
/// (de la más corta a «todo») y el orden en que se busca una ventana mayor cuando la serie es rala.
private enum AppleHealthSpan: CaseIterable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case halfYear
    case fullYear
    case everything

    /// Rótulo del segmento en el selector.
    var pill: String {
        switch self {
        case .sevenDays:  return String(localized: "W")
        case .thirtyDays: return String(localized: "M")
        case .ninetyDays: return String(localized: "3M")
        case .halfYear:   return String(localized: "6M")
        case .fullYear:   return String(localized: "1Y")
        case .everything: return String(localized: "ALL")
        }
    }

    /// Cuántos días hacia atrás cubre; `nil` = sin tope.
    var trailingDays: Int? {
        switch self {
        case .sevenDays:  return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .halfYear:   return 180
        case .fullYear:   return 365
        case .everything: return nil
        }
    }

    /// Sello en versalitas que acompaña al selector y a cada grupo de gráficas.
    var stamp: String {
        switch self {
        case .sevenDays:  return String(localized: "7 DAYS")
        case .thirtyDays: return String(localized: "30 DAYS")
        case .ninetyDays: return String(localized: "90 DAYS")
        case .halfYear:   return String(localized: "180 DAYS")
        case .fullYear:   return String(localized: "365 DAYS")
        case .everything: return String(localized: "ALL TIME")
        }
    }

    /// La ventana dicha en prosa, para meterla dentro de una frase.
    var phrase: String {
        switch self {
        case .sevenDays:  return String(localized: "week")
        case .thirtyDays: return String(localized: "month")
        case .ninetyDays: return String(localized: "3 months")
        case .halfYear:   return String(localized: "6 months")
        case .fullYear:   return String(localized: "year")
        case .everything: return String(localized: "all history")
        }
    }

    /// Esta ventana seguida de todas las mayores — el orden de búsqueda cuando la elegida sale vacía.
    var thisAndWider: [AppleHealthSpan] {
        let todas = Self.allCases
        guard let desde = todas.firstIndex(of: self) else { return [.everything] }
        return Array(todas[desde...])
    }
}

// MARK: - Dossier resuelto

/// Una serie ya recortada: qué ventana acabó mostrándose (puede ser mayor que la pedida, si los
/// puntos son ralos) y los puntos que caen dentro, ascendentes por día.
private struct AppleHealthSeriesWindow {
    let span: AppleHealthSpan
    let points: [(day: String, value: Double)]
}

/// La fotografía completa que pinta la pantalla, ya recortada a la ventana pedida.
///
/// Se arma dos veces: al terminar de leer la base y en cada toque del selector. Nunca dentro del
/// render — el `body` se re-evalúa por hover, por animación y por cada tic del pulso, y volver a
/// rebanar años de historia en cada pasada era el defecto que este tipo existe para cerrar.
private struct AppleHealthDossier {
    /// Las series que este dossier le pide a la fuente.
    static let keys = [
        "steps", "active_kcal", "vo2max", "resting_hr", "hrv", "spo2", "resp_rate",
        "skin_temp", "asleep_min", "weight", "body_fat", "lean_mass", "bmi",
    ]

    /// La ventana que el usuario eligió (no siempre la que cada serie logra mostrar).
    let requested: AppleHealthSpan
    private let windows: [String: AppleHealthSeriesWindow]
    /// Filas diarias dentro de la ventana — alimentan el subtítulo y la leyenda.
    let days: [AppleDaily]
    /// Entrenamientos dentro de la ventana.
    let workouts: Int
    /// `false` solo en el caso raro de tener entrenamientos sin ninguna fila diaria contra la cual
    /// recortar: entonces `workouts` es el total histórico y la tarjeta lo dice así.
    let workoutsFollowSpan: Bool

    static func empty(_ span: AppleHealthSpan) -> AppleHealthDossier {
        AppleHealthDossier(requested: span, windows: [:], days: [], workouts: 0, workoutsFollowSpan: true)
    }

    func window(_ key: String) -> AppleHealthSeriesWindow {
        windows[key] ?? AppleHealthSeriesWindow(span: requested, points: [])
    }

    /// Cierto si alguna serie tuvo que salirse de la ventana pedida para encontrar puntos.
    var holdsWidenedSeries: Bool {
        windows.values.contains { !$0.points.isEmpty && $0.span != requested }
    }

    // MARK: Armado

    static func assemble(span: AppleHealthSpan,
                         series: [String: [(day: String, value: Double)]],
                         days: [AppleDaily],
                         workouts: [WorkoutRow]) -> AppleHealthDossier {
        var resolved: [String: AppleHealthSeriesWindow] = [:]
        resolved.reserveCapacity(keys.count)
        for key in keys {
            resolved[key] = resolve(series[key] ?? [], within: span)
        }

        let floor = cutoff(newestDay: days.last?.day, span: span)
        let visibleDays: [AppleDaily]
        if span.trailingDays == nil {
            visibleDays = days
        } else if let floor {
            visibleDays = days.filter { row in onOrAfter(row.day, floor) }
        } else {
            visibleDays = []
        }

        let counted: Int
        let follows: Bool
        if span.trailingDays == nil {
            counted = workouts.count
            follows = true
        } else if let floor {
            counted = workouts.filter { Date(timeIntervalSince1970: TimeInterval($0.startTs)) >= floor }.count
            follows = true
        } else {
            counted = workouts.count
            follows = false
        }

        return AppleHealthDossier(requested: span, windows: resolved, days: visibleDays,
                                  workouts: counted, workoutsFollowSpan: follows)
    }

    /// La ventana pedida si tiene al menos un punto; si no, la menor de las mayores que sí lo tenga.
    /// Una serie sin historia alguna se queda en la pedida (vacía) para no fingir un ensanchamiento.
    private static func resolve(_ all: [(day: String, value: Double)],
                                within span: AppleHealthSpan) -> AppleHealthSeriesWindow {
        guard !all.isEmpty else { return AppleHealthSeriesWindow(span: span, points: []) }
        for candidate in span.thisAndWider {
            let recorte = trim(all, to: candidate)
            if !recorte.isEmpty { return AppleHealthSeriesWindow(span: candidate, points: recorte) }
        }
        return AppleHealthSeriesWindow(span: .everything, points: all)
    }

    private static func trim(_ rows: [(day: String, value: Double)],
                             to span: AppleHealthSpan) -> [(day: String, value: Double)] {
        guard span.trailingDays != nil else { return rows }
        guard let floor = cutoff(newestDay: rows.last?.day, span: span) else { return [] }
        return rows.filter { row in onOrAfter(row.day, floor) }
    }

    /// El borde inferior de la ventana, anclado al ÚLTIMO día con dato — no a «ahora»: una historia
    /// importada hace un mes seguiría teniendo algo que enseñar en la pestaña de la semana.
    private static func cutoff(newestDay: String?, span: AppleHealthSpan) -> Date? {
        guard let count = span.trailingDays else { return nil }
        guard let newestDay, let newest = Repository.parseDayKey(newestDay) else { return nil }
        return newest.addingTimeInterval(-Double(count - 1) * 86_400)
    }

    private static func onOrAfter(_ day: String, _ floor: Date) -> Bool {
        guard let parsed = Repository.parseDayKey(day) else { return false }
        return parsed >= floor
    }
}

// MARK: - Recetas de bloque

/// Un tile de la rejilla: de qué serie sale, con qué unidad se rotula y cómo se resume.
private struct AppleHealthTileRecipe {
    enum Summary { case newest, average }

    let key: String
    var unit: String = ""
    var summary: Summary = .newest
    let format: (Double) -> String
}

/// Una tarjeta de gráfica: su serie, el dominio con el que se dibuja cuando no hay datos que lo
/// definan, y el formato de sus cifras.
private struct AppleHealthChartRecipe {
    let key: String
    let fallbackDomain: ClosedRange<Double>
    let format: (Double) -> String
}

// MARK: - Pantalla

struct AppleHealthView: View {
    @EnvironmentObject private var repo: Repository

    /// Imperial/métrico (D#103): solo peso y masa magra (guardados en kg) se re-rotulan; el resto de
    /// las métricas de Apple Health no dependen del sistema. Es preferencia de presentación.
    @AppStorage(UnitPrefs.systemKey) private var storedUnitSystem = UnitSystem.metric.rawValue

    /// Datos inyectados para el canvas; con ellos la lectura del store se salta por completo
    /// (un preview no puede sembrar la base). En producción siempre es `nil`.
    private let seed: Seed?

    init() { self.seed = nil }
    fileprivate init(seed: Seed) { self.seed = seed }

    @State private var finishedReading = false
    @State private var dailyRows: [AppleDaily] = []
    /// Se guardan las filas crudas, no un conteo: así el tile de entrenamientos se recorta a la
    /// ventana activa igual que todos los demás.
    @State private var loggedWorkouts: [WorkoutRow] = []
    /// Historia completa por clave, ascendente por día. El recorte lo hace el dossier.
    @State private var rawSeries: [String: [(day: String, value: Double)]] = [:]
    @State private var span: AppleHealthSpan = .ninetyDays
    @State private var dossier = AppleHealthDossier.empty(.ninetyDays)

    /// Alto del cuerpo de cada gráfica. Tiene que empatar con el alto interno del núcleo Liquid
    /// (`LiquidChartAlto.explorador`, 144, interno al paquete) para que los pozos que esta pantalla
    /// compone a mano queden a la misma línea que las gráficas reales.
    private static let plotHeight: CGFloat = 144

    /// Tramo del subtítulo («12 ago 2026»), en el idioma del app — no clavado a `en_US_POSIX`.
    private static let spanStamp: DateFormatter = {
        let formateador = DateFormatter()
        formateador.locale = .current
        formateador.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return formateador
    }()

    /// Fecha corta («12 ago») para pies de tile y ejes de gráfica.
    private static let dayStamp: DateFormatter = {
        let formateador = DateFormatter()
        formateador.locale = .current
        formateador.setLocalizedDateFormatFromTemplate("dMMM")
        return formateador
    }()

    // MARK: Cuerpo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                SourceHeader(subtitle: headerSubtitle)
                switch phase {
                case .reading:
                    ReadingCard()
                case .nothingImported:
                    NothingImportedCard()
                case .dossier:
                    SpanBar(selection: spanSelection,
                            legend: windowLegend,
                            legendNeedsAttention: dossier.holdsWidenedSeries,
                            stamp: span.stamp)
                    tileGrid
                    vitalsGroup
                    activityGroup
                    bodyGroup
                    sleepGroup
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .task { await read() }
        .onChange(of: span) { rebuild() }
    }

    /// En qué de los tres estados está la pantalla.
    private enum Phase { case reading, nothingImported, dossier }

    private var phase: Phase {
        guard finishedReading else { return .reading }
        return holdsAnything ? .dossier : .nothingImported
    }

    /// Cierto cuando la fuente dejó ALGO: una fila diaria o una serie con puntos.
    private var holdsAnything: Bool {
        if !dailyRows.isEmpty { return true }
        return rawSeries.values.contains { !$0.isEmpty }
    }

    // MARK: Lectura

    private func read() async {
        if let seed {
            dailyRows = seed.days.sorted { $0.day < $1.day }
            loggedWorkouts = seed.workouts
            rawSeries = seed.series
            rebuild()
            finishedReading = true
            return
        }

        #if DEBUG
        await stallForScreenshotHarness()
        #endif

        async let pendingDays = repo.appleDailyRows(respectingMode: false)   // FER-485: diagnóstico, sin filtrar por modo
        async let pendingWorkouts = repo.workoutRows(respectingMode: false)

        // Una tarea por clave: en serie eran N+1 viajes al store (mismo patrón que Comparar,
        // Explorador e Insights).
        let fetched = await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for key in AppleHealthDossier.keys {
                group.addTask { (key, await repo.series(key: key, source: "apple-health")) }
            }
            var acumulado: [String: [(day: String, value: Double)]] = [:]
            for await (key, puntos) in group { acumulado[key] = puntos }
            return acumulado
        }

        let readDays = await pendingDays
        // `classify` es la ÚNICA puerta que reconoce toda la familia «apple-health:<app>»; comparar
        // por igualdad exacta se perdía cada fila con nombre de app.
        let appleOnly = await pendingWorkouts.filter { WorkoutSource.classify($0.source) == .apple }

        await MainActor.run {
            var merged = fetched
            // La temperatura de piel NO viaja como serie: HealthKit escribe la desviación nocturna en
            // `DailyMetric.skinTempDevC`. Se toma de ahí para que no salga vacía en datos ya sincronizados.
            merged["skin_temp"] = repo.days.compactMap { fila in
                fila.skinTempDevC.map { (day: fila.day, value: $0) }
            }
            dailyRows = readDays.sorted { $0.day < $1.day }
            loggedWorkouts = appleOnly
            rawSeries = merged
            rebuild()
            finishedReading = true
        }
    }

    #if DEBUG
    /// FER-389 (mapa 100 %): leer el store es casi instantáneo, así que sin este freno el estado
    /// «leyendo» nunca dura lo suficiente para una captura determinista del harness.
    private func stallForScreenshotHarness() async {
        let bandera = UserDefaults.standard.string(forKey: "cenit.slowLoad")?.lowercased()
        guard bandera == "yes" else { return }
        try? await Task.sleep(for: .seconds(3))
    }
    #endif

    private func rebuild() {
        dossier = AppleHealthDossier.assemble(span: span, series: rawSeries,
                                              days: dailyRows, workouts: loggedWorkouts)
    }

    // MARK: Encabezado y selector

    /// El subtítulo refleja el tramo VISIBLE de filas diarias; antes de terminar de leer, la frase
    /// que describe la pantalla.
    private var headerSubtitle: String {
        let rows = finishedReading ? dossier.days : dailyRows
        guard let opening = rows.first?.day, let closing = rows.last?.day,
              let from = Repository.parseDayKey(opening),
              let to = Repository.parseDayKey(closing) else {
            return String(localized: "Steps, heart, sleep, body composition and VO₂ max: read locally on this iPhone.")
        }
        let desde = Self.spanStamp.string(from: from)
        let hasta = Self.spanStamp.string(from: to)
        let stretch = desde == hasta ? desde : "\(desde) → \(hasta)"
        return String(localized: "\(rows.count) days · \(stretch)")
    }

    /// Puente entre el índice del selector Liquid y la ventana activa (el orden de `allCases` manda).
    private var spanSelection: Binding<Int> {
        Binding(
            get: { AppleHealthSpan.allCases.firstIndex(of: span) ?? 0 },
            set: { indice in span = AppleHealthSpan.allCases[indice] })
    }

    /// Cuántos días abarca la ventana, y si alguna serie rala se tuvo que ensanchar.
    private var windowLegend: String {
        let n = dossier.days.count
        let unit = n == 1 ? String(localized: "day") : String(localized: "days")
        guard dossier.holdsWidenedSeries else {
            return String(localized: "\(n) \(unit) · \(span.phrase)")
        }
        return String(localized: "\(n) \(unit) · \(span.phrase) · some sparse series widened")
    }

    // MARK: Rejilla de tiles

    private var tileRecipes: [AppleHealthTileRecipe] {
        [
            AppleHealthTileRecipe(key: "steps", format: { CenitFormat.groupedInt($0) }),
            AppleHealthTileRecipe(key: "resting_hr", unit: String(localized: "bpm"),
                                  format: { rounded($0) }),
            AppleHealthTileRecipe(key: "hrv", unit: String(localized: "ms"),
                                  format: { rounded($0) }),
            AppleHealthTileRecipe(key: "vo2max", unit: String(localized: "ml/kg"),
                                  format: { oneDecimal($0) }),
            AppleHealthTileRecipe(key: "weight", format: { mass($0) }),
            AppleHealthTileRecipe(key: "body_fat", unit: "%", format: { oneDecimal($0) }),
            AppleHealthTileRecipe(key: "lean_mass", format: { mass($0) }),
            AppleHealthTileRecipe(key: "asleep_min", summary: .average, format: { clock($0) }),
        ]
    }

    private var tileGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: LiquidSpace.s200)],
            alignment: .leading,
            spacing: LiquidSpace.s200
        ) {
            ForEach(tileRecipes, id: \.key) { recipe in
                tile(recipe)
            }
            workoutTile
        }
    }

    /// Tile «quiet» de `LiquidMetricTile` (sin delta): héroe + pie + traza, todos leyendo la MISMA
    /// ventana resuelta, así que el pie nunca describe un tramo distinto al de la traza.
    private func tile(_ recipe: AppleHealthTileRecipe) -> some View {
        let window = dossier.window(recipe.key)
        let numbers = window.points.map(\.value)
        let mark = MetricIdentity.identity(forIngestKey: recipe.key)

        var hero = "—"
        var footnote: String?
        if !numbers.isEmpty {
            switch recipe.summary {
            case .newest:
                hero = recipe.format(numbers.last ?? 0)
                footnote = window.points.last
                    .flatMap { Repository.parseDayKey($0.day) }
                    .map { String(localized: "as of \(Self.dayStamp.string(from: $0))") }
            case .average:
                hero = recipe.format(average(numbers) ?? 0)
                footnote = String(localized: "avg · \(numbers.count)d")
            }
        }

        // El glifo no es opcional en el tile; las claves de composición corporal y VO₂ todavía no
        // tienen familia propia y caen al de carga, igual que su preview en CenitDesign.
        return LiquidMetricTile(label: metricName(recipe.key),
                                value: hero,
                                unit: recipe.unit,
                                delta: nil,
                                tone: numbers.isEmpty ? LiquidColor.tinta500 : mark.hue,
                                icon: mark.glyph ?? .carga,
                                caption: footnote,
                                sparkline: numbers.count > 1 ? Array(numbers.suffix(40)) : nil)
    }

    /// Entrenamientos es un conteo, no una serie, pero se recorta a la misma ventana que el resto:
    /// un total histórico repetido bajo la pestaña «W» se leería como «tus entrenamientos de la semana».
    private var workoutTile: some View {
        let total = dossier.workouts
        let footnote: String?
        if total == 0 {
            footnote = nil
        } else {
            footnote = dossier.workoutsFollowSpan
                ? String(localized: "Apple-logged")
                : String(localized: "All-time total")
        }
        return LiquidMetricTile(label: String(localized: "Workouts"),
                                value: "\(total)",
                                delta: nil,
                                tone: total > 0 ? LiquidColor.ambar : LiquidColor.tinta500,
                                icon: .carga,
                                caption: footnote)
    }

    // MARK: Grupos de gráfica

    private var vitalsGroup: some View {
        chartGroup(String(localized: "Heart & Vitals"), recipes: [
            AppleHealthChartRecipe(key: "resting_hr", fallbackDomain: 40...80,
                                   format: { "\(rounded($0)) \(String(localized: "bpm"))" }),
            AppleHealthChartRecipe(key: "hrv", fallbackDomain: 20...120,
                                   format: { "\(rounded($0)) ms" }),
            AppleHealthChartRecipe(key: "spo2", fallbackDomain: 90...100,
                                   format: { String(format: "%.1f%%", $0) }),
            AppleHealthChartRecipe(key: "resp_rate", fallbackDomain: 10...22,
                                   format: { String(format: "%.1f rpm", $0) }),
            // Desviación respecto a la base (°C), no una temperatura absoluta — mismo formato que
            // Cuerpo y la ficha de la métrica.
            AppleHealthChartRecipe(key: "skin_temp", fallbackDomain: -1.5...1.5,
                                   format: { String(format: "%+.1f°C", $0) }),
        ])
    }

    private var activityGroup: some View {
        chartGroup(String(localized: "Activity & Energy"), recipes: [
            AppleHealthChartRecipe(key: "steps", fallbackDomain: 0...12000,
                                   format: { CenitFormat.groupedInt($0) }),
            AppleHealthChartRecipe(key: "active_kcal", fallbackDomain: 0...1000,
                                   format: { "\(CenitFormat.groupedInt($0)) kcal" }),
        ])
    }

    private var bodyGroup: some View {
        chartGroup(String(localized: "Body Composition"), recipes: [
            AppleHealthChartRecipe(key: "weight", fallbackDomain: 50...100, format: { mass($0) }),
            AppleHealthChartRecipe(key: "body_fat", fallbackDomain: 8...35,
                                   format: { String(format: "%.1f%%", $0) }),
            AppleHealthChartRecipe(key: "lean_mass", fallbackDomain: 40...80, format: { mass($0) }),
            AppleHealthChartRecipe(key: "bmi", fallbackDomain: 16...35, format: { oneDecimal($0) }),
        ])
    }

    private var sleepGroup: some View {
        chartGroup(String(localized: "Sleep"), recipes: [
            AppleHealthChartRecipe(key: "asleep_min", fallbackDomain: 240...600, format: { clock($0) }),
        ])
    }

    /// Un grupo: rótulo inset + sello de ventana, y debajo sus tarjetas.
    private func chartGroup(_ title: String, recipes: [AppleHealthChartRecipe]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(LiquidType.franja)
                    .tracking(LiquidType.franjaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: span.stamp)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            ForEach(recipes, id: \.key) { recipe in
                chartCard(recipe)
            }
        }
    }

    /// Tarjeta de una serie: nombre canónico + nota de ventana + media en su tono, la traza cruda y
    /// el pie promedio/mín/máx/puntos.
    private func chartCard(_ recipe: AppleHealthChartRecipe) -> some View {
        let window = dossier.window(recipe.key)
        let numbers = window.points.map(\.value)
        let name = metricName(recipe.key)
        let tone = MetricIdentity.identity(forIngestKey: recipe.key).hue
        let center = average(numbers)

        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(verbatim: name)
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text(verbatim: readingsNote(window))
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: LiquidSpace.s200)
                if let center {
                    Text(verbatim: recipe.format(center))
                        .font(LiquidType.valorM)
                        .foregroundStyle(tone)
                }
            }
            plot(recipe, window: window, numbers: numbers, name: name, tone: tone)
                .frame(height: Self.plotHeight)
                .clipped()
            LiquidResumenVentana(celdas: summaryCells(numbers, format: recipe.format, tone: tone))
        }
        .liquidTarjetaSeccion()
    }

    /// El cuerpo de la tarjeta. Un solo punto NO es una línea: se presenta como lectura suelta en vez
    /// de fingir un «sin datos» sobre una serie que sí tiene algo que decir.
    @ViewBuilder
    private func plot(_ recipe: AppleHealthChartRecipe,
                      window: AppleHealthSeriesWindow,
                      numbers: [Double],
                      name: String,
                      tone: Color) -> some View {
        let dots: [(fecha: Date, valor: Double)] = window.points.compactMap { punto in
            guard let fecha = Repository.parseDayKey(punto.day) else { return nil }
            return (fecha: fecha, valor: punto.value)
        }
        if dots.count >= 2 {
            LiquidGraficaNiveles(
                puntos: dots,
                bandas: [],
                dominio: domain(numbers, fallback: recipe.fallbackDomain),
                ticksY: [],
                tono: tone,
                formatoValorScrub: recipe.format,
                formatoFechaScrub: { Self.dayStamp.string(from: $0) },
                formatoFechaEje: { Self.dayStamp.string(from: $0) },
                estadoVacio: String(localized: "No readings recorded."),
                a11yLabel: String(localized: "\(name) trend"))
        } else if let lone = numbers.last {
            LoneReadingWell(reading: recipe.format(lone), tone: tone)
        } else {
            NoReadingsWell()
        }
    }

    private func summaryCells(_ numbers: [Double],
                              format: (Double) -> String,
                              tone: Color) -> [LiquidResumenVentana.Celda] {
        guard let center = average(numbers),
              let low = numbers.min(),
              let high = numbers.max() else {
            return [
                LiquidResumenVentana.Celda(rotulo: String(localized: "Avg"), valor: "—"),
                LiquidResumenVentana.Celda(rotulo: String(localized: "Min"), valor: "—"),
                LiquidResumenVentana.Celda(rotulo: String(localized: "Max"), valor: "—"),
                LiquidResumenVentana.Celda(rotulo: String(localized: "Points"), valor: "0"),
            ]
        }
        return [
            LiquidResumenVentana.Celda(rotulo: String(localized: "Avg"), valor: format(center), tono: tone),
            LiquidResumenVentana.Celda(rotulo: String(localized: "Min"), valor: format(low)),
            LiquidResumenVentana.Celda(rotulo: String(localized: "Max"), valor: format(high)),
            LiquidResumenVentana.Celda(rotulo: String(localized: "Points"), valor: "\(numbers.count)"),
        ]
    }

    /// «N lecturas · <ventana>», diciendo en voz alta cuándo hubo que ensanchar.
    private func readingsNote(_ window: AppleHealthSeriesWindow) -> String {
        let n = window.points.count
        let unit = n == 1 ? String(localized: "reading") : String(localized: "readings")
        guard window.span == span else {
            return String(localized: "\(n) \(unit) · sparse: widened to \(window.span.phrase)")
        }
        return String(localized: "\(n) \(unit) · \(span.phrase)")
    }

    // MARK: Números y rótulos

    /// El nombre canónico de una clave de ingesta — el ÚNICO puente. Nunca un rótulo inventado aquí,
    /// para que el tile y su gráfica llamen igual a la misma métrica.
    private func metricName(_ key: String) -> String {
        guard let descriptor = MetricCatalog.descriptor(forIngestKey: key) else { return key }
        return descriptor.canonicalTitle
    }

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: storedUnitSystem) ?? .metric
    }

    /// Kilos → la unidad de masa activa, con su rótulo («74.5 kg» / «164.2 lb»).
    private func mass(_ kilograms: Double) -> String {
        UnitFormatter.massFromKilograms(kilograms, system: unitSystem)
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func clock(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        let hours = whole / 60
        let rest = whole % 60
        return hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
    }

    private func average(_ numbers: [Double]) -> Double? {
        guard !numbers.isEmpty else { return nil }
        return numbers.reduce(0, +) / Double(numbers.count)
    }

    /// Dominio de la traza: min/max con 12 % de aire; una serie plana se abre ±1; sin datos, el
    /// dominio de respaldo de la receta.
    private func domain(_ numbers: [Double], fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let low = numbers.min(), let high = numbers.max() else { return fallback }
        guard high > low else { return (low - 1)...(high + 1) }
        let air = (high - low) * 0.12
        return (low - air)...(high + air)
    }
}

// MARK: - Piezas de la pantalla

private struct SourceHeader: View {
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            // El overline dice el ROL, no repite el nombre que va justo debajo.
            LiquidOverline(String(localized: "Source"))
            Text(String(localized: "Apple Health"))
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(verbatim: subtitle)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LiquidSpace.s050)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Todavía no hay nada importado. Manda el camino RÁPIDO (volver a Fuentes de datos y sincronizar);
/// el .zip de años de historia queda como lo que es: el respaldo lento.
private struct NothingImportedCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "Nothing imported yet"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Go back to Data Sources and tap Sync now (or Connect Apple Health, if it isn't linked yet)."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "For years of history at once: Health app → your photo → Export All Health Data, then import that .zip in Data Sources."))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
    }
}

/// El estado de espera NOMBRA lo que está pasando, a la vista y no solo en VoiceOver.
private struct ReadingCard: View {
    var body: some View {
        HStack(spacing: LiquidSpace.s250) {
            ProgressView()
                .tint(LiquidColor.tinta500)
            Text(String(localized: "Reading your Apple Health history…"))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidTarjetaSeccion()
    }
}

private struct SpanBar: View {
    let selection: Binding<Int>
    let legend: String
    let legendNeedsAttention: Bool
    let stamp: String

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            LiquidRangeSelector(opciones: AppleHealthSpan.allCases.map(\.pill),
                                seleccion: selection,
                                tono: LiquidColor.tinta700)
                .accessibilityLabel(String(localized: "Time range"))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: legend)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(legendNeedsAttention ? LiquidColor.atencionTexto : LiquidColor.tinta500)
                    .accessibilityLabel(legend)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: stamp)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }
}

/// Pozo para una serie con exactamente una lectura en la ventana.
private struct LoneReadingWell: View {
    let reading: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "Latest reading"))
                .liquidLabel()
                .foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: reading)
                .font(LiquidType.valorTileL)
                .tracking(LiquidType.valorTileTracking)
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Pozo para una serie sin ninguna lectura.
private struct NoReadingsWell: View {
    var body: some View {
        Text(String(localized: "No readings recorded."))
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
    }
}

// MARK: - Costura de preview

extension AppleHealthView {
    /// Paquete en memoria que sustituye la lectura del store en el canvas. Los entrenamientos llegan
    /// como filas crudas (no un conteo) para que el tile tenga fechas reales que recortar.
    fileprivate struct Seed {
        var days: [AppleDaily]
        var workouts: [WorkoutRow]
        var series: [String: [(day: String, value: Double)]]
    }
}

#if DEBUG
@MainActor
private func seededAppleHealth() -> AppleHealthView.Seed {
    let calendario = Calendar(identifier: .gregorian)
    let claveDeDia = DayKey.utcFormatter
    let ahora = Date()
    let historia = 730

    var days: [AppleDaily] = []
    var workouts: [WorkoutRow] = []
    var series: [String: [(day: String, value: Double)]] = [:]
    for key in ["steps", "active_kcal", "vo2max", "resting_hr", "hrv", "spo2", "resp_rate",
                "skin_temp", "asleep_min", "weight", "body_fat", "lean_mass", "bmi"] {
        series[key] = []
    }

    // Dos años de historia: suficiente profundidad para que las seis pestañas del selector se vean
    // distintas entre sí.
    for indice in 0..<historia {
        let atras = historia - 1 - indice
        guard let fecha = calendario.date(byAdding: .day, value: -atras, to: ahora) else { continue }
        let dia = claveDeDia.string(from: fecha)
        let t = Double(indice)
        let ruido = { (semilla: Int, tope: Int) in Double((indice &* semilla) % tope) }

        let pasos = 8000 + 3200 * sin(t / 6.0) + ruido(53, 1800)
        let activas = max(120, 420 + 180 * sin(t / 5.0 + 0.6) + ruido(17, 90))
        let fcReposo = max(40, 53 + 4 * sin(t / 8.0) + ruido(7, 4) - 2)
        let vfc = max(15, 58 + 16 * sin(t / 9.0) + ruido(13, 11) - 5)
        let oxigeno = min(100, 96 + 1.4 * sin(t / 4.0) + ruido(3, 2))
        let respiracion = 14.5 + 1.2 * sin(t / 7.0)
        let vo2 = 47 + 2.2 * sin(t / 21.0)
        let dormido = max(180, 410 + 55 * sin(t / 5.0 + 1.1) + ruido(11, 30) - 15)
        // Desviación en °C respecto a la base, igual que la columna real.
        let piel = 0.15 * sin(t / 10.0) + ruido(7, 5) * 0.05 - 0.1
        let peso = 78.0 - 5.0 * sin(t / 220.0) + 0.6 * sin(t / 13.0)
        let grasa = 18.0 - 3.0 * sin(t / 240.0) + 0.4 * sin(t / 11.0)

        days.append(AppleDaily(day: dia,
                               steps: Int(max(0, pasos).rounded()),
                               activeKcal: activas,
                               basalKcal: 1600,
                               vo2max: vo2,
                               avgHr: 72,
                               maxHr: 148,
                               walkingHr: 96,
                               weightKg: peso))

        series["steps"]?.append((dia, max(0, pasos)))
        series["active_kcal"]?.append((dia, activas))
        series["vo2max"]?.append((dia, vo2))
        series["resting_hr"]?.append((dia, fcReposo))
        series["hrv"]?.append((dia, vfc))
        series["spo2"]?.append((dia, oxigeno))
        series["resp_rate"]?.append((dia, respiracion))
        series["skin_temp"]?.append((dia, piel))
        series["asleep_min"]?.append((dia, dormido))

        // La composición corporal se mide UNA vez por semana: rala a propósito, para ejercitar el
        // ensanchamiento automático de la ventana.
        if indice % 7 == 0 {
            series["weight"]?.append((dia, peso))
            series["body_fat"]?.append((dia, grasa))
            series["lean_mass"]?.append((dia, peso * (1.0 - grasa / 100.0)))
            series["bmi"]?.append((dia, peso / (1.78 * 1.78)))
        }

        // Un entrenamiento cada seis días, repartidos por los dos años: así el tile cambia de cifra
        // al cambiar de pestaña.
        if indice % 6 == 0 {
            let arranque = Int(fecha.timeIntervalSince1970)
            workouts.append(WorkoutRow(startTs: arranque,
                                       endTs: arranque + 2700,
                                       sport: "run",
                                       source: "apple-health",
                                       durationS: 2700,
                                       energyKcal: 380,
                                       avgHr: 132,
                                       maxHr: 158,
                                       strain: nil,
                                       distanceM: 5200,
                                       zonesJSON: nil,
                                       notes: nil))
        }
    }

    return AppleHealthView.Seed(days: days, workouts: workouts, series: series)
}

#Preview("Apple Health: seeded") {
    AppleHealthView(seed: seededAppleHealth())
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 980)
}

#Preview("Apple Health: empty") {
    AppleHealthView(seed: .init(days: [], workouts: [], series: [:]))
        .environmentObject(Repository(deviceId: "preview"))
        .frame(width: 920, height: 600)
}
#endif
