// FER-521 · Ola 3 — mirrors idleContext into the App Group snapshot the accessoryRectangular
// complication reads. Same oracle word the iPhone pushed; never re-derived; never an ACWR number.

import Foundation
import WidgetKit

enum WatchTrainGlancePublisher {

    /// Writes a `TrainWidgetSnapshot` the complication can trust, then reloads its timeline.
    /// - `hasWeeklyPlan`: false → sin plan (empty week); true with nil routine → rest day.
    static func publish(routineName: String?,
                        word: String?,
                        advice: String?,
                        toneRaw: String?,
                        hasWeeklyPlan: Bool,
                        now: Date = Date()) {
        let today = routineName.map {
            TrainWidgetSnapshot.TodayPlan(routineName: $0, sessionLive: false)
        }
        let verdict: TrainWidgetSnapshot.Verdict? = {
            guard let word, !word.isEmpty else { return nil }
            return .init(tone: tone(from: toneRaw), word: word, advice: advice)
        }()
        // hasPlan = today != nil || week.contains { $0.state != .rest }
        let week: [TrainWidgetSnapshot.WeekDay]
        if let _ = today {
            week = [.init(weekday: 2, state: .today, label: "")]
        } else if hasWeeklyPlan {
            // Rest day inside an armed week: one non-rest day so hasPlan stays true.
            week = [
                .init(weekday: 2, state: .rest, label: ""),
                .init(weekday: 3, state: .upcoming, label: ""),
            ]
        } else {
            week = []
        }
        let snap = TrainWidgetSnapshot(writtenAt: now, today: today, verdict: verdict, week: week)
        TrainWidgetSnapshot.write(snap)
        WidgetCenter.shared.reloadTimelines(ofKind: TrainWidgetSnapshot.verdictComplicationKind)
    }

    private static func tone(from raw: String?) -> TrainWidgetSnapshot.VerdictTone {
        switch raw {
        case "clear":   return .clear
        case "caution": return .caution
        case "ease":    return .ease
        default:        return .hollow
        }
    }
}
