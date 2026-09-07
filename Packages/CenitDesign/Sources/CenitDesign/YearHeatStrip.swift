import SwiftUI

// MARK: - Year Heat Strip (§9.4 Trends)
//
// A GitHub-style calendar: columns are weeks, rows are weekdays (Monday-first). Each in-range day is
// tinted by its score via a caller-supplied gradient sampler; an in-range day with no reading draws a
// faint inset square instead. Hover (iOS) reveals a ring + tooltip; an optional tap handler adds touch
// selection since `onContinuousHover` never fires on a touch device.

/// One day's score for the heat strip. `score == nil` means no data for that day.
public struct RecoveryDay: Identifiable, Sendable {
    public var date: Date, score: Double?
    public let id = UUID()

    public init(date: Date, score: Double?) {
        (self.date, self.score) = (date, score)
    }
}

struct YearHeatStrip: View {

    var days: [RecoveryDay]
    var cellSize: CGFloat
    var spacing: CGFloat
    var showsMonthLabels: Bool
    var showsScrub: Bool
    /// Tints a day's cell from its score. Defaults to the recovery gradient.
    var tint: (Double) -> Color
    var emptyFill: Color
    var emptyStroke: Color
    var labelColor: Color
    /// When set, tapping a day calls this — the touch-friendly counterpart to hover.
    var onSelect: ((RecoveryDay) -> Void)?
    var selectionColor: Color
    var cellCornerRadius: CGFloat
    var valueFormat: (Double) -> String
    /// The metric word read out in the `.help`/VoiceOver label ("<date> · <word> 67").
    var valueWord: String

    init(
        days: [RecoveryDay],
        cellSize: CGFloat = 12,
        spacing: CGFloat = 3,
        showsMonthLabels: Bool = true,
        showsScrub: Bool = true,
        tint: @escaping (Double) -> Color = { StrandPalette.recoveryColor($0) },
        emptyFill: Color = InstrumentoTheme.base.hairline,
        emptyStroke: Color = InstrumentoTheme.base.hairline.opacity(0.6),
        labelColor: Color = InstrumentoTheme.base.inkTertiary,
        onSelect: ((RecoveryDay) -> Void)? = nil,
        selectionColor: Color = InstrumentoTheme.base.hairlineStrong,
        cellCornerRadius: CGFloat = 2.5,
        valueFormat: @escaping (Double) -> String = { "Recovery \(Int($0.rounded()))" },
        valueWord: String = "recovery"
    ) {
        self.days = days.sorted { $0.date < $1.date }
        self.cellSize = cellSize
        self.spacing = spacing
        self.showsMonthLabels = showsMonthLabels
        self.showsScrub = showsScrub
        self.tint = tint
        self.emptyFill = emptyFill
        self.emptyStroke = emptyStroke
        self.labelColor = labelColor
        self.onSelect = onSelect
        self.selectionColor = selectionColor
        self.cellCornerRadius = cellCornerRadius
        self.valueFormat = valueFormat
        self.valueWord = valueWord
    }

    /// How many week-columns a rolling 90-day window can ever span (12.86 weeks → 13 or 14 depending on
    /// the start weekday). Fixed at the upper bound so every 90-day calendar renders at the SAME cell
    /// size regardless of which weekday the window happens to start on.
    static let rollingWindowColumns = 14

    /// The cell size that fills `width` with a fixed 14-column grid — a pure function of width alone,
    /// so every 90-day calendar on screen matches, day to day. Falls back to 14pt at width 0.
    static func rollingCellSize(width: CGFloat, spacing: CGFloat = 4, gutter: CGFloat = 24) -> CGFloat {
        guard width > 0 else { return 14 }
        let columns = CGFloat(rollingWindowColumns)
        let raw = (width - gutter - spacing - (columns - 1) * spacing) / columns
        return max(8, min(22, raw))
    }

    private let gutterWidth: CGFloat = 24
    private let monthLabelHeight: CGFloat = 10

    @State private var hoverCell: (week: Int, row: Int)? = nil
    @State private var selectedID: UUID? = nil

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday-first columns
        return cal
    }

    private struct WeekColumn: Identifiable {
        let id = UUID()
        var cells: [RecoveryDay?] // 7 entries, indexed by Monday-first weekday row
        var monthLabel: String?
    }

    private static func emptyColumn() -> WeekColumn { WeekColumn(cells: Array(repeating: nil, count: 7), monthLabel: nil) }

    private func buildWeeks() -> [WeekColumn] {
        guard let leadDate = days.first?.date else { return [] }
        var columns: [WeekColumn] = []
        var building = Self.emptyColumn()
        var monthSeen = -1
        var slotsFilled = weekdayRow(leadDate)

        for day in days {
            let slot = weekdayRow(day.date)
            if slot == 0 && slotsFilled > 0 {
                columns.append(building)
                building = Self.emptyColumn()
                slotsFilled = 0
            }
            building.cells[slot] = day
            let dayMonth = calendar.component(.month, from: day.date)
            if dayMonth != monthSeen {
                building.monthLabel = monthAbbreviation(day.date)
                monthSeen = dayMonth
            }
            slotsFilled += 1
        }
        if slotsFilled > 0 { columns.append(building) }
        return columns
    }

    private func weekdayRow(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1=Sun...7=Sat
        return (weekday + 5) % 7 // Monday-first 0...6
    }

    private func monthAbbreviation(_ date: Date) -> String {
        CalendarFormatters.month.string(from: date)
    }

    /// Weekday gutter labels: Mon/Wed/Fri/Sun only, blank on the rest. `shortWeekdaySymbols` is always
    /// Sunday-indexed regardless of locale, so pick indices [1,3,5,0] for the Monday-first rows.
    private var rowLabels: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return [symbols[1], "", symbols[3], "", symbols[5], "", symbols[0]]
    }

    var body: some View {
        let columns = buildWeeks()
        let gridWidth = gridOriginX + CGFloat(columns.count) * (cellSize + spacing) - spacing
        let gridHeight = gridOriginY + 7 * (cellSize + spacing) - spacing

        return VStack(alignment: .leading, spacing: spacing) {
            if showsMonthLabels {
                HStack(spacing: spacing) {
                    Color.clear.frame(width: gridOriginX - spacing, height: monthLabelHeight)
                    ForEach(columns) { column in
                        Text(column.monthLabel ?? "")
                            .font(StrandFont.footnote)
                            .foregroundStyle(labelColor)
                            .frame(width: cellSize, alignment: .leading)
                    }
                }
            }
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(rowLabels[row])
                            .font(StrandFont.footnote)
                            .foregroundStyle(labelColor)
                            .frame(width: gutterWidth, height: cellSize, alignment: .trailing)
                    }
                }
                ForEach(Array(columns.enumerated()), id: \.element.id) { columnIndex, column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(column.cells[row], isHovered: isHovered(columnIndex, row))
                        }
                    }
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        .overlay(hoverOverlay(columns: columns, gridSize: CGSize(width: gridWidth, height: gridHeight)))
        .contentShape(Rectangle())
        #if os(iOS)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard showsScrub else { return }
            switch phase {
            case .active(let location): hoverCell = cellIndex(at: location, columnCount: columns.count)
            case .ended: hoverCell = nil
            }
        }
        #endif
    }

    private var gridOriginX: CGFloat { gutterWidth + spacing }
    private var gridOriginY: CGFloat { showsMonthLabels ? monthLabelHeight + spacing : 0 }

    private func isHovered(_ column: Int, _ row: Int) -> Bool {
        hoverCell?.week == column && hoverCell?.row == row
    }

    private func cellIndex(at point: CGPoint, columnCount: Int) -> (week: Int, row: Int)? {
        let pitch = cellSize + spacing
        let localX = point.x - gridOriginX
        let localY = point.y - gridOriginY
        guard localX >= 0, localY >= 0 else { return nil }
        let column = Int(localX / pitch)
        let row = Int(localY / pitch)
        guard column >= 0, column < columnCount, row >= 0, row < 7 else { return nil }
        // Reject a hit in the spacing gap between cells.
        guard localX - CGFloat(column) * pitch <= cellSize,
              localY - CGFloat(row) * pitch <= cellSize else { return nil }
        return (column, row)
    }

    private func cellCenter(week column: Int, row: Int) -> CGPoint {
        let pitch = cellSize + spacing
        return CGPoint(x: gridOriginX + CGFloat(column) * pitch + cellSize / 2,
                        y: gridOriginY + CGFloat(row) * pitch + cellSize / 2)
    }

    @ViewBuilder
    private func hoverOverlay(columns: [WeekColumn], gridSize: CGSize) -> some View {
        if showsScrub, let hovered = hoverCell, hovered.week < columns.count,
           let day = columns[hovered.week].cells[hovered.row], let score = day.score {
            let center = cellCenter(week: hovered.week, row: hovered.row)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(InstrumentoTheme.base.hairlineStrong, lineWidth: 1.5)
                    .frame(width: cellSize + 3, height: cellSize + 3)
                    .position(center)
                PositionedTooltip(
                    anchor: center,
                    container: gridSize,
                    tooltip: ChartTooltip(
                        value: valueFormat(score),
                        label: "\(CalendarFormatters.day.string(from: day.date)) · \(StrandPalette.recoveryState(score))",
                        accent: tint(score)
                    )
                )
            }
            .animation(StrandMotion.fade, value: hovered.week)
            .animation(StrandMotion.fade, value: hovered.row)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cell(_ day: RecoveryDay?, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cellCornerRadius)
        let isSelected = day.map { $0.id == selectedID } ?? false
        Group {
            if let day, let score = day.score {
                shape
                    .fill(tint(score))
                    .frame(width: cellSize, height: cellSize)
                    .opacity(isHovered ? 1.0 : (hoverCell == nil ? 1.0 : 0.78))
                    .help("\(CalendarFormatters.day.string(from: day.date)) · \(valueWord) \(Int(score.rounded()))")
            } else if day != nil {
                shape
                    .fill(emptyFill)
                    .overlay(shape.stroke(emptyStroke, lineWidth: 0.5))
                    .frame(width: cellSize, height: cellSize)
            } else {
                shape.fill(Color.clear).frame(width: cellSize, height: cellSize)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(selectionColor, lineWidth: 2)
                    .frame(width: cellSize + 4, height: cellSize + 4)
            }
        }
        .modifier(TappableCell(
            enabled: onSelect != nil && day != nil,
            label: day.map(accessibilityLabel) ?? Text(""),
            action: { if let day { selectedID = day.id; onSelect?(day) } }
        ))
    }

    /// VoiceOver label for a selectable cell.
    private func accessibilityLabel(_ day: RecoveryDay) -> Text {
        let date = CalendarFormatters.day.string(from: day.date)
        guard let score = day.score else { return Text("\(date) · no reading") }
        return Text("\(date) · \(valueWord) \(Int(score.rounded()))")
    }
}

/// Adds tap selection + a VoiceOver button only when `enabled` — the hover-only caller's cells stay
/// exactly as before, with no extra tap target or accessibility element.
private struct TappableCell: ViewModifier {
    let enabled: Bool
    let label: Text
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

private enum CalendarFormatters {
    static let month: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

#if DEBUG
private enum DemoYear {
    static func days(count: Int = 365) -> [RecoveryDay] {
        let anchor = Date()
        return (0..<count).map { offset in
            let backDate = Calendar.current.date(byAdding: .day, value: -(count - 1 - offset), to: anchor) ?? anchor
            let isGap = offset.isMultiple(of: 23)
            let curve = 28.0 * sin(Double(offset) / 11.0)
            let jitter = Double((offset * 31) % 17) - 8.0
            let reading = (55.0 + curve + jitter).clamped(to: 2.0...99.0)
            return RecoveryDay(date: backDate, score: isGap ? nil : reading)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview("YearHeatStrip") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Recovery — past year").strandOverline()
        Text("Hover a cell: ring + date, score and recovery-state tooltip.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
        YearHeatStrip(days: DemoYear.days())
    }
    .padding(28)
    .frame(width: 900, height: 240)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
