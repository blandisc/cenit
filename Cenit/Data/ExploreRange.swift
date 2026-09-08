import Foundation
import CenitDesign
import StrandAnalytics

// MARK: - Range
//
// The W/M/3M/6M/1Y/ALL window shared by every metric drill-down: the dark Metric
// Explorer (`MetricDetailView`) and the unified light Detalle de Métrica
// (`MetricDetailScreen`, FER-185). Extracted from `MetricExplorerView.swift` so the
// new screen doesn't have to import the Explorer to reuse the window model.

/// La ventana de tiempo que el usuario elige —semana, mes, trimestre, medio año, año o todo— y que
/// gobierna el control de píldoras que aparece arriba de cada gráfica.
enum ExploreRange: Int, CaseIterable, Identifiable, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .week: return String(localized: "W"); case .month: return String(localized: "M")
        case .quarter: return String(localized: "3M"); case .half: return String(localized: "6M")
        case .year: return String(localized: "1Y"); case .all: return String(localized: "ALL")
        }
    }
    var name: String {
        switch self {
        case .week: return String(localized: "week"); case .month: return String(localized: "month")
        case .quarter: return String(localized: "quarter"); case .half: return String(localized: "6 months")
        case .year: return String(localized: "year"); case .all: return String(localized: "all time")
        }
    }

    /// A human phrase for sentences ("over 1Y" → "over 3 months"). Moved here from the retired
    /// `CompareView.CompareRange` (FER-104 / TND-29, foco 2): Compare and every drill-down now share
    /// ONE range enum, so the overlay/correlation captions read from the same window model.
    var phrase: String {
        switch self {
        case .week:    return String(localized: "the last 7 days")
        case .month:   return String(localized: "30 days")
        case .quarter: return String(localized: "3 months")
        case .half:    return String(localized: "6 months")
        case .year:    return String(localized: "1 year")
        case .all:     return String(localized: "all history")
        }
    }
    /// Cuántos días hacia atrás abarca la ventana. Nada significa «todo el historial».
    var days: Int? { self == .all ? nil : rawValue }

    /// The trend chip's comparison for `series`: this window vs the equally-long window before it. `.all`
    /// has no previous period of the same length, so it returns nil (and the chip hides). Pass the series
    /// already trimmed of any in-progress current day. The shared glue for every trend block. (FER-264)
    func periodComparison(of series: [(day: String, value: Double)]) -> PeriodComparison? {
        days.map { ComparisonEngine.periodOverPeriod(byDay: series, windowDays: $0,
                                                     referenceDay: series.last?.day ?? "") }
    }

    /// The period the trend chip compares against — its trailing window vs the equally-long window before
    /// it. `.all` has no previous period of the same length, so it returns nil and the chip hides. (FER-264)
    var comparisonPeriod: TrendStatSummary.ComparisonPeriod? {
        switch self {
        case .week:    return .week
        case .month:   return .month
        case .quarter: return .quarter
        case .half:    return .halfYear
        case .year:    return .year
        case .all:     return nil
        }
    }

    /// Ascending order of every range, the basis for the auto-expand search.
    private static let ascending: [ExploreRange] = [.week, .month, .quarter, .half, .year, .all]

    /// Esta ventana y todas las MÁS GRANDES, de menor a mayor.
    ///
    /// Es el orden en que se busca cuando la ventana elegida no tiene ni un punto: la gráfica se
    /// abre sola hasta encontrar datos. «Todo» cierra la cadena, así que la búsqueda siempre acaba.
    var widening: [ExploreRange] {
        guard let i = Self.ascending.firstIndex(of: self) else { return [.all] }
        return Array(Self.ascending[i...])
    }
}
