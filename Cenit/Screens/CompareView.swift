import SwiftUI
import Foundation
import CenitDesign
import StrandAnalytics
import CenitStore

// MARK: - Comparar · superponer señales y sacar conclusiones (Liquid Glass · El Eje)
// Se eligen de 2 a 4 métricas del catálogo y una ventana, y se leen en UNA sola gráfica donde cada
// línea se normaliza min–max DENTRO de su propia ventana: unidades distintas comparten el plot por
// forma, jamás por magnitud. Debajo, cada par recibe su Pearson r vivo con una conclusión en prosa.
// Pantalla de pura lectura: cada métrica se trae del repositorio y todo lo demás se deriva aquí.
// Se presenta como `.sheet` desde Cuerpo y desde la raíz; el fondo es `LiquidSheetFondo` (neutro:
// Comparar no tiene un sujeto único que teñir), se cierra arrastrando y no anida NavigationStack.
//
// Dos invariantes que la pantalla defiende:
//   • EL COLOR ES IDENTIDAD, por métrica — `MetricIdentity.hue(for:)`, nunca una paleta por índice.
//     La misma señal lleva el mismo tono en toda la app.
//   • EL NOMBRE ES CANÓNICO — `canonicalTitle` dice «Esfuerzo», no el apodo de cada pantalla.
//
// El archivo separa a propósito el motor de la piel: `ComparePairing` (la corrida de pares, pura y
// Sendable, fuera del hilo principal) y `CompareWording` (cómo se dice el resultado) no saben nada
// de SwiftUI, y las vistas no saben de estadística.

// MARK: - Vocabulario de procedencia (compartido con el Explorador)
// Las filas del selector de Comparar y las del catálogo del Explorador hablan el MISMO vocabulario
// cerrado que la hoja de Hoy. Solo se adopta el RÓTULO: la fila conserva su glifo y su hue de
// identidad. Vive aquí, sin `#if`, para que el Explorador (solo-iOS) siempre lo alcance.

/// Cierto cuando Cénit CALCULA la métrica en el teléfono, en vez de leer un valor medido o importado.
func metricIsCalculated(_ m: MetricDescriptor) -> Bool {
    ["recovery", "strain", "stress"].contains(m.key)
}

/// De dónde sale la métrica, en el vocabulario CERRADO de la hoja de Hoy: lo calculado en el
/// teléfono, lo que solo puede venir de la muñeca, y todo lo demás.
func originVocabulary(_ m: MetricDescriptor) -> String {
    if metricIsCalculated(m) { return String(localized: "Calculated on your phone") }
    let deMuneca = m.key == "skin_temp" || m.key == "resp_rate"
    return deMuneca ? String(localized: "Apple Watch") : String(localized: "Apple Health")
}

// MARK: - Una serie superpuesta

/// `yyyy-MM-dd` → fecha, con el parser de clave-de-día compartido (UTC / `en_US_POSIX`).
private func compareDate(_ day: String) -> Date? { Repository.parseDayKey(day) }

/// Una métrica elegida, ya resuelta sobre la ventana activa: su descriptor, sus filas recortadas,
/// su color de IDENTIDAD y su mínimo/máximo reales.
private struct OverlaidMetric: Identifiable {
    let descriptor: MetricDescriptor
    /// El hue de identidad de la métrica, no un color por índice: ese es todo el punto del puente.
    let tone: Color
    let window: [(day: String, value: Double)]

    var id: String { descriptor.id }
    var readings: [Double] { window.map(\.value) }
    var lowest: Double { readings.min() ?? 0 }
    var highest: Double { readings.max() ?? 0 }

    /// El valor de un día concreto, si quedó registrado.
    func reading(on day: String) -> Double? {
        window.first { $0.day == day }?.value
    }
}

// MARK: - Motor de pares (puro, fuera de la vista y fuera del hilo principal)

/// El resultado de la corrida, sin nada que no cruce un `Task.detached`: ids y números, jamás un
/// `Color` ni una vista.
private struct PairScan: Sendable {
    let aId: String
    let bId: String
    let r: Double
    let n: Int
}

/// Un par ya listo para pintarse: la corrida re-adjuntada a sus dos series.
private struct PairedMetrics: Identifiable {
    let id: String
    let a: OverlaidMetric
    let b: OverlaidMetric
    let r: Double
    let n: Int
}

private enum ComparePairing {
    /// Huella estable de las entradas de la corrida: si no cambia, la caché sigue siendo válida.
    static func fingerprint(_ series: [OverlaidMetric]) -> String {
        var trazos: [String] = []
        for s in series where !s.window.isEmpty {
            let primera = s.window.first?.day ?? ""
            let ultima = s.window.last?.day ?? ""
            trazos.append("\(s.id):\(s.window.count):\(primera)>\(ultima)")
        }
        return trazos.joined(separator: "|")
    }

    /// La corrida cara: Sendable adentro, Sendable afuera, así que sirve igual síncrona que dentro de
    /// un `Task.detached`. El piso de cómputo y la escalera de fuerza son los canónicos de
    /// `CorrelationStrength`, nunca umbrales inventados aquí.
    static func scan(_ series: [(id: String, puntos: [(day: String, value: Double)])]) -> [PairScan] {
        guard series.count >= 2 else { return [] }
        var hallazgos: [PairScan] = []
        for primera in 0..<(series.count - 1) {
            for segunda in (primera + 1)..<series.count {
                let comunes = CorrelationEngine.alignByDay(series[primera].puntos, series[segunda].puntos)
                guard comunes.count >= CorrelationStrength.minPairs,
                      let correlacion = CorrelationEngine.pearson(comunes) else { continue }
                hallazgos.append(PairScan(aId: series[primera].id,
                                          bId: series[segunda].id,
                                          r: correlacion.r,
                                          n: correlacion.n))
            }
        }
        return hallazgos.sorted { abs($0.r) > abs($1.r) }
    }

    /// Re-adjunta cada corrida a sus series (color y descriptor) por id.
    static func attach(_ scans: [PairScan], to series: [OverlaidMetric]) -> [PairedMetrics] {
        let porId = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        return scans.compactMap { scan in
            guard let a = porId[scan.aId], let b = porId[scan.bId] else { return nil }
            return PairedMetrics(id: "\(scan.aId)~\(scan.bId)", a: a, b: b, r: scan.r, n: scan.n)
        }
    }

    /// Corrida síncrona, usada SOLO como respaldo del mismo cuadro cuando la caché viene fría.
    static func immediate(_ series: [OverlaidMetric]) -> [PairedMetrics] {
        let dibujables = series.filter { !$0.window.isEmpty }
        let foto = dibujables.map { (id: $0.id, puntos: $0.window) }
        return attach(scan(foto), to: dibujables)
    }
}

// MARK: - Cómo se dice el resultado

private enum CompareWording {
    /// El coeficiente escrito como se ve: signo explícito, «−» tipográfico y dos decimales. VoiceOver
    /// lee EXACTAMENTE esta cadena, así que el «+» y el «−» se pronuncian.
    static func signedR(_ r: Double) -> String {
        let signo = r >= 0 ? "+" : "−"
        return signo + String(format: "%.2f", abs(r))
    }

    /// La palabra de fuerza. Los CORTES son la escalera canónica de `CorrelationStrength`; aquí solo
    /// se traduce la palabra.
    static func strength(_ r: Double) -> String {
        switch CorrelationStrength.classify(r: r) {
        case .negligible: return String(localized: "negligible")
        case .weak:       return String(localized: "weak")
        case .moderate:   return String(localized: "moderate")
        case .strong:     return String(localized: "strong")
        case .veryStrong: return String(localized: "very strong")
        }
    }

    static func direction(_ r: Double) -> String {
        guard abs(r) >= 0.1 else { return "" }
        return r >= 0 ? String(localized: "positive") : String(localized: "negative")
    }

    /// Fuerza y dirección como UNA frase, sin espacio colgando cuando no hay dirección que nombrar.
    static func strengthAndDirection(_ r: Double) -> String {
        let dir = direction(r)
        let fuerza = strength(r)
        return dir.isEmpty ? fuerza : "\(fuerza) \(dir)"
    }

    /// La conclusión en prosa. Los nombres son CANÓNICOS; cuando |r| no llega a 0.3 se dice que no hay
    /// relación clara, en vez de forzar una lectura que el número no sostiene.
    static func insight(_ p: PairedMetrics) -> String {
        let aT = p.a.descriptor.canonicalTitle
        let bT = p.b.descriptor.canonicalTitle
        let head = String(localized: "\(aT) ↔ \(bT): r = \(signedR(p.r)) (\(strengthAndDirection(p.r))) over \(p.n) shared days.")
        if abs(p.r) < 0.3 {
            return head + String(localized: " No clear relationship: they move largely independently.")
        }
        let aLower = aT.lowercased()
        let bLower = bT.lowercased()
        let verb = p.r < 0 ? String(localized: "tends to fall") : String(localized: "tends to rise")
        return head + String(localized: " When \(aLower) rises, \(bLower) \(verb): a \(strength(p.r)) \(direction(p.r)) link.")
    }

    static func footer(_ p: PairedMetrics) -> String {
        String(format: String(localized: "compare.pair.footer",
                              defaultValue: "%1$lld overlapping days · %2$@ correlation"),
               p.n, strengthAndDirection(p.r))
    }

    /// Lo que oye VoiceOver, con el coeficiente escrito igual que a la vista.
    static func spoken(_ p: PairedMetrics) -> String {
        String(format: String(localized: "compare.pair.a11y",
                              defaultValue: "%1$@ versus %2$@, r equals %3$@, %4$lld days"),
               p.a.descriptor.canonicalTitle, p.b.descriptor.canonicalTitle, signedR(p.r), p.n)
    }
}

// MARK: - Pantalla

struct CompareView: View {
    @EnvironmentObject private var repo: Repository
    /// Tamaño de texto: en tamaños de accesibilidad la cabecera de la tarjeta de par se apila en vez
    /// de correr el título contra el valor de r.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Con qué abre. Las tres resuelven desde el tablero, así que se ve una superposición desde el
    /// primer momento; si alguna faltara, se cae a las primeras del catálogo.
    private static let openingKeys = ["recovery", "strain", "hrv"]

    private let ceiling = 4
    private let floorCount = 2

    /// Abre en M, igual que el Explorador y los detalles de métrica.
    @State private var range: ExploreRange = .month
    /// Selección ordenada (tope 4). Manda el orden de la leyenda.
    @State private var picked: [MetricDescriptor] = []
    /// El selector es una hoja y no un `Menu`: un menú reinicia su scroll en cada re-render del padre.
    @State private var showPicker = false
    /// Historia completa por id de métrica (ascendente por día); el recorte se hace en la vista.
    @State private var history: [String: [(day: String, value: Double)]] = [:]
    @State private var firstReadDone = false
    /// Series ya ventaneadas — se recalculan solo al cambiar selección, ventana o carga.
    @State private var windowed: [OverlaidMetric] = []
    /// Última corrida de pares y la huella de las entradas con que se calculó.
    @State private var pairs: [PairedMetrics] = []
    @State private var pairFingerprint = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s550) {
                CompareHeader()
                metricBar
                readingArea
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity,
                   alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .presentationBackground { LiquidSheetFondo() }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        .sheet(isPresented: $showPicker) {
            CompareMetricPicker(picked: $picked, ceiling: ceiling)
        }
        .task { await seedSelectionIfNeeded() }
        .task(id: pickedKey) {
            await loadMissingSeries()
            rewindow()
            refreshPairs(windowed)
        }
        // La ventana es la otra entrada de la que dependen las series recortadas.
        .onChange(of: range) {
            rewindow()
        }
        // La corrida solo se rehace cuando cambia el contenido de las series ventaneadas.
        .onChange(of: ComparePairing.fingerprint(windowed)) {
            refreshPairs(windowed)
        }
    }

    /// Lo que va debajo del selector: el pozo honesto que toque, o la superposición y sus correlaciones.
    @ViewBuilder
    private var readingArea: some View {
        if picked.count < floorCount {
            // Elegir menos de dos no es un problema de datos: el selector está justo arriba. Decir
            // «conecta Apple Health» aquí sería mentir; esa copia se reserva para más abajo.
            CompareWell(text: String(localized: "Pick 2–4 metrics to overlay."))
        } else if windowed.allSatisfy({ $0.window.isEmpty }) {
            if firstReadDone {
                // Dos causas, dos copias: no hay historia de NADA (el caso real de sin datos / sin
                // permiso) contra hay historia pero no en ESTA ventana.
                CompareWell(text: noHistoryAtAll ? Self.connectCopy : outOfWindowCopy)
            } else {
                LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your history…"))
            }
        } else {
            overlayBlock
            correlationBlock
        }
    }

    // MARK: Selector de métricas y ventana

    private var metricBar: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(String(localized: "Metrics"))
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)

            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeIndex,
                                tono: LiquidColor.tinta700)
                .accessibilityLabel(String(localized: "Time range"))

            HStack(alignment: .firstTextBaseline) {
                if picked.count >= floorCount {
                    Text(verbatim: readingsCaption)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(someSeriesWidened ? LiquidColor.atencionTexto : LiquidColor.tinta500)
                        .accessibilityLabel(readingsCaption)
                }
                Spacer(minLength: LiquidSpace.s200)
                pickerButton
            }

            if picked.isEmpty {
                Text(String(localized: "Nothing selected yet."))
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
            } else {
                LiquidFlujoLeyenda(espacioH: LiquidSpace.s150, espacioV: LiquidSpace.s150) {
                    ForEach(picked) { metric in
                        LiquidChipSeleccion(
                            nombre: metric.canonicalTitle,
                            tono: MetricIdentity.hue(for: metric),
                            a11yQuitar: String(localized: "Remove \(metric.canonicalTitle)")) {
                                drop(metric)
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
    }

    /// Puente entre el índice del selector Liquid y la ventana activa.
    private var rangeIndex: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { indice in range = ExploreRange.allCases[indice] })
    }

    /// Abre la hoja de selección. Siempre pulsable: ahí se añade Y se quita, así que sigue alcanzable
    /// con las cuatro métricas puestas.
    private var pickerButton: some View {
        let atCeiling = picked.count >= ceiling
        return Button {
            showPicker = true
        } label: {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: "plus")
                    .font(LiquidType.iconSF(size: 14))
                Text(atCeiling ? String(localized: "Max 4") : String(localized: "Add metric"))
                    .font(LiquidType.boton)
            }
            .foregroundStyle(atCeiling ? LiquidColor.tinta500 : LiquidColor.tinta900)
            .padding(.horizontal, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s150)
        }
        .buttonStyle(.liquidPress)
        .liquidGlass(.pastillaSolida)
        .fixedSize()
        .accessibilityLabel(String(localized: "Add or remove metrics"))
    }

    private func drop(_ metric: MetricDescriptor) {
        withAnimation(LiquidMotion.selector) {
            picked.removeAll { $0 == metric }
        }
    }

    // MARK: Bloques de lectura

    private var overlayBlock: some View {
        // A la pieza se le pasan TODAS las elegidas, no solo las que tienen filas: así resuelve el
        // estado honesto (con 2+ elegidas pero menos de 2 con lecturas cae en «sin datos en la
        // ventana», nunca en la copia de «conecta Apple Health»). El conteo del rótulo sí es el de
        // las que se dibujan.
        let drawable = windowed.filter { !$0.window.isEmpty }.count
        return CompareBlock(title: String(localized: "Overlay"),
                            trailing: String(format: String(localized: "compare.overlay.count",
                                                            defaultValue: "%lld series"), drawable)) {
            CompareOverlay(series: windowed, widened: someSeriesWidened, phrase: range.phrase)
        }
    }

    private var correlationBlock: some View {
        let found = pairResults(windowed)
        let trailing = found.isEmpty ? nil
            : String(format: String(localized: "compare.pairs.count", defaultValue: "%lld pairs"),
                     found.count)
        return CompareBlock(title: String(localized: "How They Move Together"), trailing: trailing) {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text(String(localized: "Pearson r · \(range.phrase)"))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)

                // Asociación, no causa: que dos curvas se muevan juntas no dice que una empuje a la otra.
                LiquidNotaLine(String(localized: "Association, not cause: moving together isn't one driving the other."))

                if found.isEmpty {
                    CompareWell(text: String(localized: "Not enough overlapping days between these metrics in \(range.phrase). Widen the range."))
                } else {
                    ForEach(found) { pair in
                        ComparePairCard(pair: pair, stacked: dynamicTypeSize.isAccessibilitySize)
                    }
                }
            }
        }
    }

    // MARK: Ventaneo

    private var pickedKey: String {
        picked.map(\.id).sorted().joined(separator: "|")
    }

    private func parsed(_ full: [(day: String, value: Double)]) -> MetricWindowMath.Parsed {
        full.map { (day: $0.day, date: compareDate($0.day), value: $0.value) }
    }

    private func rewindow() {
        windowed = picked.map { metric in
            let completa = history[metric.id] ?? []
            let recorte = MetricWindowMath.make(parsed(completa), selected: range)
            return OverlaidMetric(descriptor: metric,
                                  tone: MetricIdentity.hue(for: metric),
                                  window: recorte.rows)
        }
    }

    /// Cierto si alguna serie elegida tuvo que salirse de la ventana pedida para encontrar puntos.
    private var someSeriesWidened: Bool {
        for metric in picked {
            let completa = history[metric.id] ?? []
            if completa.isEmpty { continue }
            if MetricWindowMath.effectiveRange(parsed(completa), selected: range) != range { return true }
        }
        return false
    }

    /// «N lecturas · <ventana>», con aviso cuando algo se ensanchó. El conteo de series NO va aquí:
    /// vive en el rótulo del bloque de superposición.
    private var readingsCaption: String {
        let total = windowed.reduce(0) { $0 + $1.window.count }
        let unit = total == 1 ? String(localized: "reading") : String(localized: "readings")
        let base = String(format: String(localized: "compare.caption.readings",
                                         defaultValue: "%1$lld %2$@ · %3$@"),
                          total, unit, range.phrase)
        guard someSeriesWidened else { return base }
        return String(format: String(localized: "compare.caption.widened",
                                     defaultValue: "%1$@ · sparse widened"), base)
    }

    private var outOfWindowCopy: String {
        String(localized: "No data for these metrics in \(range.phrase). Widen the range or pick metrics you've logged.")
    }

    /// La copia de «conecta Apple Health» se reserva para cuando conectar SÍ es el arreglo — la misma
    /// frase que la pieza de la gráfica usa en su estado mínimo.
    private static let connectCopy = String(localized: "Compare needs at least two metrics with history. Connect Apple Health in Data Sources first.")

    /// Cierto, ya cargado, cuando NINGUNA métrica elegida tiene historia: el caso genuino de sin datos
    /// o sin permiso, distinto de «tiene historia, pero no en esta ventana».
    private var noHistoryAtAll: Bool {
        picked.allSatisfy { (history[$0.id] ?? []).isEmpty }
    }

    // MARK: Carga

    private func seedSelectionIfNeeded() async {
        guard picked.isEmpty else { return }
        var arranque = Self.openingKeys.compactMap { key in
            MetricCatalog.all.first { $0.key == key }
        }
        if arranque.isEmpty {
            arranque = Array(MetricCatalog.all.prefix(2))
        }
        picked = Array(arranque.prefix(ceiling))
    }

    /// Trae (y guarda) la historia completa de cada métrica elegida que aún no se haya leído. Dos
    /// caminos: los campos del tablero salen de `repo.displayDays` por el resolvedor COMPARTIDO — el
    /// mismo que usa el Explorador, así una clave da el mismo número en ambas pantallas — y el resto
    /// cae a `series()`. Se guarda la historia entera para que la ventana pueda ensancharse sola.
    private func loadMissingSeries() async {
        let pendientes = picked.filter { history[$0.id] == nil }
        var delTablero: [(id: String, series: [(day: String, value: Double)])] = []
        var porConsultar: [MetricDescriptor] = []
        for metric in pendientes {
            let delTableroSerie = MetricSeriesResolver.dashboardSeries(metric.key, from: repo.displayDays)
            if let delTableroSerie {
                delTablero.append((metric.id, delTableroSerie))
            } else {
                porConsultar.append(metric)
            }
        }
        let consultadas = await withTaskGroup(of: (String, [(day: String, value: Double)]).self) { group in
            for metric in porConsultar {
                group.addTask { (metric.id, await repo.series(key: metric.key, source: metric.source)) }
            }
            var acumulado: [(id: String, series: [(day: String, value: Double)])] = []
            for await (id, series) in group { acumulado.append((id, series)) }
            return acumulado
        }
        for (id, series) in delTablero { history[id] = series }
        for (id, series) in consultadas { history[id] = series }
        firstReadDone = true
    }

    // MARK: Pares

    /// Lo que lee el `body`: la corrida memoizada si las entradas coinciden, y si no, una corrida de
    /// un solo cuadro (sin mutar estado a media construcción).
    private func pairResults(_ series: [OverlaidMetric]) -> [PairedMetrics] {
        ComparePairing.fingerprint(series) == pairFingerprint ? pairs : ComparePairing.immediate(series)
    }

    /// Rehace la caché FUERA del hilo principal, y solo si las entradas cambiaron: la corrida se
    /// despacha sobre una foto Sendable `(id, filas)` — nunca sobre las series, que cargan un `Color` —
    /// y se re-adjunta ya de vuelta en el hilo principal. Una foto vieja que llegue tarde se descarta.
    private func refreshPairs(_ series: [OverlaidMetric]) {
        let huella = ComparePairing.fingerprint(series)
        guard huella != pairFingerprint else { return }
        pairFingerprint = huella
        let dibujables = series.filter { !$0.window.isEmpty }
        let foto = dibujables.map { (id: $0.id, puntos: $0.window) }
        Task {
            let scans = await Task.detached(priority: .userInitiated) {
                ComparePairing.scan(foto)
            }.value
            guard pairFingerprint == huella else { return }
            pairs = ComparePairing.attach(scans, to: dibujables)
        }
    }
}

// MARK: - Piezas de la pantalla

private struct CompareHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(String(localized: "Compare"))
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Overlay signals, draw conclusions."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Un bloque titulado: rótulo quieto en la voz de franja (inset, no a sangre — las secciones de
/// Comparar llevan controles), un conteo opcional a la derecha, y el contenido.
private struct CompareBlock<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(LiquidType.franja)
                    .tracking(LiquidType.franjaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityAddTraits(.isHeader)
                if let trailing {
                    Spacer(minLength: LiquidSpace.s200)
                    Text(verbatim: trailing)
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
    }
}

/// Un estado vacío honesto, sobre papel opaco (dentro de una hoja de vidrio, nunca vidrio sobre vidrio).
private struct CompareWell: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .liquidTarjetaSeccion()
    }
}

/// Una correlación en su propia tarjeta de papel: dos gotas de identidad, el par en nombres canónicos,
/// el coeficiente en tinta neutra (el signo lo carga el «−», nunca el color: una correlación negativa
/// no es una alarma), la conclusión y el pie de solape. En tamaños de accesibilidad la cabecera se
/// apila en vez de correr título contra valor en la misma línea.
private struct ComparePairCard: View {
    let pair: PairedMetrics
    let stacked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            if stacked {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    HStack(spacing: LiquidSpace.s250) {
                        swatches
                        title
                    }
                    coefficient
                }
            } else {
                HStack(spacing: LiquidSpace.s250) {
                    swatches
                    title
                    Spacer(minLength: LiquidSpace.s200)
                    coefficient
                }
            }

            Text(verbatim: CompareWording.insight(pair))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false,
                           vertical: true)

            Text(verbatim: CompareWording.footer(pair))
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .liquidTarjetaSeccion()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: CompareWording.spoken(pair)))
    }

    private var swatches: some View {
        HStack(spacing: LiquidSpace.s075) {
            Circle().fill(pair.a.tone).frame(width: 8, height: 8)
            Circle().fill(pair.b.tone).frame(width: 8, height: 8)
        }
        .accessibilityHidden(true)
    }

    private var title: some View {
        Text(verbatim: "\(pair.a.descriptor.canonicalTitle) ↔ \(pair.b.descriptor.canonicalTitle)")
            .font(LiquidType.tituloFila)
            .foregroundStyle(LiquidColor.tinta900)
    }

    /// El dato es dato por TAMAÑO (valorM, dígitos monoespaciados), no por tono.
    private var coefficient: some View {
        Text(verbatim: CompareWording.signedR(pair.r))
            .font(LiquidType.valorM)
            .monospacedDigit()
            .foregroundStyle(LiquidColor.tinta900)
    }
}

// MARK: - La superposición (aislada para que el scrub re-renderice solo aquí)

/// La gráfica normalizada con su lectura viva. Es dueña del día bajo el dedo, así que un tic del
/// scrub re-renderiza solo este bloque y las tarjetas de correlación se quedan quietas; y construye
/// los datos por serie UNA vez por construcción, no por tic. El tooltip es una pieza hermana, fija
/// arriba del plot (la gráfica no expone la x del cursor ni formatea fechas).
private struct CompareOverlay: View {
    /// TODAS las elegidas: la pieza necesita saber cuántas se pidieron para escoger su estado vacío.
    let series: [OverlaidMetric]
    let widened: Bool
    let phrase: String

    /// Las que de verdad se dibujan. El tooltip y la etiqueta de a11y siguen a la leyenda, que la
    /// pieza arma con estas.
    private var drawable: [OverlaidMetric] { series.filter { !$0.window.isEmpty } }

    private let liquidSeries: [LiquidGraficaSuperpuesta.Serie]
    private let descriptorById: [String: MetricDescriptor]
    private let dateRange: ClosedRange<Date>

    /// El día bajo el dedo (nil en reposo). Lo publica la gráfica; jamás un `DragGesture` propio.
    @State private var scrubDay: Date?

    /// Comparar respeta el interruptor imperial igual que los detalles: peso (kg → lb) y temperatura
    /// de piel (°C → °F) se re-rotulan, el resto no depende del sistema. Solo convierte lo MOSTRADO;
    /// la normalización min–max es de forma y nunca se enseña como número, así que se queda en SI.
    @AppStorage(UnitPrefs.systemKey) private var storedUnitSystem = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var storedTemperature = ""

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: storedUnitSystem) ?? .metric
    }

    private var temperature: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: storedTemperature)
    }

    // Las fechas de la gráfica están ancladas a UTC, así que ambos formateadores rotulan en UTC para
    // no correrse de día, con el locale vivo para los nombres de mes y de día.
    private static let axisFormatter = utcFormatter(template: "dMMM")
    private static let tooltipFormatter = utcFormatter(template: "EEEdMMMyyyy")

    private static func utcFormatter(template: String) -> DateFormatter {
        let formateador = DateFormatter()
        formateador.locale = .autoupdatingCurrent
        formateador.timeZone = TimeZone(secondsFromGMT: 0)
        formateador.setLocalizedDateFormatFromTemplate(template)
        return formateador
    }

    init(series: [OverlaidMetric], widened: Bool, phrase: String) {
        self.series = series
        self.widened = widened
        self.phrase = phrase
        self.liquidSeries = series.map { s in
            LiquidGraficaSuperpuesta.Serie(
                id: s.id,
                nombre: s.descriptor.canonicalTitle,
                color: s.tone,
                puntos: s.window.compactMap { row in
                    compareDate(row.day).map { (fecha: $0, valor: row.value) }
                },
                // Min–max de la ventana, por serie. Nunca una banda fija de niveles: eso metería una
                // cuarta escala en un plot que ya comparte tres.
                dominio: s.lowest...s.highest)
        }
        self.descriptorById = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0.descriptor) })
        let fechas = series.flatMap { $0.window.compactMap { compareDate($0.day) } }
        let desde = fechas.min() ?? Date()
        let hasta = fechas.max() ?? Date()
        self.dateRange = desde...hasta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(verbatim: methodCaption)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false,
                           vertical: true)
            ZStack(alignment: .top) {
                LiquidGraficaSuperpuesta(
                    series: liquidSeries,
                    rango: dateRange,
                    seleccion: $scrubDay,
                    formatoValor: { serie, valor in
                        descriptorById[serie.id]?
                            .format(valor, system: unitSystem, temperature: temperature) ?? ""
                    },
                    a11yLabel: spokenLabel,
                    formatoFechaEje: { Self.axisFormatter.string(from: $0) },
                    rotulosRejilla: (bajo: String(localized: "low"),
                                     medio: String(localized: "mid"),
                                     alto: String(localized: "high")),
                    mensajeMinimo: String(localized: "Compare needs at least two metrics with history. Connect Apple Health in Data Sources first."),
                    mensajeSinLecturas: emptyWindowCopy)
                if let scrubDay {
                    LiquidTooltipMulti(fecha: Self.tooltipFormatter.string(from: scrubDay),
                                       filas: tooltipRows(on: scrubDay))
                        .padding(.top, LiquidSpace.s200)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var methodCaption: String {
        guard widened else {
            return String(format: String(localized: "compare.overlay.caption",
                                         defaultValue: "Each line min–max normalized within %1$@ · drag to read values"),
                          phrase)
        }
        return String(format: String(localized: "compare.overlay.caption.widened",
                                     defaultValue: "Min–max normalized · sparse series widened past %1$@ · drag to read values"),
                      phrase)
    }

    private var emptyWindowCopy: String {
        String(localized: "No data for these metrics in \(phrase). Widen the range or pick metrics you've logged.")
    }

    private var spokenLabel: String {
        String(format: String(localized: "compare.chart.a11y", defaultValue: "Comparing %1$@"),
               drawable.map(\.descriptor.canonicalTitle).joined(separator: ", "))
    }

    /// Una fila por serie dibujada, en el orden de la leyenda: el valor REAL de ese día, o nada.
    private func tooltipRows(on date: Date) -> [LiquidTooltipMulti.Fila] {
        let day = Repository.utcDayKey(date)
        return drawable.map { s in
            let valor = s.reading(on: day).map {
                s.descriptor.format($0, system: unitSystem, temperature: temperature)
            }
            return LiquidTooltipMulti.Fila(id: s.id,
                                           color: s.tone,
                                           nombre: s.descriptor.canonicalTitle,
                                           valor: valor)
        }
    }
}

// MARK: - Hoja de selección de métricas

/// El «añadir / quitar métricas», como cascarón de hoja Liquid. Sustituye al menú de catálogo, que
/// reiniciaba su scroll en cada re-render del padre. Va agrupado por categoría; cada fila es un
/// interruptor con palomita. Al tope de 4 las filas nuevas se apagan, pero las ya elegidas siguen
/// pulsables para poder cambiarlas. Se cierra arrastrando.
private struct CompareMetricPicker: View {
    @Binding var picked: [MetricDescriptor]
    let ceiling: Int

    /// Neutro: el selector tampoco tiene un sujeto único, así que su plasta es un gris cálido quieto.
    private let tono = LiquidColor.tinta500

    var body: some View {
        LiquidMetricSheet(tono: tono, detent: .porContenido) {
            LiquidSheetHeader(icono: nil,
                              titulo: String(localized: "Metrics"),
                              tono: tono,
                              numeral: nil)
            LiquidNotaLine(String(localized: "Pick 2–4 to overlay."))
            ForEach(MetricCatalog.categories, id: \.self) { category in
                let delGrupo = MetricCatalog.inCategory(category)
                if !delGrupo.isEmpty {
                    group(category, delGrupo)
                }
            }
        }
    }

    private func group(_ category: String, _ metrics: [MetricDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(MetricCatalog.localizedCategory(category))
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            VStack(spacing: .zero) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { posicion, metric in
                    row(metric, last: posicion == metrics.count - 1)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
    }

    private func row(_ metric: MetricDescriptor, last: Bool) -> some View {
        let marcada = picked.contains(metric)
        let blocked = !marcada && picked.count >= ceiling
        return LiquidListRow(
            title: metric.canonicalTitle,
            // El mismo subtítulo de procedencia que lleva el catálogo del Explorador, en el
            // vocabulario cerrado: una métrica nombra su origen igual en los dos instrumentos.
            subtitle: originVocabulary(metric),
            tone: MetricIdentity.hue(for: metric),
            seleccionado: marcada,
            deshabilitado: blocked,
            // Por qué la fila está inerte: si no, VoiceOver lee una fila apagada sin decir la razón.
            a11yHint: blocked ? String(localized: "At most 4 metrics.") : nil,
            divider: !last) {
                withAnimation(LiquidMotion.selector) {
                    if marcada {
                        picked.removeAll { $0 == metric }
                    } else if picked.count < ceiling {
                        picked.append(metric)
                    }
                }
            }
    }
}

// MARK: - Canvas

#if DEBUG
@MainActor
private func compareCanvasRepo() -> Repository {
    let repositorio = Repository(deviceId: "preview")
    repositorio.setDashboard()
    return repositorio
}

#Preview("Compare") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CompareView().environmentObject(compareCanvasRepo())
    }
}
#endif
