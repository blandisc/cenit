import SwiftUI

// MARK: - EntrenarFilaCarga — la fila «Contexto · Carga» bajo el hilo (FER-488 · ola 1a)
//
// La segunda fila de la portada de Entrenar: debajo del hilo del veredicto (`EntrenarHilo`), una
// fila compacta y NEUTRA que nombra el contexto de carga y abre la Hoja de carga. Decisión del
// dueño 2026-09-15 («Cénit replanteada» §2 y §6): la carga NO vota (FER-336 pendiente), así que
// nunca puede parecer una segunda señal del oráculo — sin ratio, sin escala, sin color de bandera.
// Por eso `TrainingLoadStrip` (ratio numérico, escala de cápsulas, color de bandera) no sirve aquí.
//
// Anatomía: punto de identidad de carga (`verdeCarga`, 6 pt, solo con banda) · rótulo en
// versalitas («CONTEXTO · CARGA», `LiquidType.regla`, tinta/500) · la palabra de banda en tinta/900
// (o «Calibrando» en tinta/700) · «›» solo con acción. Papel pelón: sin vidrio, sin borde, sin
// pastilla — es una fila secundaria, no una tarjeta. El único color de dato es la IDENTIDAD de
// carga en el punto; la palabra va en tinta, y ese verde nunca es el del veredicto ni el de marca.
//
// Es la hermana del hilo: mismo ritmo de fila (`EntrenarMetrics.row`), mismo press
// (`EntrenarPressStyle`), misma familia SF `.footnote` para la palabra (`LiquidType.subtituloFila`,
// sucesor del `CenitFont.subhead` que el hilo usa) para que las dos filas se lean como UNA
// columna — y en peso regular, un escalón por debajo de la palabra del veredicto (semibold).

public struct EntrenarFilaCarga: View {

    /// Qué muestra la fila. La tercera rama de la decisión («nada → oculta») no es un estado: la
    /// app simplemente no monta la fila cuando no hay carga calculable ni esfuerzo registrado.
    public enum Estado: Sendable, Hashable {
        /// Hay ACWR: punto `verdeCarga` + la palabra de banda, que llega YA localizada desde la app
        /// (`ReadinessEngine.LoadBand.shortLabel`: «En equilibrio» · «Subiendo» · «Subiendo
        /// rápido» · «Bajando»).
        case banda(String)
        /// Esfuerzo registrado en la ventana pero todavía sin ACWR: sin punto, «Calibrando»
        /// (clave `Calibrating`, ya en el catálogo de la app) en tinta secundaria.
        case calibrando
    }

    /// Las tintas de la pieza, con nombre, para que la regla «la carga no vota» se pueda MEDIR
    /// (`EntrenarFilaCargaTests`) y no solo revisar a ojo.
    enum Tinta {
        /// Identidad de carga — el único color de dato. Nunca el verde de marca ni el del veredicto.
        static let punto = LiquidColor.verdeCarga
        static let rotulo = LiquidColor.tinta500
        static let palabra = LiquidColor.tinta900
        static let calibrando = LiquidColor.tinta700
        static let chevron = LiquidColor.tinta500
    }

    private let estado: Estado
    private let rotulo: LocalizedStringKey
    private let accessibilityLabel: String
    private let hint: LocalizedStringKey?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - estado: banda (con la palabra ya localizada) o calibrando.
    ///   - rotulo: el rótulo de contexto, como clave del catálogo de la app (`"Context · Load"` →
    ///     «Contexto · Carga»); la pieza lo pone en versalitas. El paquete no tiene catálogo propio
    ///     (localiza vía `.main`), así que la clave vive en la app — igual que `word`/`advice` del
    ///     hilo.
    ///   - accessibilityLabel: la etiqueta VoiceOver completa, ya localizada por la app («Carga de
    ///     entrenamiento, En equilibrio»). Sustituye a los textos visibles: un solo elemento.
    ///   - hint: a dónde lleva, para VoiceOver (`"Opens the load sheet"` → «Abre la Hoja de
    ///     carga»). Solo se anuncia cuando hay `action`.
    ///   - action: qué abre (la Hoja de carga). `nil` deja la fila informativa (sin «›» y sin toque).
    public init(estado: Estado, rotulo: LocalizedStringKey, accessibilityLabel: String,
                hint: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.estado = estado; self.rotulo = rotulo; self.accessibilityLabel = accessibilityLabel
        self.hint = hint; self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { fila }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(hint.map { Text($0) } ?? Text(""))
        } else {
            fila
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var fila: some View {
        HStack(spacing: LiquidSpace.s225) {
            if estado != .calibrando {
                EntrenarFamilyDot(Tinta.punto, size: EntrenarMetrics.familyDotCompact)
            }
            // Con Dynamic Type grande el rótulo y la palabra no caben lado a lado: en vez de
            // truncar la palabra —que es el contenido—, se apilan (mismo gesto que el hilo).
            // Lado a lado comparten baseline: las versalitas de 10 no flotan a media palabra.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s225) { rotuloTexto; palabra }
                VStack(alignment: .leading, spacing: LiquidSpace.s050) { rotuloTexto; palabra }
            }
            Spacer(minLength: LiquidSpace.s200)
            if action != nil {
                CenitIcon.disclosure.image
                    .font(CenitFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(Tinta.chevron)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
    }

    /// «CONTEXTO · CARGA»: la regla-kicker de módulo (10/600 +2.2, versalitas) — el nombre de la
    /// casa, no su contenido; por eso pesa menos que la palabra.
    private var rotuloTexto: some View {
        Text(rotulo)
            .liquidRegla()
            .foregroundStyle(Tinta.rotulo)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var palabra: some View {
        switch estado {
        case .banda(let banda):
            Text(verbatim: banda)
                .font(LiquidType.subtituloFila)
                .foregroundStyle(Tinta.palabra)
                .fixedSize(horizontal: false, vertical: true)
        case .calibrando:
            Text("Calibrating")
                .font(LiquidType.subtituloFila)
                .foregroundStyle(Tinta.calibrando)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("EntrenarFilaCarga · 3 estados") {
    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
        EntrenarFilaCarga(estado: .banda("En equilibrio"), rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, En equilibrio",
                          hint: "Opens the load sheet") {}
        EntrenarFilaCarga(estado: .banda("Subiendo rápido"), rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, Subiendo rápido",
                          hint: "Opens the load sheet") {}
        EntrenarFilaCarga(estado: .calibrando, rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, Calibrando",
                          hint: "Opens the load sheet") {}
        // Informativa: sin «›» y sin toque.
        EntrenarFilaCarga(estado: .banda("En equilibrio"), rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, En equilibrio")
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoAlto)
}

#Preview("EntrenarFilaCarga · bajo el hilo") {
    VStack(alignment: .leading, spacing: LiquidSpace.s050) {
        EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
        EntrenarFilaCarga(estado: .banda("En equilibrio"), rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, En equilibrio",
                          hint: "Opens the load sheet") {}
        EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet")
        EntrenarFilaCarga(estado: .calibrando, rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, Calibrando",
                          hint: "Opens the load sheet") {}
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoAlto)
}

#Preview("EntrenarFilaCarga · AX3") {
    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
        EntrenarFilaCarga(estado: .banda("Subiendo rápido"), rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, Subiendo rápido",
                          hint: "Opens the load sheet") {}
        EntrenarFilaCarga(estado: .calibrando, rotulo: "Context · Load",
                          accessibilityLabel: "Carga de entrenamiento, Calibrando",
                          hint: "Opens the load sheet") {}
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoAlto)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
