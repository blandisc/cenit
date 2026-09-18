// FER-95 · E14 / FER-521 · Ola 3 — the 7-day strip shared by WeekWidget and TrainDayPlanWidget.
//
// Same tesela grammar as `EntrenarHubSemana.tesela` in the app; box size stays
// `HomeWidgetMetrics.dayToken` (widget canvas, not the app's 26pt). No family tint
// (decisión #13 del épico).

import SwiftUI
import CenitDesign

struct WeekStrip: View {
    let days: [TrainWidgetSnapshot.WeekDay]
    private typealias M = HomeWidgetMetrics
    private typealias T = EntrenarHubMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                tesela(day.state, label: day.label)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a11yLabel(day))
            }
        }
    }

    /// Same case grammar as the app: `.done` fills, everyone else outlines the shape; `.today` is a
    /// SOLID ring, `.upcoming`/`.rest` are DASHED — only color/opacity tells those two apart, exactly
    /// like `EntrenarDayToken.planned`/`.rest` do.
    @ViewBuilder private func tesela(_ state: TrainWidgetSnapshot.WeekDayState, label: String) -> some View {
        let side = M.dayToken
        let shape = RoundedRectangle(cornerRadius: T.teselaRadius, style: .continuous)
        ZStack {
            switch state {
            case .done:
                shape.fill(LiquidColor.tinta900)
            case .today:
                shape.strokeBorder(LiquidColor.tinta900, lineWidth: T.teselaHoyLineWidth)
            case .upcoming:
                shape.strokeBorder(LiquidColor.tinta500,
                                    style: StrokeStyle(lineWidth: T.teselaOffLineWidth, dash: [2, 2]))
            case .rest:
                shape.strokeBorder(LiquidColor.tinta900.opacity(T.teselaOffAlfa),
                                    style: StrokeStyle(lineWidth: T.teselaOffLineWidth, dash: [2, 2]))
            }
            Text(verbatim: label)
                .font(T.teselaLabel)
                .foregroundStyle(state == .done ? LiquidColor.papelTarjeta : LiquidColor.tinta500)
        }
        .frame(width: side, height: side)
    }

    private func a11yLabel(_ day: TrainWidgetSnapshot.WeekDay) -> Text {
        let name = Text(verbatim: day.label) + Text(verbatim: ", ")
        switch day.state {
        case .done:     return name + Text("trained.day")
        case .today:    return name + Text("today") + Text(verbatim: ", ") + Text("training day")
        case .upcoming: return name + Text("planned")
        case .rest:     return name + Text("rest day")
        }
    }
}
