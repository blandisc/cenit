// ensenanza: ajustes.ayuda
#if os(iOS)
import SwiftUI
import CenitDesign
import CenitEnsenanza
import StrandAnalytics

// MARK: - «Cómo funciona Cénit» (épico FER-428 · L2/FER-435, D7 = A+B)
//
// La única puerta para volver a aprender: una LISTA DE LECTURA, no un menú. Cinco secciones
// (Hoy · Tendencias · Entrenar · Ajustes · En tu iPhone y tu reloj) leídas del registro
// `CenitEnsenanza` — la pantalla no inventa contenido: por funcionalidad, nombre · para qué ·
// dónde vive, la nota «Necesita Apple Watch» cuando `requiere` incluye `.watch` (se lista, nunca se
// esconde), cada `gestoConBoton` como «gesto · botón», y la PUERTA a su pieza cuando ya existe
// (taller, manuales, hoja del guardián, el acta). Solo la puerta es tocable. Al pie de cada
// pestaña, «Volver a ver los consejos» (`EnsenanzaGeneracion.reiniciar`). Nunca un modal.
//
// Hoja hermana de `SupportView` (mismo header, márgenes `s550`, `LiquidSheetFondo`, tarjetas
// opacas: en hoja no hay vidrio-sobre-vidrio). Trae su propio «Listo»: la abren Ajustes
// (`presentedSheet = .ayuda`) y el «?» de las cuatro pestañas (`AyudaBoton`, desplazada a su
// sección con `ScrollViewReader`).

struct AyudaScreen: View {
    /// Sección a la que abre desplazada (el «?» de cada pestaña); `nil` = desde arriba (Ajustes).
    var inicial: Pestana? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var showDecide = false
    @State private var showContexto = false
    @State private var showTaller = false
    /// Pestañas cuyos consejos ya se pidió volver a ver en esta apertura — el pie lo confirma.
    @State private var reiniciadas: Set<Pestana> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    header
                    ForEach(Pestana.allCases, id: \.self) { pestana in
                        seccion(pestana).id(pestana)
                    }
                }
                .padding(.horizontal, LiquidSpace.s550)
                .padding(.top, LiquidSpace.s550)
                .padding(.bottom, LiquidSpace.s800)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let inicial { proxy.scrollTo(inicial, anchor: .top) }
            }
        }
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) { dismiss() }
                    .foregroundStyle(LiquidColor.tinta900)
            }
        }
        // `entrenar.taller` → el taller («Lo que Cénit sabe hacer» + «Palabras del gym»), empujado
        // en el stack de esta hoja, como lo empujaba el «?» del hub de Entrenar.
        .navigationDestination(isPresented: $showTaller) { WorkshopTricksScreen() }
        // `hoy.manuales` → los dos manuales, en la misma hoja neutra con que los abre Hoy.
        .sheet(isPresented: $showDecide) {
            LiquidMetricSheet(tono: LiquidColor.tinta700, detent: .porContenido) { HojaDecideTuDia() }
        }
        .sheet(isPresented: $showContexto) {
            LiquidMetricSheet(tono: LiquidColor.tinta700, detent: .porContenido) { HojaContexto() }
        }
    }

    // MARK: - Header (hermano de SupportView)

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidOverline(String(localized: "Help"))
            Text("How Cénit works")
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "ayuda.subtitulo",
                        defaultValue: "Everything the app teaches, by tab, to come back to whenever you want. And to see the tips again."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, LiquidSpace.s300)
    }

    // MARK: - Sección (una por pestaña, en el orden del registro)

    private func seccion(_ pestana: Pestana) -> some View {
        let funcionalidades = Registro.por(pestana)
        let titulo = Self.titulo(pestana)
        return VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader(LocalizedStringKey(titulo)) {
                Text(String(localized: "ayuda.seccion.conteo", defaultValue: "\(funcionalidades.count) features"))
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
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
/// puerta(s). La fila NO es un botón; solo la puerta lo es (44 pt). Misma geometría que
/// `LiquidListRow` (vertical `s300`, horizontal `s100`, divisor 0.5 tinta10) para que Ayuda,
/// Novedades y Ajustes lean como una sola familia. Sin `lineLimit`: a tallas AX todo apila.
struct AyudaFila: View {
    let funcionalidad: Funcionalidad
    var puertas: [AyudaPuerta] = []
    var divider = true

    /// Chevron de la puerta — el mismo que el de la fila de lista y la tarjeta de una vez.
    private static let chevron: CGFloat = 12  // token-exempt(paridad): chevron de LiquidListRow / LiquidUnaVez (no público)

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
                Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)  // token-exempt(paridad): paridad divisor LiquidListRow (no público)
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
                    LiquidIcon(.chevron, size: Self.chevron, color: LiquidColor.verdeProfundo)
                }
                .frame(minHeight: LiquidControl.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        }
    }
}
#endif
