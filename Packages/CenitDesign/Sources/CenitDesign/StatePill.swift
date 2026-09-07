import SwiftUI

/// Maps a semantic status to the color token that paints it. Shared by any pill/badge that needs to
/// speak "this is fine / this is a warning / this is critical" without inventing its own color.
public enum StrandTone: Sendable {
    case neutral, accent, positive, warning, critical

    public var color: Color {
        switch self {
        case .neutral:  InstrumentoTheme.base.inkSecondary
        case .accent:   StrandPalette.accent
        case .positive: StrandPalette.statusPositive
        case .warning:  StrandPalette.statusWarning
        case .critical: StrandPalette.statusCritical
        }
    }
}
