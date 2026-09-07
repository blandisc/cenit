import SwiftUI
// MARK: - El color de un dato
//   Aquí vive TODA ficha de color con la que Cénit pinta una medición: las rampas de recuperación y
//   esfuerzo, las etapas de sueño, las zonas de frecuencia cardiaca, las palabras de estado y el
//   acento compartido. Los hex son exactos según el spec de diseño: nunca se aproximan.
//   Las fichas de superficie, tinta y filete que este enum también cargaba se retiraron cuando
//   «Instrumento diurno» quedó como único lenguaje de superficie: hoy las dueña `Instrumento.swift`.

// MARK: Vocabulario compartido

/// Las cuatro etapas en que se reparte una noche.
public enum SleepStage: String, Sendable, CaseIterable {
    case awake, light, deep, rem

    /// Rótulo visible. Se traduce contra el catálogo de la app anfitriona: el paquete no envía
    /// cadenas propias.
    public var label: String { String(localized: claveDeRotulo, bundle: .main) }

    /// La clave que la app traduce. Va en una propiedad aparte para que `label` quede en una línea y
    /// el `switch` exhaustivo siga obligando a nombrar cualquier etapa nueva.
    private var claveDeRotulo: String.LocalizationValue {
        switch self {
        case .awake: "Awake"
        case .light: "Light"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }
}

/// Los ÚNICOS escalones con los que se modula una ficha de color por opacidad. Antes de existir,
/// las pantallas inventaban unas quince opacidades mágicas entre tintes, trazos y estados
/// atenuados. `dim` coincide con `StrandPalette.disabledOpacity` (0.45).
public enum CenitOpacity {
    public static let tintFill: Double = 0.10       // chip/badge tint fill (absorbs 0.10–0.12)
    public static let tintFillStrong: Double = 0.14 // emphasized tint (absorbs 0.14–0.18)
    public static let strokeSoft: Double = 0.30     // soft tinted stroke (absorbs 0.28–0.40)
    public static let dim: Double = 0.45            // dimmed value (absorbs 0.40–0.52)
    public static let muted: Double = 0.60          // secondary over color (absorbs 0.55–0.70)
}

// MARK: - Las fichas

public enum StrandPalette { // color de dato: rampas, etapas, zonas y estados

    // MARK: Acento (cromo, no dato)

    public static let accent = Color(hex: "#18C98B")
    /// Shared dimming for a disabled/inactive section, so screens don't invent their own value.
    public static let disabledOpacity: Double = 0.45 // == CenitOpacity.dim, kept for older call sites

    // MARK: Recovery gradient — red (depleted) rising through gold to mint (peak)

    public static let recovery000 = Color(hex: "#FF4F73") // depleted
    public static let recovery030 = Color(hex: "#F5A623") // low
    public static let recovery055 = Color(hex: "#E8C24B") // moderate
    public static let recovery078 = Color(hex: "#18C98B") // primed
    public static let recovery100 = Color(hex: "#2FE6A8") // peak

    public static let recoveryStops: [Gradient.Stop] = zip(
        [recovery000, recovery030, recovery055, recovery078, recovery100],
        [0.00, 0.30, 0.55, 0.78, 1.00]
    ).map { Gradient.Stop(color: $0, location: $1) }
    public static let recoveryGradient = Gradient(stops: recoveryStops) // recovery-tinted views sample this

    // MARK: Strain ramp — ember rising through orange/rose to magenta

    public static let strain000 = Color(hex: "#E8B04B") // ramp floor, warm amber
    public static let strain033 = Color(hex: "#E8743B") // second stop, burnt orange
    public static let strain066 = Color(hex: "#E0476B") // third stop, deep rose
    public static let strain100 = Color(hex: "#C13AC1") // ramp ceiling, magenta

    public static let strainStops: [Gradient.Stop] = zip(
        [strain000, strain033, strain066, strain100],
        [0.00, 0.33, 0.66, 1.00]
    ).map { Gradient.Stop(color: $0, location: $1) }
    public static let strainGradient = Gradient(stops: strainStops) // strain-tinted views sample this

    // MARK: Sleep stages

    public static let sleepAwake = Color(hex: "#E0476B") // awake segments of the night
    public static let sleepLight = Color(hex: "#5C6FB1") // light-sleep segments
    public static let sleepDeep  = Color(hex: "#2C3A7A") // deep-sleep segments
    public static let sleepREM   = Color(hex: "#3E9E8C") // REM segments

    // MARK: HR zones

    public static let zone1 = Color(hex: "#4FA9C9") // easy
    public static let zone2 = Color(hex: "#5BD3A0") // fat-burn
    public static let zone3 = Color(hex: "#E8C24B") // aerobic
    public static let zone4 = Color(hex: "#E8743B") // threshold
    public static let zone5 = Color(hex: "#E0476B") // max effort

    public static let hrZones: [Color] = [zone1, zone1, zone2, zone3, zone4, zone5] // 1-indexed, [0] mirrors [1]

    // MARK: Status — never reused as a recovery color

    public static let statusPositive = Color(hex: "#18C98B") // "all good" verdict
    public static let statusWarning  = Color(hex: "#F5A623") // "pay attention" verdict
    public static let statusCritical = Color(hex: "#FF4F73") // "something's wrong" verdict

    // MARK: Per-metric accents

    public static let metricCyan   = Color(hex: "#2FC7FF") // identifies Apple Health bar charts
    public static let metricPurple = Color(hex: "#A879FF") // identifies HRV / strain-shaped data
    public static let metricAmber  = Color(hex: "#F5A623") // identifies calorie / moderate-load data
    public static let metricRose   = Color(hex: "#FF4F73") // identifies risk / high-strain / low-recovery data

    // MARK: Leer una rampa

    /// Interpola un juego de paradas ordenadas en una posición normalizada. Fuera de `0...1` se
    /// pega a la parada del extremo en vez de extrapolar.
    public static func sample(stops: [Gradient.Stop], at position: Double) -> Color { Rampa.leer(stops, en: position) }

    /// Lee la rampa de recuperación en un puntaje `0...100`.
    static func recoveryColor(_ score: Double) -> Color { Rampa.leer(recoveryStops, en: score / 100.0) }

    /// Lee la rampa de esfuerzo en la escala `0...21`.
    static func strainColor(_ strain: Double) -> Color { Rampa.leer(strainStops, en: strain / 21.0) }

    /// Mezcla lineal de dos colores en sRGB.
    static func interpolate(_ a: Color, _ b: Color, _ t: Double) -> Color { Rampa.mezclar(a, b, avance: t) }

    /// La palabra de estado de un puntaje de recuperación. Se traduce contra el catálogo de la app
    /// anfitriona: el paquete no envía cadenas propias.
    static func recoveryState(_ reading: Double) -> String {
        let key: String.LocalizationValue
        switch reading {
        case ..<25: key = "DEPLETED"
        case ..<50: key = "LOW"
        case ..<70: key = "MODERATE"
        case ..<88: key = "PRIMED"
        default:    key = "PEAK"
        }
        return String(localized: key, bundle: .main)
    }

    /// Color de una zona de FC (1...5, recortado a ese rango).
    static func hrZoneColor(_ zone: Int) -> Color { hrZones[Rampa.recortar(zone, entre: 1, y: 5)] }

    /// Color de una etapa de sueño.
    static func sleepStageColor(_ kind: SleepStage) -> Color {
        switch kind {
        case .awake: sleepAwake
        case .light: sleepLight
        case .deep:  sleepDeep
        case .rem:   sleepREM
        }
    }
}

// MARK: - Aritmética de rampa
//
// La única matemática de color del paquete, fuera de `StrandPalette` a propósito: leer una rampa es
// geometría, no una ficha, y así se prueba sin arrastrar la paleta entera.
private enum Rampa {

    /// Recorta un valor a un rango cerrado.
    static func recortar<T: Comparable>(_ valor: T, entre piso: T, y techo: T) -> T { Swift.min(Swift.max(valor, piso), techo) }

    /// El color de `paradas` en la posición normalizada `avance`.
    static func leer(_ paradas: [Gradient.Stop], en avance: Double) -> Color {
        guard paradas.count > 1 else { return paradas.first?.color ?? .clear }
        let t = recortar(avance, entre: 0, y: 1)

        // El par de paradas que encierra `t`; si ninguna lo hace (paradas fuera de orden), los
        // extremos de la rampa hacen de horquilla.
        let horquilla = zip(paradas, paradas.dropFirst()).first { par in
            t >= par.0.location && t <= par.1.location
        }
        let (baja, alta) = horquilla ?? (paradas[0], paradas[paradas.count - 1])
        let tramo = alta.location - baja.location
        return mezclar(baja.color, alta.color, avance: tramo > 0 ? (t - baja.location) / tramo : 0)
    }

    /// Mezcla lineal de dos colores en espacio sRGB.
    static func mezclar(_ desde: Color, _ hasta: Color, avance: Double) -> Color {
        let origen = desde.rgbaComponents, destino = hasta.rgbaComponents
        let t = recortar(avance, entre: 0, y: 1)
        func entre(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Color(.sRGB, red: entre(origen.r, destino.r), green: entre(origen.g, destino.g),
                     blue: entre(origen.b, destino.b), opacity: entre(origen.a, destino.a))
    }
}

// MARK: - Color: leer un hex, desglosar componentes

/// Cuarteto sRGB con cada canal en `0...1`.
typealias ComponentesSRGB = (r: Double, g: Double, b: Double, a: Double)

#if canImport(UIKit)
private typealias ColorDePlataforma = UIColor
#elseif canImport(AppKit)
private typealias ColorDePlataforma = NSColor
#endif

extension Color { // el puente entre un hex del spec, SwiftUI y el color de la plataforma

    /// Construye un color desde un hex del spec: `"#0B0D12"` (RGB de 6 dígitos) o `"AA0B0D12"`
    /// (RGBA de 8). Todo lo que no sea `[0-9A-Fa-f]` —el `#` de cabeza, espacios sueltos— se cae
    /// antes de leer. Una cadena ilegible no revienta: se lee como negro.
    public init(hex cadena: String) {
        let digitos = cadena.trimmingCharacters(in: .alphanumerics.inverted)
        let empaquetado = UInt64(digitos, radix: 16) ?? 0
        func canal(_ corrimiento: Int) -> Double { Double((empaquetado >> corrimiento) & 0xFF) / 255.0 }

        // Ocho dígitos traen alfa al final; cualquier otro largo se lee como los seis del caso
        // documentado, opaco.
        let conAlfa = digitos.count == 8
        self.init(.sRGB,
                  red: canal(conAlfa ? 24 : 16),
                  green: canal(conAlfa ? 16 : 8),
                  blue: canal(conAlfa ? 8 : 0),
                  opacity: conAlfa ? canal(0) : 1.0)
    }

    /// Resuelve el color a componentes sRGB en `0...1`, cruzando por el tipo de color nativo.
    var rgbaComponents: ComponentesSRGB {
        #if canImport(UIKit) || canImport(AppKit)
        return Color.desglosar(ColorDePlataforma(self))
        #else
        return (r: 0, g: 0, b: 0, a: 1)
        #endif
    }

    #if canImport(UIKit)
    /// UIKit ya entrega sRGB: se piden los cuatro canales de frente.
    fileprivate static func desglosar(_ nativo: UIColor) -> ComponentesSRGB {
        var r = CGFloat.zero, g = CGFloat.zero, b = CGFloat.zero, a = CGFloat.zero
        nativo.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
    #elseif canImport(AppKit)
    /// AppKit puede venir en otro espacio de color; se convierte a sRGB antes de leer los canales.
    fileprivate static func desglosar(_ nativo: NSColor) -> ComponentesSRGB {
        let enSRGB = nativo.usingColorSpace(.sRGB) ?? nativo
        var r = CGFloat.zero, g = CGFloat.zero, b = CGFloat.zero, a = CGFloat.zero
        enSRGB.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
    #endif
}

#if DEBUG
/// Las medidas del muestrario. Solo viven en el `#Preview`, pero con nombre igual que en producción.
private enum MedidasMuestrario {
    static let canto: CGFloat = 8
    static let altoDeTira: CGFloat = 32
    static let ladoDeMuestra = CGSize(width: 56, height: 44)
    static let vozDeMuestra: CGFloat = 9
}

/// Una tira de rampa: se ve dónde cae cada parada y cómo se mezclan entre ellas.
private struct TiraDeRampa: View {
    let titulo: String
    let rampa: Gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            RoundedRectangle(cornerRadius: MedidasMuestrario.canto)
                .fill(LinearGradient(gradient: rampa, startPoint: .leading, endPoint: .trailing))
                .frame(height: MedidasMuestrario.altoDeTira)
        }
    }
}

/// Una fila de muestras cuadradas con su rótulo debajo.
private struct FilaDeMuestras: View {
    let muestras: [(String, Color)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(muestras, id: \.0) { rotulo, tinta in muestra(rotulo, tinta) }
        }
    }

    private func muestra(_ rotulo: String, _ tinta: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: MedidasMuestrario.canto).fill(tinta)
                .frame(width: MedidasMuestrario.ladoDeMuestra.width,
                       height: MedidasMuestrario.ladoDeMuestra.height)
            Text(rotulo).font(.system(size: MedidasMuestrario.vozDeMuestra))
                .foregroundStyle(InstrumentoTheme.base.inkSecondary)
        }
    }
}

#Preview("Palette") {
    let etapas: [(String, Color)] = SleepStage.allCases.map { ($0.rawValue, StrandPalette.sleepStageColor($0)) }
    let zonas: [(String, Color)] = (1...5).map { ("Z\($0)", StrandPalette.hrZoneColor($0)) }
    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            TiraDeRampa(titulo: "recovery", rampa: StrandPalette.recoveryGradient)
            TiraDeRampa(titulo: "strain", rampa: StrandPalette.strainGradient)
            FilaDeMuestras(muestras: etapas)
            FilaDeMuestras(muestras: zonas)
        }
        .padding(24)
    }
    .frame(width: 460, height: 400)
    .background(InstrumentoTheme.base.paper).preferredColorScheme(.light)
}
#endif
