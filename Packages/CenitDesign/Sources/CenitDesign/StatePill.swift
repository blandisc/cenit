import SwiftUI

/// El vocabulario de estado que usan píldoras, insignias y sellos: «esto va bien», «esto pide
/// atención», «esto anda mal». Existe para que ninguna pantalla invente su propio verde ni su
/// propio rojo — el tono nombra el estado y la ficha de color se deduce de él.
public enum StrandTone: Sendable { // solo nombra el estado; el color lo resuelve `ficha(de:)`
    case neutral, accent, positive, warning, critical

    /// La ficha de color con la que se pinta este estado.
    public var color: Color { Self.ficha(de: self) }

    /// Tabla estado → ficha. Va como función y no como diccionario a propósito: el `switch`
    /// exhaustivo obliga a resolver el color de cualquier estado nuevo antes de compilar.
    private static func ficha(de tono: StrandTone) -> Color {
        switch tono {
        case .neutral: InstrumentoTheme.base.inkSecondary
        case .accent: StrandPalette.accent
        case .positive: StrandPalette.statusPositive
        case .warning: StrandPalette.statusWarning
        case .critical: StrandPalette.statusCritical
        }
    }
}
