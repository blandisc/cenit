#if os(iOS)
import SwiftUI
import Foundation
import CenitDesign
import CenitAnalytics
import CenitStore

// MARK: - Explore (Metric Explorer + Detail) — en vidrio «Liquid Glass» (FER-104 · TND-31)
// The catalog-driven "Explore" surface, migrated from the light «Instrumento» paper to the Liquid
// Glass language, sibling to Compare (TND-30) and the vital detail (TND-19/20). The root is a
// categorized picker — one section per `MetricCatalog.category`, its rows `LiquidListRow`s on a
// solid card, each pushing a GENERIC detail. The detail is a uniform analytic dossier for ANY of
// the ~35 catalog metrics: a tinted Liquid hero (`LiquidCampoMetrica`), a raw-line history
// (`LiquidGraficaNiveles` + `LiquidResumenVentana`) as protagonist, and a method+provenance foot.
// A17 (architecture, co-decided): the Explorer migrates its OWN `MetricDetailView` IN PLACE to a
// generic Liquid detail — it does NOT route to `MetricDetailScreen`. The 7 rich metrics keep
// opening `MetricDetailScreen` from Hoy/Cuerpo; from the Explorer, ALL 35 open this generic
// dossier. The NavigationStack push is conserved (the Explorer's contract, distinct from the
// sheet/overlay of the rich screens).
//
// THE MIGRATION IS SKIN, NOT THREAD (FER-104): the data path is conserved verbatim from the paper
// screen — the shared `MetricSeriesResolver` for every series (TND-29), the memoized window math
// (FER-269). What
// changed is every surface, plus the three invariants TND-29 exists to fix:
//   • COLOR IS IDENTITY, per metric — `MetricIdentity.hue(for:)`, never the rival `metricAccent`
//     map (deleted here). Each dot/field/chart wears its family's hue on every screen.
//   • NAME IS CANONICAL — `canonicalTitle` says «Effort», never «Day Strain» (HJ-13).
//
// «Qué correlaciona» (the cross-catalog Pearson sweep and its in-line r bar) was RETIRED in FER-489
// (ola 0b, DECISIONS 2026-09-15 punto 5): the dossier is hero + history + method, nothing else.

/// «9 jun 2026» — la fecha larga de la cláusula del héroe, en el idioma del usuario. Los días vienen
/// con clave UTC, así que la zona se clava ahí y el rótulo no se corre de día.
private let longDateFmt: DateFormatter = {
    let formateador = DateFormatter()
    formateador.locale = .autoupdatingCurrent
    formateador.timeZone = TimeZone(identifier: "UTC")
    formateador.setLocalizedDateFormatFromTemplate("d MMM y")
    return formateador
}()
private func longDate(_ fecha: Date) -> String { longDateFmt.string(from: fecha) }

// `originVocabulary(_:)` + `metricIsCalculated(_:)` now live in CompareView.swift (unguarded, shared
// by both instruments): the origin label speaks the Hoy sheet's CLOSED vocabulary — «Apple Health» /
// «Apple Watch» / «Calculated on your phone» — instead of the raw catalog tag (C-16). Used here as
// the catalog row subtitle and the detail's provenance chip label; the chip keeps its identity
// glyph/hue and only the text changes.

// MARK: - On-device series resolver / range
//
// Explore shares `MetricSeriesResolver` (`Cenit/Data/MetricSeriesResolver.swift`) with Compare so a
// catalog key resolves to the SAME number on both screens (TND-29). The W/M/3M/6M/1Y/ALL window
// lives in `ExploreRange` + `MetricWindowMath` (FER-269), shared by every drill-down.

// MARK: - Root: categorized picker

/// The "Explore" picker in Liquid — categories as inset sections, metrics as `LiquidListRow`s on a
/// solid card, each pushing the generic `MetricDetailView`. A metric with no series at all is flagged
/// in the a11y hint only ("No data"), never as a visible trailing word (TND31-3).
struct MetricExplorerView: View {
    @EnvironmentObject private var repo: Repository
    /// id de métrica → si su serie está vacía. Se resuelve una sola vez, al abrir.
    @State private var sinSerie: [String: Bool] = [:]

    // Sin `NavigationStack` aquí: Explorar se empuja dentro de la pila de la hoja que la monta. Una
    // pila anidada cruzando estos valores `MetricDescriptor` reventaba SwiftUI. La lista y su
    // `.navigationDestination(for: MetricDescriptor.self)` cuelgan de esa pila de afuera.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                header
                secciones
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity,
                   alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        // El Explorador no tiene un sujeto único que teñir: papel cálido neutro, como el selector de
        // Comparar. Se pone también en la hoja para que sus márgenes empaten con el suelo del scroll.
        .presentationBackground { LiquidSheetFondo() }
        .navigationDestination(for: MetricDescriptor.self) { metric in
            MetricDetailView(metric: metric)
        }
        .task { await sondearVacias() }
    }

    /// Una sección por categoría con métricas; una categoría vacía no se pinta.
    @ViewBuilder
    private var secciones: some View {
        ForEach(MetricCatalog.categories, id: \.self) { categoria in
            let deLaCategoria = MetricCatalog.inCategory(categoria)
            if !deLaCategoria.isEmpty {
                categorySection(categoria, metrics: deLaCategoria)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(String(localized: "Explore"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Every signal, one tap deep."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One category: an inset overline + count (the picker carries its count like Compare's blocks,
    /// not an a-sangre franja — that voice belongs to the read-only detail), then its rows on ONE
    /// solid card, hairline-divided by `LiquidListRow`'s own divider.
    private func categorySection(_ category: String, metrics: [MetricDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            encabezadoDeCategoria(category, conteo: metrics.count)
            VStack(spacing: .zero) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { posicion, metric in
                    fila(metric, ultima: posicion == metrics.count - 1)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
    }

    private func encabezadoDeCategoria(_ category: String, conteo: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(MetricCatalog.localizedCategory(category))
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LiquidSpace.s200)
            Text(verbatim: "\(conteo)")
                .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
        }
    }

    /// Una fila del índice. «Sin datos» vive SOLO en la pista de VoiceOver: el papel marcaba una
    /// métrica vacía con un punto quieto, nunca con la PALABRA, y la única ranura de cola de
    /// `LiquidListRow` es un texto que VoiceOver lee. La cola se queda en el galón de siempre.
    private func fila(_ metric: MetricDescriptor, ultima: Bool) -> some View {
        NavigationLink(value: metric) {
            LiquidListRow(
                title: metric.canonicalTitle,
                subtitle: originVocabulary(metric),
                tone: MetricIdentity.hue(for: metric),
                a11yHint: (sinSerie[metric.id] ?? false) ? String(localized: "No data") : nil,
                divider: !ultima)
        }
        .buttonStyle(.plain)
    }

    /// Una pasada ligera para saber qué métricas no tienen serie, y que la fila lo pueda decir en
    /// VoiceOver. Una métrica tiene datos si el tablero la calcula en el teléfono O si se importó.
    /// Una sola consulta `DISTINCT key` por origen, de puro índice, con el resolvedor COMPARTIDO.
    private func sondearVacias() async {
        guard sinSerie.isEmpty else { return }
        let tablero = repo.displayDays
        let importadas = await repo.availableKeySets(sources: MetricCatalog.all.map(\.source))
        var mapa: [String: Bool] = [:]
        for descriptor in MetricCatalog.all {
            let calculada = !(MetricSeriesResolver.dashboardSeries(descriptor.key, from: tablero) ?? []).isEmpty
            let importada = importadas[descriptor.source]?.contains(descriptor.key) ?? false
            mapa[descriptor.id] = !(calculada || importada)
        }
        sinSerie = mapa
    }
}

// MARK: - Detail / drill-down (generic Liquid dossier)

/// The uniform analytic dossier for ANY catalog metric in Liquid: a tinted hero
/// (`LiquidCampoMetrica`, identity per metric), a raw-line history (`LiquidGraficaNiveles` +
/// `LiquidResumenVentana`), and a method+provenance foot. Serves the ~35 metrics: the ~7 with a
/// canonical hue read from the identity bridge, the rest fall to `verdePrimario` with no glyph
/// (TND-29's documented fallback).
struct MetricDetailView: View {
    let metric: MetricDescriptor
    @EnvironmentObject private var repo: Repository

    // Imperial/Metric display preference (D#103). Display-only: weight (kg) and skin temp (°C)
    // re-label; everything else is unit-agnostic and renders unchanged.
    @AppStorage(UnitPrefs.systemKey) private var storedUnitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var storedTemperature = ""
    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: storedUnitSystem) ?? .metric
    }
    private var temperature: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: storedTemperature)
    }
    private func fmt(_ valor: Double) -> String {
        metric.format(valor, system: unitSystem, temperature: temperature)
    }

    /// The displayed number for `v` WITHOUT its unit (TND31-2). The generic detail's `fmt` folds
    /// number+unit into one string, so the range extremes had to be built from `fmt` and doubled the
    /// unit («68 %–76 %»). This mirrors the sibling `MetricDetailScreen`, which keeps a bare `fmt`
    /// number and a separate `unit` suffix — the extremes join as bare numbers and the unit prints
    /// ONCE. The two SI units with an imperial form convert here too (kg → kg/lb at one decimal, like
    /// `UnitFormatter.massFromKilograms`; °C → °C/°F at the metric's precision), so the range never
    /// double-labels in either system. Everything else falls to the plain decimals path (`format`).
    private func bareNumber(_ v: Double) -> String {
        guard v.isFinite else { return "—" }   // FER-465
        switch metric.unit {
        case "kg":
            return String(format: "%.1f", unitSystem == .imperial ? UnitFormatter.kgToPounds(v) : v)
        case "°C":
            let t = temperature == .fahrenheit ? UnitFormatter.celsiusToFahrenheit(v) : v
            return metric.decimals == 0 ? String(Int(t.rounded())) : String(format: "%.\(metric.decimals)f", t)
        default:
            return metric.decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(metric.decimals)f", v)
        }
    }

    /// The active display-unit label ("%", "min", "kg"/"lb", "°C"/"°F", …); "" for a unitless metric.
    private var displayUnit: String { metric.displayUnit(system: unitSystem, temperature: temperature) }

    /// «68–76 %» — the window range as bare extremes with the unit exactly ONCE (TND31-2), never the
    /// doubled «68 %–76 %». En-dash between the extremes (no spaces), one leading space before the unit,
    /// matching `MetricDescriptor.format`'s «\(n) \(unit)». Unitless metrics drop the suffix.
    private func rangoValor(_ lo: Double, _ hi: Double) -> String {
        let cuerpo = "\(bareNumber(lo))–\(bareNumber(hi))"
        return displayUnit.isEmpty ? cuerpo : "\(cuerpo) \(displayUnit)"
    }

    // `-cenit.range` (FER-384 · mapa 100%) fija la ventana inicial para la captura; una corrida
    // normal cae al `.month` de siempre (`TendenciasFixtures.debugRange()` es DEBUG-only).
    #if DEBUG
    @State private var range = TendenciasFixtures.debugRange() ?? ExploreRange.month
    #else
    @State private var range = ExploreRange.month
    #endif
    /// The field's ⓘ opens the uniform «What we measure» card beneath it (D3/C-17, calco
    /// StrainDetailScreen.infoOpen). ONE card for all 35 metrics — no per-metric essay.
    @State private var infoOpen = false
    /// La serie completa de esta métrica, ascendente por día: TODA la historia.
    @State private var historia: [(day: String, value: Double)] = []
    /// The series with each `day` string parsed to a `Date` exactly ONCE — the shared window math
    /// reads `date` straight from here (FER-269). Se arma en `cargar()`.
    @State private var parsed: MetricWindowMath.Parsed = []
    @State private var yaLeido = false

    /// «jun 6» axis/scrub label, UTC-anchored so the local-zone label never slips west of UTC.
    private static let ejeFmt: DateFormatter = {
        let formateador = DateFormatter()
        formateador.locale = .autoupdatingCurrent
        formateador.timeZone = TimeZone(secondsFromGMT: 0)
        formateador.setLocalizedDateFormatFromTemplate("dMMM")
        return formateador
    }()

    // MARK: Identity (the puente — kills `metricAccent`)

    private var hue: Color { MetricIdentity.hue(for: metric) }
    private var glyph: LiquidIcon.Glyph? { MetricIdentity.glyph(for: metric) }

    // MARK: Derivados

    private var latest: (day: String, value: Double)? { historia.last }

    /// Dominio con aire para que la línea no quede pegada al eje: min…max con 12 % de holgura. Es el
    /// dominio de la VENTANA, nunca una banda fija de niveles.
    private func dominioDeVentana(_ windowValues: [Double]) -> ClosedRange<Double> {
        guard let bajo = windowValues.min(), let alto = windowValues.max() else { return 0...1 }
        guard alto > bajo else { return (bajo - 1)...(alto + 1) }
        let aire = (alto - bajo) * 0.12
        return (bajo - aire)...(alto + aire)
    }

    /// A Binding<Int> bridging `LiquidRangeSelector`'s index to `range` (allCases order = W…ALL).
    private var rangeIndex: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { range = ExploreRange.allCases[$0] })
    }

    // MARK: Cuerpo

    var body: some View {
        // La ventana se resuelve UNA vez por evaluación del body y se le entrega a los bloques.
        let ventana = MetricWindowMath.make(parsed, selected: range)
        return ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                heroField
                if infoOpen { whatWeMeasureCard }
                fusionRow
                dossier(ventana)
            }
            .frame(maxWidth: .infinity,
                   alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo(tone: hue).ignoresSafeArea() }
        .navigationTitle(metric.canonicalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: metric.id) { await cargar() }
    }

    /// Lo que va bajo el héroe: la espera, el vacío honesto, o el dossier completo.
    @ViewBuilder
    private func dossier(_ ventana: MetricWindow) -> some View {
        if !yaLeido {
            LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
                .liquidSeccion()
        } else if historia.isEmpty {
            // El ÚNICO vacío genuino: ni un dato en toda la historia. FER-433: en vez del pozo
            // (una gráfica sin puntos), el vacío que enseña — qué va aquí y cómo se llena.
            LiquidFranjaSeccion(String(localized: "History"), tono: hue)
            LiquidVacio(
                queEs: Text(String(localized: "vacio.detalle.tendencia.queEs",
                                   defaultValue: "This period's trend goes here.")),
                comoSeLlena: Text(String(localized: "No history yet. Connect Apple Health in Data Sources and it fills every metric you can explore here.")))
                .liquidSeccion()
        } else {
            LiquidFranjaSeccion(String(localized: "History"), tono: hue)
            trendContent(window: ventana).liquidSeccion()
            pieMetodo
        }
    }

    // MARK: - 1. Hero (campo teñido) — identidad por métrica, «as of» como cláusula

    @ViewBuilder private var heroField: some View {
        if let last = latest {
            LiquidCampoMetrica(
                tono: hue,
                titulo: metric.canonicalTitle,
                glifo: glyph,
                datos: [heroDato(last.value)],
                clausula: asOfClause,
                // D3/C-17: the ⓘ opens the uniform «What we measure» card (no verdict, no level
                // phrase — A17). Same lever the sibling MetricDetailScreen uses.
                infoAbierto: infoOpen,
                infoEtiqueta: String(localized: "What we measure"),
                onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } })
        } else {
            LiquidCampoMetrica(
                tono: hue,
                titulo: metric.canonicalTitle,
                glifo: glyph,
                // C-01: no category rótulo — it only echoed the title / a redundant category under a
                // numeral whose identity the title already names; the «as of <date>» clause carries
                // the temporal context.
                datos: [.init(valor: LiquidCajita.sinDato, rotulo: "",
                              a11y: String(localized: "no data"), ausente: true)])
        }
    }

    /// The hero numeral, unit split from the number so the value reads big and the unit small (the
    /// sibling detail's typography). The two SI-stored units that carry an imperial form (kg / °C)
    /// stay WHOLE — `fmt` converts + relabels them as one string, and re-splitting it is fragile.
    /// The bare-number logic mirrors `MetricDescriptor.format` exactly.
    private func heroDato(_ v: Double) -> LiquidCampoDato {
        // C-01: no rótulo — the numeral carried a repeated category («Recovery» under a «Recovery»
        // title). The title names the metric; the «as of <date>» clause dates the number.
        guard v.isFinite else { return .init(valor: "—", rotulo: "") }   // FER-465
        switch metric.unit {
        case "kg", "°C":
            return .init(valor: fmt(v), rotulo: "")
        default:
            let n = metric.decimals == 0 ? String(Int(v.rounded()))
                                         : String(format: "%.\(metric.decimals)f", v)
            return .init(valor: n, unidad: metric.unit, rotulo: "")
        }
    }

    private var asOfClause: String? {
        // C-12: the family (Today's twins, the vital detail) never stamps a FRESH numeral with an
        // absolute date — it says «hoy» / «anoche». The Explorer, though, covers all 35 catalog
        // metrics and many go stale (a weight from three weeks ago, a VO₂max from months back).
        // Dating a reading that IS current would desentonar with the family; NOT dating a 21-day-old
        // weight would LIE that it's current — and copy that misdates the body is the class that
        // breaks the review. So the clause stays SILENT inside the family's freshness window
        // (today / yesterday, the same cut CuerpoView.freshSteps uses) and only dates a reading
        // older than that.
        guard let day = latest?.day, let d = Repository.parseDayKey(day) else { return nil }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        guard day < cutoff else { return nil }
        return String(localized: "as of \(longDate(d))")
    }

    /// The ⓘ card under the field: ONE uniform «what we measure» line for ALL 35 catalog metrics —
    /// no per-metric essay, no verdict, no level phrase (D3/C-17, A17). Same shape as
    /// `StrainDetailScreen.whatWeMeasureCard`.
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "The daily series of this metric, in its unit; the number above is the most recent day."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false,
                           vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    /// FER-670 / FER-254: when a second source reported the shown day (steps / sleep total /
    /// active kcal), say whether they agree — both values visible, a conflict flagged, never
    /// averaged. Liquid via `LiquidNotaLine`. `fusionPoint` folds the calorie alias, so the raw
    /// key works.
    @ViewBuilder private var fusionRow: some View {
        if let day = latest?.day, let agreement = repo.fusionPoint(day: day, metric: metric.key) {
            FusionAgreementRow(point: agreement, format: fmt)
                .padding(.horizontal, LiquidSpace.s550)
                .padding(.top, LiquidSpace.s300)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
        }
    }

    // MARK: - 2. Tu historia — selector + gráfica cruda + resumen de ventana

    private func trendContent(window: MetricWindow) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeIndex, tono: hue)
                .accessibilityLabel(String(localized: "Time range"))
            if window.hasTrend {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    trendChart(window: window)
                    LiquidResumenVentana(celdas: resumenCeldas(window))
                }
                .liquidTarjetaSeccion()
            } else {
                // One reading or none in the range → el vacío que enseña (FER-433).
                MetricDetailScreen.vacioTendencia(noches: false)
            }
        }
    }

    /// The raw line (no moving average — the dossier traces the windowed values directly), on the
    /// window's own domain, tinted by identity. No bands: the generic detail has no level ladder.
    private func trendChart(window: MetricWindow) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [],
            dominio: dominioDeVentana(window.values),
            ticksY: [],
            tono: hue,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFmt.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFmt.string(from: $0) },
            estadoVacio: MetricDetailScreen.vacioTendenciaComoSeLlena(noches: false),
            a11yLabel: String(localized: "\(metric.canonicalTitle) trend"))
    }

    /// Promedio · Δ% (period over period, tinted by the metric's polarity) · Rango — the paper's
    /// `TrendStatSummary`, now the reusable window summary. Δ% drops out on `.all` (no prior period).
    private func resumenCeldas(_ window: MetricWindow) -> [LiquidResumenVentana.Celda] {
        let stat = ComparisonEngine.stat(window.values)
        let promedio = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Average"), valor: fmt(stat.mean))
        let rango = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Range"), valor: rangoValor(stat.min, stat.max))
        guard let pct = window.range.periodComparison(of: historia)?.pctChange else {
            return [promedio, rango]
        }
        let rounded = Int(pct.rounded())
        let texto = rounded > 0 ? "+\(rounded)%" : (rounded < 0 ? "−\(abs(rounded))%" : "0%")
        let cambio = LiquidResumenVentana.Celda(
            rotulo: String(localized: "Change"), valor: texto, tono: deltaTono(pct))
        return [promedio, cambio, rango]
    }

    /// Δ% tint by the metric's polarity: the good direction → `positivo`, the other → `atencionTexto`;
    /// flat or a neutral metric → quiet ink. Mirrors the vital detail's `liquidTonoDelta`.
    private func deltaTono(_ pct: Double) -> Color? {
        guard Int(abs(pct).rounded()) != 0 else { return nil }
        switch metric.higherIsBetter {
        case .some(true):  return pct > 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .some(false): return pct < 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
        case .none:        return nil
        }
    }

    // MARK: - 3. Método + sello de procedencia

    /// D3/C-17 (b): the method line, HONEST by origin. «Your latest daily reading, shown raw, with no
    /// smoothing» LIED for the on-device-computed metrics (recovery / strain / stress) — those are a
    /// calculation, not a raw reading. Two templates, not 35 methods: a measured value vs. a computed
    /// one, keyed to the SAME «calculated» bucket as the provenance chip (`metricIsCalculated`). No
    /// verdict, no level phrase (A17).
    private var metodoTexto: String {
        metricIsCalculated(metric)
            ? String(localized: "The number is the most recent calculated value; the chart traces the daily values across the range.")
            : String(localized: "The number is the most recent value in this series; the chart traces the daily values across the range.")
    }

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(metodoTexto, tono: LiquidColor.tinta700)
            }
            // Provenance chip: the Hoy sheet's CLOSED vocabulary («Apple Health» / «Apple Watch» /
            // «Calculated on your phone», C-16) over the metric's own identity mark — a glyph badge for
            // the ~7 canonical families, a plain tone dot for the rest (glyph == nil, TND31-4: no
            // invented `.rayo`). Only the LABEL adopts the vocabulary; glyph + hue stay identity. With
            // history only.
            if !historia.isEmpty {
                LiquidOrigenChip(glyph: glyph, badgeTono: hue,
                                 etiqueta: originVocabulary(metric))
            }
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Load (data path conserved verbatim from the paper screen)

    private func cargar() async {
        // Manda el tablero ya fusionado (`displayDays`) sobre la tabla de solo-importados: ahí viven
        // los puntajes que el teléfono calcula. Las métricas que solo llegan importadas (peso, grasa
        // corporal, zonas de FC…) caen a la tabla. Las dos vías, por el resolvedor COMPARTIDO.
        let tablero = repo.displayDays

        // La serie focal: la del tablero si el teléfono calcula esta métrica, si no la importada.
        let focalDelTablero = MetricSeriesResolver.dashboardSeries(metric.key, from: tablero) ?? []
        let focal = focalDelTablero.isEmpty
            ? await repo.series(key: metric.key, source: metric.source)
            : focalDelTablero
        historia = focal
        parsed = focal.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        yaLeido = true
    }
}

// MARK: - Canvas

#if DEBUG
/// El canvas monta la pila que la vista ya no provee: su `.navigationDestination` cuelga de ahí.
@MainActor
private func explorerCanvas<Contenido: View>(@ViewBuilder _ contenido: () -> Contenido) -> some View {
    let repositorio = Repository(deviceId: "preview")
    repositorio.setDashboard()
    return NavigationStack(root: contenido)
        .environmentObject(repositorio)
        .frame(width: 390, height: 820)
}

#Preview("Explore") {
    explorerCanvas { MetricExplorerView() }
}

#Preview("Metric Detail") {
    explorerCanvas {
        MetricDetailView(metric: MetricCatalog.all.first { $0.key == "recovery" }!)
    }
}
#endif
#endif
