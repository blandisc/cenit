// ensenanza: ajustes.ayuda
#if os(iOS)
import SwiftUI
import CenitDesign
import CenitEnsenanza
import CenitAnalytics

// MARK: - «Cómo funciona Cénit» (épico FER-428 · L2/FER-435, D7 = A+B · rediseño índice)
//
// Antes: una sola LISTA DE LECTURA que apilaba las cinco secciones y sus 68 funcionalidades de
// corrido — una pared de texto sin jerarquía. Ahora un ÍNDICE + DETALLE (rediseño «híbrido»,
// dueño 2026-09-10): la puerta es un índice de cinco tarjetas de vidrio tintado (glifo del dock +
// nombre · conteo · una línea de qué encuentras), más un buscador que filtra sobre las 68 de un
// jalón. Tocas una sección y entras a SU lista (las mismas filas de lectura, `AyudaFila`, ahora
// solas y no ahogadas por las otras cuatro). El registro `CenitEnsenanza` sigue siendo la única
// fuente: la pantalla no inventa contenido (por funcionalidad: nombre · para qué · dónde vive, la
// nota «Necesita Apple Watch», cada `gestoConBoton`, y la PUERTA a su pieza cuando existe). Al pie
// de cada sección, «Volver a ver los consejos» (`EnsenanzaGeneracion.reiniciar`). Nunca un modal.
//
// Hoja hermana de `SupportView` (mismo header, `LiquidSheetFondo`, tarjetas opacas: en hoja no hay
// vidrio-sobre-vidrio). Trae su propio «Listo». La abren Ajustes (`presentedSheet = .ayuda`) y el
// «?» de las cuatro pestañas (`AyudaBoton`, que pasa `inicial` para entrar directo a esa sección).
// La pantalla es DUEÑA de su `NavigationStack` (path de `Pestana`): los dos call-sites ya no la
// envuelven.

struct AyudaScreen: View {
    /// Sección a la que entra directo (el «?» de cada pestaña); `nil` = se abre en el índice (Ajustes).
    var inicial: Pestana? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter
    /// El stack de esta hoja: vacío = índice; `[pestana]` = detalle de esa sección.
    @State private var path: [Pestana] = []
    /// Texto del buscador. No vacío ⇒ el índice se reemplaza por resultados filtrados de las 68.
    @State private var busqueda = ""
    @State private var showDecide = false
    @State private var showContexto = false
    @State private var showTaller = false
    /// Pestañas cuyos consejos ya se pidió volver a ver en esta apertura — el pie lo confirma.
    @State private var reiniciadas: Set<Pestana> = []

    var body: some View {
        NavigationStack(path: $path) {
            indice
                .navigationDestination(for: Pestana.self) { pestana in
                    seccionDetalle(pestana)
                }
        }
        // El «?» de una pestaña entra directo a su sección; Ajustes abre en el índice.
        .onAppear { if let inicial, path.isEmpty { path = [inicial] } }
        // Las tres puertas de contenido viven como HOJAS (no push): el `path` solo lleva `Pestana`,
        // así que el taller —que no es una pestaña— se presenta como sheet, no como destino tipado.
        .sheet(isPresented: $showTaller) {
            NavigationStack { WorkshopTricksScreen() }
                .environmentObject(repo)
                .environmentObject(tabRouter)
        }
        .sheet(isPresented: $showDecide) {
            LiquidMetricSheet(tono: LiquidColor.tinta700, detent: .porContenido) { HojaDecideTuDia() }
        }
        .sheet(isPresented: $showContexto) {
            LiquidMetricSheet(tono: LiquidColor.tinta700, detent: .porContenido) { HojaContexto() }
        }
    }

    // MARK: - Índice (la puerta: header + buscador + cinco tarjetas, o resultados)

    private var indice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                header
                buscador
                if busqueda.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(spacing: LiquidSpace.s250) {
                        ForEach(Pestana.allCases, id: \.self) { tarjetaSeccion($0) }
                    }
                } else {
                    resultados
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.pestanaContenidoTop)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .modifier(HojaChrome())
        .toolbar { ToolbarItem(placement: .confirmationAction) { botonListo } }
    }

    private var botonListo: some View {
        Button(String(localized: "Done")) { dismiss() }
            .foregroundStyle(LiquidColor.tinta900)
    }

    // MARK: - Header (hermano de SupportView)

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "Help"))
            Text("How Cénit works")
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "ayuda.subtitulo",
                        defaultValue: "Everything the app teaches, by tab. Open one, or search."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, LiquidSpace.s100)
    }

    // MARK: - Buscador

    private var buscador: some View {
        HStack(spacing: LiquidSpace.s150) {
            Image(systemName: "magnifyingglass")
                .font(LiquidType.iconSF(size: 15))
                .foregroundStyle(LiquidColor.tinta500)
            TextField(String(localized: "ayuda.buscar", defaultValue: "Search a feature"),
                      text: $busqueda)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta900)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            if !busqueda.isEmpty {
                Button {
                    busqueda = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LiquidType.iconSF(size: 15))
                        .foregroundStyle(LiquidColor.tinta500)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .liquidTarjetaSeccion(padding: LiquidSpace.s250)
    }

    // MARK: - Tarjeta de sección (una fila del índice → empuja el detalle)

    private func tarjetaSeccion(_ pestana: Pestana) -> some View {
        NavigationLink(value: pestana) {
            HStack(spacing: LiquidSpace.s300) {
                chipGlifo(pestana, glifo: 20, chip: 38)
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: Self.titulo(pestana))
                            .font(LiquidType.titulo)
                            .foregroundStyle(LiquidColor.tinta900)
                        Spacer(minLength: LiquidSpace.s200)
                        Text(String(localized: "ayuda.seccion.conteo",
                                    defaultValue: "\(Registro.por(pestana).count) features"))
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    Text(descriptor(pestana))
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LiquidIcon(.chevron, size: 12, color: LiquidColor.tinta500)
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Resultados de búsqueda (filtra las 68 de un jalón)

    @ViewBuilder private var resultados: some View {
        let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = Pestana.allCases
            .flatMap { Registro.por($0) }
            .filter { f in
                f.nombre.lowercased().contains(q)
                    || f.paraQue.lowercased().contains(q)
                    || f.dondeVive.lowercased().contains(q)
            }
        if hits.isEmpty {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text(String(localized: "ayuda.buscar.vacio", defaultValue: "Nothing matches that."))
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(String(localized: "ayuda.buscar.vacio.sub",
                            defaultValue: "Try another word, or browse by tab above."))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LiquidSpace.s300)
        } else {
            VStack(spacing: .zero) {
                ForEach(hits) { funcionalidad in
                    AyudaFila(funcionalidad: funcionalidad,
                              puertas: puertas(funcionalidad),
                              divider: funcionalidad.id != hits.last?.id)
                }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
    }

    // MARK: - Detalle de una sección (las filas de lectura, solas)

    private func seccionDetalle(_ pestana: Pestana) -> some View {
        let funcionalidades = Registro.por(pestana)
        let titulo = Self.titulo(pestana)
        return ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                seccionCabecera(pestana, titulo: titulo, conteo: funcionalidades.count)
                VStack(spacing: .zero) {
                    ForEach(funcionalidades) { funcionalidad in
                        AyudaFila(funcionalidad: funcionalidad,
                                  puertas: puertas(funcionalidad),
                                  divider: funcionalidad.id != funcionalidades.last?.id)
                    }
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
                // «En tu iPhone y tu reloj» no es una pestaña: no tiene consejos que volver a ver.
                if pestana != .transversal {
                    pie(pestana, titulo: titulo)
                }
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.pestanaContenidoTop)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .modifier(HojaChrome())
        .toolbar { ToolbarItem(placement: .confirmationAction) { botonListo } }
    }

    /// La cabecera del detalle: glifo tintado grande + nombre + conteo, para que la sección se
    /// reconozca de un vistazo (el mismo glifo y tinte de su tarjeta en el índice).
    private func seccionCabecera(_ pestana: Pestana, titulo: String, conteo: Int) -> some View {
        HStack(spacing: LiquidSpace.s300) {
            chipGlifo(pestana, glifo: 26, chip: 48)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: titulo)
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(String(localized: "ayuda.seccion.conteo", defaultValue: "\(conteo) features"))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Spacer(minLength: LiquidSpace.s200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, LiquidSpace.s300)
    }

    // MARK: - Glifo + tinte por sección (mismo mark del dock, tinte de la familia de acentos)

    @ViewBuilder private func glifo(_ pestana: Pestana, size: CGFloat) -> some View {
        switch pestana {
        case .hoy:
            DialTabGlyph(size: size, color: tinte(pestana))
        case .tendencias:
            TendenciasGlyph(color: tinte(pestana)).frame(width: size, height: size)
        case .entrenar:
            Image(systemName: "dumbbell.fill")
                .font(LiquidType.iconSF(size: size)).foregroundStyle(tinte(pestana))
        case .ajustes:
            Image(systemName: "slider.horizontal.3")
                .font(LiquidType.iconSF(size: size)).foregroundStyle(tinte(pestana))
        case .transversal:
            Image(systemName: "iphone")
                .font(LiquidType.iconSF(size: size)).foregroundStyle(tinte(pestana))
        }
    }

    private func chipGlifo(_ pestana: Pestana, glifo tamano: CGFloat, chip: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                .fill(tinte(pestana).opacity(CenitOpacity.tintFillStrong))
            glifo(pestana, size: tamano)
        }
        .frame(width: chip, height: chip)
    }

    private func tinte(_ pestana: Pestana) -> Color {
        switch pestana {
        case .hoy:         return LiquidColor.verdeOrbe
        case .tendencias:  return LiquidColor.cian
        case .entrenar:    return LiquidColor.ambar
        case .ajustes:     return LiquidColor.indigo
        case .transversal: return LiquidColor.azul
        }
    }

    /// La línea de «qué encuentras» de cada tarjeta del índice — la voz de marca, no una lista.
    private func descriptor(_ pestana: Pestana) -> String {
        switch pestana {
        case .hoy:
            return String(localized: "ayuda.desc.hoy",
                          defaultValue: "Your reading, the guardian, and what decides your day.")
        case .tendencias:
            return String(localized: "ayuda.desc.tendencias",
                          defaultValue: "Your ranges and where they head: rest, load, vitals.")
        case .entrenar:
            return String(localized: "ayuda.desc.entrenar",
                          defaultValue: "The plan that acts: today, your week, the live session.")
        case .ajustes:
            return String(localized: "ayuda.desc.ajustes",
                          defaultValue: "Sources, reminders, backup, and what the app teaches.")
        case .transversal:
            return String(localized: "ayuda.desc.transversal",
                          defaultValue: "No account, no cloud, and what the watch adds.")
        }
    }

    /// El nombre de la sección: las cuatro pestañas dicen lo mismo que el dock
    /// (`LiquidTabRotulos.cenit`, mismas claves); la quinta es propia.
    static func titulo(_ pestana: Pestana) -> String {
        switch pestana {
        case .hoy: return String(localized: "Today")
        case .tendencias: return String(localized: "Trends")
        case .entrenar: return String(localized: "Train")
        case .ajustes: return String(localized: "Settings")
        case .transversal:
            return String(localized: "ayuda.seccion.transversal", defaultValue: "On your iPhone and your watch")
        }
    }

    /// Pie de sección: «Volver a ver los consejos de {pestaña}» — sube la generación de la pestaña
    /// (`EnsenanzaGeneracion`), y en Hoy reactiva además los hints de gesto.
    private func pie(_ pestana: Pestana, titulo: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            LiquidGlassButton(
                String(localized: "ayuda.volverAVer", defaultValue: "See the \(titulo) tips again"),
                variant: .solida,
                systemImage: "arrow.counterclockwise"
            ) {
                EnsenanzaGeneracion.reiniciar(pestana)
                reiniciadas.insert(pestana)
            }
            if reiniciadas.contains(pestana) {
                Text(String(localized: "ayuda.volverAVer.listo", defaultValue: "Done. The \(titulo) tips will show again."))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, LiquidSpace.s300)
    }

    // MARK: - Puertas (tabla id → destino; solo estas)

    private func puertas(_ funcionalidad: Funcionalidad) -> [AyudaPuerta] {
        switch funcionalidad.id {
        case .hoyActa:
            // Con lectura de hoy: el acta. Sin lectura: «¿Qué decide tu día?». Lo decide Hoy al
            // recibir la bandera (`TabRouter.abrirActa`); aquí solo cambia el rótulo.
            let rotulo = hayVeredicto
                ? String(localized: "ayuda.puerta.lecturaHoy", defaultValue: "Your reading for today")
                : String(localized: "ayuda.puerta.decide", defaultValue: "What decides your day?")
            return [AyudaPuerta(id: "acta", rotulo: rotulo) {
                dismiss()
                tabRouter.abrirActa = true
                tabRouter.requested = .today
            }]
        case .hoyGuardian:
            // La hoja del guardián vive en `TodayView` (sus series las carga Hoy): misma ruta.
            return [AyudaPuerta(id: "guardian",
                                rotulo: String(localized: "ayuda.puerta.guardian", defaultValue: "The guardian's sheet")) {
                dismiss()
                tabRouter.abrirGuardian = true
                tabRouter.requested = .today
            }]
        case .hoyManuales:
            return [
                AyudaPuerta(id: "decide",
                            rotulo: String(localized: "ayuda.puerta.decide", defaultValue: "What decides your day?")) {
                    showDecide = true
                },
                AyudaPuerta(id: "contexto",
                            rotulo: String(localized: "ayuda.puerta.contexto", defaultValue: "Your context")) {
                    showContexto = true
                },
            ]
        case .entrenarTaller:
            return [AyudaPuerta(id: "taller",
                                rotulo: String(localized: "ayuda.puerta.taller", defaultValue: "Open the workshop")) {
                showTaller = true
            }]
        default:
            return []
        }
    }

    /// La misma puerta que Hoy exige para pronunciar la palabra (`TodayView.alimentarHoyTips`).
    private var hayVeredicto: Bool {
        guard let prep = repo.todayPreparedness else { return false }
        return prep.verdict != .lowSignal && prep.isNightAnchored
    }
}

// MARK: - Cromo de hoja (fondo + nav bar, compartido por el índice y el detalle)

private struct HojaChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { LiquidSheetFondo().ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
    }
}

// MARK: - Puerta

/// Una puerta de una fila de Ayuda: rótulo en voz de marca + chevron de fila; corre su acción.
struct AyudaPuerta: Identifiable {
    let id: String
    let rotulo: String
    let accion: () -> Void

    init(id: String, rotulo: String, accion: @escaping () -> Void) {
        self.id = id
        self.rotulo = rotulo
        self.accion = accion
    }
}

// MARK: - Fila de lectura (Ayuda y Novedades)

/// La fila de lectura: nombre · para qué · dónde vive · «Necesita Apple Watch» · gesto · botón ·
/// puerta(s). La fila NO es un botón (no es una `LiquidListRow`: no navega y lleva captions y
/// puertas debajo); solo la puerta lo es (44 pt). Ritmo de fila de lista (vertical `s300`,
/// horizontal `s100`) y `LiquidCapilar` como divisor, para que Ayuda, Novedades y Ajustes lean
/// como una sola familia. Sin `lineLimit`: a tallas AX todo apila.
struct AyudaFila: View {
    let funcionalidad: Funcionalidad
    var puertas: [AyudaPuerta] = []
    var divider = true

    /// Los pares gesto · botón del registro, ya resueltos contra el catálogo.
    private var gestos: [(gesto: String, boton: String)] {
        funcionalidad.piezas.compactMap { pieza -> (gesto: String, boton: String)? in
            guard case .gestoConBoton(let gesto, let boton) = pieza else { return nil }
            return (gesto: String(localized: String.LocalizationValue(gesto)),
                    boton: String(localized: String.LocalizationValue(boton)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            texto
            if !puertas.isEmpty {
                puertasFila
            }
        }
        .padding(.vertical, LiquidSpace.s300)
        .padding(.horizontal, LiquidSpace.s100)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if divider {
                LiquidCapilar(eje: .horizontal)
            }
        }
    }

    /// Nombre + para qué + dónde vive + notas: UNA parada de VoiceOver.
    private var texto: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: funcionalidad.nombre)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(verbatim: funcionalidad.paraQue)
                    .font(LiquidType.subtituloFila)
                    .foregroundStyle(LiquidColor.tinta700)
            }
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: funcionalidad.dondeVive)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                if funcionalidad.requiere.contains(.watch) {
                    HStack(spacing: LiquidSpace.s100) {
                        Image(systemName: "applewatch")
                            .font(LiquidType.iconSF(size: 10))
                        Text("Needs Apple Watch")
                            .font(LiquidType.captionLectura)
                    }
                    .foregroundStyle(LiquidColor.tinta500)
                }
                ForEach(Array(gestos.enumerated()), id: \.offset) { _, par in
                    (Text(verbatim: par.gesto).foregroundStyle(LiquidColor.tinta900)
                        + Text(verbatim: " · ").foregroundStyle(LiquidColor.tinta500)
                        + Text(verbatim: par.boton).foregroundStyle(LiquidColor.tinta700))
                        .font(LiquidType.captionLectura)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Hasta dos puertas lado a lado; apiladas cuando no caben (Dynamic Type grande).
    private var puertasFila: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LiquidSpace.s400) { botones }
            VStack(alignment: .leading, spacing: .zero) { botones }
        }
    }

    private var botones: some View {
        ForEach(puertas) { puerta in
            Button(action: puerta.accion) {
                HStack(spacing: LiquidSpace.s150) {
                    Text(verbatim: puerta.rotulo)
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.verdeProfundo)
                    LiquidIcon(.chevron, size: 12, color: LiquidColor.verdeProfundo)
                }
                .frame(minHeight: LiquidControl.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        }
    }
}
#endif
