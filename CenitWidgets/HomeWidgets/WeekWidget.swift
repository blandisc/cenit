// FER-95 · E14 — the week's plan, the medium home-screen widget.
//
// Redraws the 7-day strip with the SAME pure semantics `WeeklySplit`/`WeekTokens` already define
// (done/today/upcoming/rest — via `TrainWidgetSnapshot.WeekDayState`, already resolved by the app), but
// as its own WidgetKit view: `WeekTokens` (CenitDesign) is a SwiftUI `View` built for the app's live
// theme environment, not something a widget extension can reuse verbatim. No family tint here (out of
// scope — decisión #13 del épico, resuelta en otra rama): a filled token means «trained», not «which
// routine». Liquid Glass · El Eje (DECISIONS 2026-09-03): `LiquidColor.fondoAlto` + tinta Liquid.

import SwiftUI
import WidgetKit
import CenitDesign

struct WeekEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainWidgetSnapshot?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: Date(),
                             snapshot: context.isPreview ? Self.sample : TrainWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let entry = WeekEntry(date: Date(), snapshot: TrainWidgetSnapshot.read())
        let nextRefresh = Date().addingTimeInterval(4 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let sample = TrainWidgetSnapshot(
        writtenAt: Date(),
        today: .init(routineName: "Push", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")),
        week: [
            // Iniciales en inglés (galería del widget): M T W T F S S.
            .init(weekday: 2, state: .done, label: "M"), .init(weekday: 3, state: .rest, label: "T"),
            .init(weekday: 4, state: .done, label: "W"), .init(weekday: 5, state: .rest, label: "T"),
            .init(weekday: 6, state: .today, label: "F"), .init(weekday: 7, state: .upcoming, label: "S"),
            .init(weekday: 1, state: .rest, label: "S"),
        ])
}

struct WeekWidgetView: View {
    let entry: WeekEntry
    private typealias M = HomeWidgetMetrics

    var body: some View {
        content
            .padding(M.padding)
            .containerBackground(LiquidColor.fondoAlto, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isStale(asOf: entry.date) {
                staleHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                body(snapshot: snapshot)
            }
        } else {
            body(snapshot: WeekProvider.sample)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func body(snapshot: TrainWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: M.weekGap) {
            header(snapshot: snapshot)
            WeekStrip(days: snapshot.week)
        }
    }

    private var staleHeader: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("This week")
                .font(LiquidType.unidad.weight(.semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 0)
            // FER-433 · Para qué abrirla, no solo «Abre Cénit».
            Text(verbatim: TrainWidgetSnapshot.rancioComoSeLlena)
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrainWidgetSnapshot.rancioComoSeLlena))
    }

    @ViewBuilder private func header(snapshot: TrainWidgetSnapshot) -> some View {
        if let today = snapshot.today {
            Button(intent: StartTodayRoutineIntent()) {
                headerRow(title: Text(verbatim: today.routineName), verdict: snapshot.verdict,
                          cta: today.sessionLive ? Text("Continue") : Text("Start"))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((today.sessionLive ? Text("Continue") : Text("Start routine"))
                + Text(verbatim: ", ") + Text(verbatim: today.routineName))
            .accessibilityHint(Text("Opens today's guided session"))
            .accessibilityAddTraits(.isButton)
        } else if !snapshot.hasPlan {
            // FER-433 · Sin plan (primer uso): qué va aquí y cómo se llena; el toque abre Cénit en Entrenar.
            Button(intent: StartTodayRoutineIntent()) {
                headerRow(title: Text(verbatim: TrainWidgetSnapshot.sinPlanQueEs), verdict: snapshot.verdict,
                          cta: Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: TrainWidgetSnapshot.sinPlanQueEs)
                + Text(verbatim: ". ") + Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena))
            .accessibilityAddTraits(.isButton)
        } else {
            headerRow(title: Text("Rest day"), verdict: snapshot.verdict, cta: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Rest day"))
        }
    }

    /// FER-433: `cta` es un `Text` ya resuelto (antes `LocalizedStringKey?`) para que el primer uso pueda
    /// pasar su copy `verbatim` sin una segunda firma.
    private func headerRow(title: Text, verdict: TrainWidgetSnapshot.Verdict?, cta: Text?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: M.microGap) {
                Text("Today")
                    .font(LiquidType.unidad.weight(.semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(LiquidColor.tinta500)
                title
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: LiquidSpace.s200)
            VStack(alignment: .trailing, spacing: M.microGap) {
                if let verdict {
                    Text(verbatim: verdict.word)
                        .font(LiquidType.cuerpoBanner.weight(.medium))
                        .foregroundStyle(verdict.tone.liquidWord)
                        .lineLimit(verdict.advice == nil ? 1 : 2)
                        .minimumScaleFactor(0.8)
                    // FER-499: el consejo del oráculo (solo el caso sin Apple Salud lo trae aquí); sin él
                    // la palabra «Sin Apple Salud,» quedaba como coma colgando. Encoge antes que romper la
                    // cabecera compacta del strip.
                    if let advice = verdict.advice {
                        Text(verbatim: advice)
                            .font(LiquidType.pie)
                            .foregroundStyle(LiquidColor.tinta500)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                if let cta {
                    cta
                        .font(LiquidType.cuerpoBanner.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta900)
                }
            }
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainWidgetSnapshot.weekKind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("This week"))
        .description(Text("Your week's plan, and today's routine in one tap."))
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Con rutina", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: WeekProvider.sample)
}

#Preview("Día de descanso", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil,
        verdict: .init(tone: .hollow, word: String(localized: "Getting to know you")),
        week: WeekProvider.sample.week))
}

#Preview("Sesión ya viva", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: .init(routineName: "Tirón", sessionLive: true),
        verdict: nil, week: WeekProvider.sample.week))
}

#Preview("Snapshot rancio", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now.addingTimeInterval(-60 * 60 * 24 * 5),
        today: .init(routineName: "Push", sessionLive: false), verdict: nil,
        week: WeekProvider.sample.week))
}

#Preview("Sin snapshot (primera instalación)", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: nil)
}
