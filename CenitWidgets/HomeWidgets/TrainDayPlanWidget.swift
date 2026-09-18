// FER-521 · Ola 3 — medium home-screen widget: day's plan (DosePlan rows) + week strip as context.
//
// Reads `TrainWidgetSnapshot` + `dosePlanData` already written by the app. Never re-derives a
// verdict or an ACWR load number. Seed weight is the planned set weight (not training load).
// Liquid Glass · El Eje: `LiquidColor.fondoAlto`, tokens only.

import SwiftUI
import WidgetKit
import CenitDesign
import CenitTraining

struct TrainDayPlanEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainWidgetSnapshot?
}

struct TrainDayPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainDayPlanEntry {
        TrainDayPlanEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainDayPlanEntry) -> Void) {
        completion(TrainDayPlanEntry(date: Date(),
                                     snapshot: context.isPreview ? Self.sample : TrainWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainDayPlanEntry>) -> Void) {
        let entry = TrainDayPlanEntry(date: Date(), snapshot: TrainWidgetSnapshot.read())
        let nextRefresh = Date().addingTimeInterval(4 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let sample: TrainWidgetSnapshot = {
        let plan = DosePlan(
            computedAt: Date(),
            dayKey: DosePlan.dayKey(for: Date()),
            routineId: "push",
            routineName: "Push",
            verdict: .init(tone: "clear", word: String(localized: "In range")),
            exercises: [
                DoseExercise(exerciseId: "bench", name: "Bench press", order: 0,
                             workSets: [
                                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
                                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
                                DoseSet(reps: 8, seedWeightKg: 60, kind: .work),
                             ],
                             restSeconds: 120),
                DoseExercise(exerciseId: "ohp", name: "Overhead press", order: 1,
                             workSets: [
                                DoseSet(reps: 8, repsRangeTop: 10, seedWeightKg: 40, kind: .work),
                                DoseSet(reps: 8, repsRangeTop: 10, seedWeightKg: 40, kind: .work),
                             ],
                             restSeconds: 90),
            ])
        return TrainWidgetSnapshot(
            writtenAt: Date(),
            today: .init(routineName: "Push", sessionLive: false),
            verdict: .init(tone: .clear, word: String(localized: "In range")),
            week: WeekProvider.sample.week,
            dosePlanData: try? JSONEncoder().encode(plan))
    }()
}

struct TrainDayPlanWidgetView: View {
    let entry: TrainDayPlanEntry
    private typealias M = HomeWidgetMetrics

    var body: some View {
        content
            .padding(M.padding)
            .containerBackground(LiquidColor.fondoAlto, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isStale(asOf: entry.date) {
                staleBody
            } else if !snapshot.hasPlan {
                noPlanBody
            } else {
                planBody(snapshot: snapshot)
            }
        } else {
            planBody(snapshot: TrainDayPlanProvider.sample)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func planBody(snapshot: TrainWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: M.weekGap) {
            header(snapshot: snapshot)
            if let today = snapshot.today,
               let plan = DosePlan.decode(snapshot.dosePlanData, asOf: entry.date),
               !plan.exercises.isEmpty {
                exerciseRows(plan)
            } else if snapshot.today == nil {
                Text("Rest day")
                    .font(LiquidType.cuerpoBanner.weight(.medium))
                    .foregroundStyle(LiquidColor.tinta700)
            } else {
                Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena)
                    .font(LiquidType.cuerpoBanner.weight(.medium))
                    .foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            WeekStrip(days: snapshot.week)
        }
    }

    private func header(snapshot: TrainWidgetSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: M.microGap) {
                Text("Today's plan")
                    .font(LiquidType.unidad.weight(.semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(verbatim: snapshot.today?.routineName
                     ?? String(localized: "Rest day"))
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: LiquidSpace.s200)
            if let verdict = snapshot.verdict {
                Text(verbatim: verdict.word)
                    .font(LiquidType.cuerpoBanner.weight(.medium))
                    .foregroundStyle(verdict.tone.liquidWord)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func exerciseRows(_ plan: DosePlan) -> some View {
        let ordered = plan.exercises.sorted { $0.order < $1.order }
        // Medium canvas: a few rows; remainder is week context below.
        let visible = Array(ordered.prefix(4))
        return VStack(alignment: .leading, spacing: M.microGap) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, ex in
                Text(verbatim: DosePlanRowFormat.line(ex))
                    .font(LiquidType.pie)
                    .foregroundStyle(LiquidColor.tinta700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if ordered.count > visible.count {
                Text(verbatim: String(format: String(localized: "widget.day-plan.more"),
                                        ordered.count - visible.count))
                    .font(LiquidType.pie)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var staleBody: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("Today's plan")
                .font(LiquidType.unidad.weight(.semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 0)
            Text(verbatim: TrainWidgetSnapshot.rancioComoSeLlena)
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrainWidgetSnapshot.rancioComoSeLlena))
    }

    private var noPlanBody: some View {
        Button(intent: StartTodayRoutineIntent()) {
            VStack(alignment: .leading, spacing: M.rowGap) {
                Text("Today's plan")
                    .font(LiquidType.unidad.weight(.semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(verbatim: TrainWidgetSnapshot.sinPlanQueEs)
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena)
                    .font(LiquidType.cuerpoBanner.weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrainWidgetSnapshot.sinPlanQueEs)
            + Text(verbatim: ". ") + Text(verbatim: TrainWidgetSnapshot.sinPlanComoSeLlena))
        .accessibilityAddTraits(.isButton)
    }
}

/// «{ejercicio} · {series}×{reps} @ {peso semilla}» — seed weight only, never ACWR / load ratio.
enum DosePlanRowFormat {
    static func line(_ ex: DoseExercise) -> String {
        let work = ex.workSets.filter { $0.kind == .work }
        let series = work.count
        let reps = repsText(work.first)
        let base = String(format: String(localized: "widget.day-plan.row"),
                          ex.name, series, reps)
        if let seed = work.first?.seedWeightKg {
            let weight = seedWeightText(seed)
            return String(format: String(localized: "widget.day-plan.row.with-seed"),
                          ex.name, series, reps, weight)
        }
        return base
    }

    private static func repsText(_ set: DoseSet?) -> String {
        guard let set else { return "—" }
        if let top = set.repsRangeTop, let floor = set.reps, top != floor {
            return "\(floor)–\(top)"
        }
        if let r = set.reps { return "\(r)" }
        if let top = set.repsRangeTop { return "\(top)" }
        return "—"
    }

    /// Planned seed kg as display text (not training-load). Whole kg → Int; else one decimal.
    private static func seedWeightText(_ kg: Double) -> String {
        let n: String
        if abs(kg - kg.rounded()) < 0.05 {
            n = "\(Int(kg.rounded()))"
        } else {
            n = String(format: "%.1f", kg)
        }
        return String(format: String(localized: "widget.day-plan.seed-kg"), n)
    }
}

struct TrainDayPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainWidgetSnapshot.dayPlanKind, provider: TrainDayPlanProvider()) { entry in
            TrainDayPlanWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Today's plan"))
        .description(Text("widget.day-plan.description"))
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Con plan", as: .systemMedium) {
    TrainDayPlanWidget()
} timeline: {
    TrainDayPlanEntry(date: .now, snapshot: TrainDayPlanProvider.sample)
}

#Preview("Día de descanso", as: .systemMedium) {
    TrainDayPlanWidget()
} timeline: {
    TrainDayPlanEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil,
        verdict: .init(tone: .hollow, word: String(localized: "Getting to know you")),
        week: WeekProvider.sample.week))
}

#Preview("Sin plan", as: .systemMedium) {
    TrainDayPlanWidget()
} timeline: {
    TrainDayPlanEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil, verdict: nil, week: []))
}

#Preview("Snapshot rancio", as: .systemMedium) {
    TrainDayPlanWidget()
} timeline: {
    TrainDayPlanEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now.addingTimeInterval(-60 * 60 * 24 * 5),
        today: .init(routineName: "Push", sessionLive: false),
        verdict: nil, week: WeekProvider.sample.week))
}
