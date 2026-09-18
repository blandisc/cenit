// FER-521 · Ola 3 — watchOS accessoryRectangular: «{rutina} · {palabra}».
//
// Reads the glance `TrainWidgetSnapshot` the watch app mirrors from idleContext (same oracle
// word, never re-derived; never an ACWR / load number). OLED tokens only.

import SwiftUI
import WidgetKit
import CenitDesign

struct TrainVerdictEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainWidgetSnapshot?
}

struct TrainVerdictProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainVerdictEntry {
        TrainVerdictEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainVerdictEntry) -> Void) {
        completion(TrainVerdictEntry(date: Date(),
                                     snapshot: context.isPreview ? Self.sample : TrainWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainVerdictEntry>) -> Void) {
        let entry = TrainVerdictEntry(date: Date(), snapshot: TrainWidgetSnapshot.read())
        let nextRefresh = Date().addingTimeInterval(4 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let sample = TrainWidgetSnapshot(
        writtenAt: Date(),
        today: .init(routineName: "Push", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")),
        week: [
            .init(weekday: 2, state: .today, label: "M"),
            .init(weekday: 3, state: .upcoming, label: "T"),
        ])
}

struct TrainVerdictComplicationView: View {
    let entry: TrainVerdictEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isStale(asOf: entry.date) {
                line(TrainWidgetSnapshot.rancioComoSeLlena)
            } else if let today = snapshot.today {
                let word = snapshot.verdict?.word
                if let word, !word.isEmpty {
                    line(String(format: String(localized: "watch.complication.routine-word"),
                                today.routineName, word))
                } else {
                    line(today.routineName)
                }
            } else if !snapshot.hasPlan {
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(verbatim: TrainWidgetSnapshot.sinPlanQueEs)
                        .font(LiquidType.filaConteo.weight(.semibold))
                        .foregroundStyle(LiquidOLED.tinta)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena)
                        .font(LiquidType.pie)
                        .foregroundStyle(LiquidOLED.tintaSecundaria)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                // Rest day inside an armed week — honest, no invented routine.
                let word = snapshot.verdict?.word
                if let word, !word.isEmpty {
                    line(String(format: String(localized: "watch.complication.rest-word"), word))
                } else {
                    line(String(localized: "Rest day"))
                }
            }
        } else {
            line(String(format: String(localized: "watch.complication.routine-word"),
                        "Push", String(localized: "In range")))
                .redacted(reason: .placeholder)
        }
    }

    private func line(_ text: String) -> some View {
        Text(verbatim: text)
            .font(LiquidType.filaConteo.weight(.semibold))
            .foregroundStyle(LiquidOLED.tinta)
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityLabel(Text(verbatim: text))
    }
}

struct TrainVerdictComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainWidgetSnapshot.verdictComplicationKind,
                            provider: TrainVerdictProvider()) { entry in
            TrainVerdictComplicationView(entry: entry)
        }
        .configurationDisplayName(Text("watch.complication.display-name"))
        .description(Text("watch.complication.description"))
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview("Con rutina", as: .accessoryRectangular) {
    TrainVerdictComplication()
} timeline: {
    TrainVerdictEntry(date: .now, snapshot: TrainVerdictProvider.sample)
}

#Preview("Descanso", as: .accessoryRectangular) {
    TrainVerdictComplication()
} timeline: {
    TrainVerdictEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil,
        verdict: .init(tone: .caution, word: String(localized: "Go light today")),
        week: [
            .init(weekday: 2, state: .rest, label: "M"),
            .init(weekday: 3, state: .upcoming, label: "T"),
        ]))
}

#Preview("Sin plan", as: .accessoryRectangular) {
    TrainVerdictComplication()
} timeline: {
    TrainVerdictEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil, verdict: nil, week: []))
}

#Preview("Rancio", as: .accessoryRectangular) {
    TrainVerdictComplication()
} timeline: {
    TrainVerdictEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now.addingTimeInterval(-60 * 60 * 24 * 5),
        today: .init(routineName: "Push", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")),
        week: []))
}
