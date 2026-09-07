import SwiftUI
// MARK: - La voz tipográfica
//   SF Pro. Conviven aquí dos familias de fichas, y la diferencia entre ellas es deliberada:
//   · Las de LECTURA se anclan a un estilo nativo (`Font.system(.subheadline)`), así que crecen y
//     encogen con el tamaño de texto que la persona eligió en iOS.
//   · Las NUMÉRICAS y las de glifo se declaran en puntos FIJOS. Viven dentro de un dibujo —anillos,
//     diales, marcas de una gráfica— donde reflowear con Dynamic Type rompería la geometría.
//
// Todo valor vivo se pinta con dígitos monoespaciados, para que el número no baile al cambiar.
public enum StrandFont { // fichas de tipo: nadie escribe `.font(.system(size:))` a mano
    // MARK: Escala de lectura — crece con Dynamic Type
    /// Relative to `.title`, 28pt bold at the default size.
    public static let title1 = Font.system(.title, weight: .bold)
    /// Relative to `.headline`, 17pt semibold at the default size.
    public static let headline = Font.system(.headline)
    /// Relative to `.subheadline`, 15pt at the default size.
    public static let body = Font.system(.subheadline)
    /// Relative to `.footnote`, 13pt at the default size.
    public static let subhead = Font.system(.footnote)
    /// Relative to `.caption`, 12pt at the default size.
    public static let caption = Font.system(.caption)
    /// Relative to `.caption2`, 11pt at the default size.
    public static let footnote = Font.system(.caption2)
    /// La unidad chica que sigue a un valor (ms / bpm / %). Un escalón por encima de `footnote` para
    /// que se lea como parte del dato y no como decorado.
    public static let unit = Font.system(.footnote)
    /// Voz de VERSALITAS, de uso escaso. Acompáñala con `.tracking(overlineTracking)` — o llama a
    /// `strandOverline()`, que ya trae las dos cosas.
    public static let overline = Font.system(.caption2, weight: .semibold)
    /// SF Mono — vistas crudas/de bitácora, tabulares por naturaleza.
    public static let mono = Font.system(.footnote, design: .monospaced)
    /// Leyenda con dígitos monoespaciados: valores vivos chicos (chips, sparklines).
    public static let captionNumber = Font.system(.caption, weight: .medium).monospacedDigit()
    /// Espaciado de letra que `strandOverline()` aplica sobre `overline`.
    public static let overlineTracking: CGFloat = 0.8

    // MARK: Numerales de tamaño fijo — dígitos tabulares
    /// Un numeral de dígitos monoespaciados a un tamaño arbitrario, para valores vivos.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default).monospacedDigit() }
    /// SF Mono a un tamaño arbitrario.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    // MARK: Tamaños de glifo SF Symbol
    //
    // Escalones fijos que absorbieron los `.font(.system(size:))` que las pantallas inventaban para
    // sus íconos. Son cromo pegado a texto que no escala, o geometría: no se mueven con Dynamic Type.

    /// Tamaño semántico de un glifo. En un call site nunca va un `CGFloat` crudo.
    public enum GlyphSize: CGFloat {
        /// Chevrones de navegación, marcas de despliegue (absorbe 10–14).
        case chevron = 12
        /// Ícono junto a texto de lectura (absorbe 14–17).
        case inline = 15
        /// Ícono guía de una fila o un encabezado (absorbe 17–22).
        case lead = 18
        /// Glifo de estado vacío (absorbe 28–40).
        case empty = 34
    }

    /// Un SF Symbol a un tamaño semántico. FIJO: no escala con Dynamic Type. `.regular` iguala el
    /// default nativo de `.font(.system(size:))`, así que migrar un ícono con tamaño suelto —el caso
    /// común— no le cambia el peso salvo que el call site lo pida.
    public static func glyph(_ size: GlyphSize, weight: Font.Weight = .regular) -> Font { .system(size: size.rawValue, weight: weight) }
}

// MARK: - Sobrelínea
//
// La sobrelínea es una receta, no una suma de modificadores sueltos: un `ViewModifier` la guarda
// entera para que ninguna pantalla la arme a medias (sin tracking, o con otra tinta).
private struct VozDeSobrelinea: ViewModifier {
    func body(content: Content) -> some View {
        content.textCase(.uppercase)
            .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(InstrumentoTheme.base.inkSecondary)
    }
}

public extension Text {
    /// La viste de sobrelínea: VERSALITAS, semibold, con tracking, en tinta secundaria.
    func strandOverline() -> some View { modifier(VozDeSobrelinea()) }
}

public extension View {
    /// Atajo: arma la etiqueta de sobrelínea directo desde una cadena.
    static func strandOverline(_ string: String) -> some View { Text(string).strandOverline() }
}

#if DEBUG
/// Una fila de la muestra: cómo se llama la ficha y con qué fuente se pinta.
private struct MuestraDeVoz: Identifiable {
    let id = UUID()
    let rotulo: String
    let voz: Font
    let atenuada: Bool
}

private let muestrario: [MuestraDeVoz] = [
    .init(rotulo: "Title1", voz: StrandFont.title1, atenuada: false),
    .init(rotulo: "Headline", voz: StrandFont.headline, atenuada: false),
    .init(rotulo: "Body", voz: StrandFont.body, atenuada: false),
    .init(rotulo: "Subhead", voz: StrandFont.subhead, atenuada: true),
    .init(rotulo: "Caption", voz: StrandFont.caption, atenuada: true),
    .init(rotulo: "Footnote", voz: StrandFont.footnote, atenuada: true),
    .init(rotulo: "Mono 0x1F 0x0A crc=91b2", voz: StrandFont.mono, atenuada: true),
]

/// Un dato con su unidad: rótulo, numeral y unidad, cada uno con su ficha, para verlas juntas.
private struct MuestraDeDato: View {
    /// Aire entre rótulo, numeral y unidad — cifra de muestrario, no ficha del sistema.
    private let aireEntrePiezas: CGFloat = 4

    private var piezas: [(String, Font, Color)] {
        [("HRV", StrandFont.caption, InstrumentoTheme.base.inkSecondary),
         ("62", StrandFont.captionNumber, InstrumentoTheme.base.ink),
         ("ms", StrandFont.unit, InstrumentoTheme.base.inkTertiary)]
    }

    var body: some View {
        HStack(spacing: aireEntrePiezas) {
            ForEach(piezas, id: \.0) { texto, voz, tinta in
                Text(texto).font(voz).foregroundStyle(tinta)
            }
        }
    }
}

#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(muestrario) { fila in
                Text(fila.rotulo).font(fila.voz)
                    .foregroundStyle(fila.atenuada ? InstrumentoTheme.base.inkSecondary : InstrumentoTheme.base.ink)
            }
            Text(verbatim: "Overline").strandOverline()
            MuestraDeDato()
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 480, height: 520)
    .background(InstrumentoTheme.base.paper).preferredColorScheme(.light)
}
#endif
