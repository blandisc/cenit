#if os(iOS)
import Foundation

/// FER-522 — pure spoken answer for «¿qué toca hoy?». Reads an already-published
/// `TrainWidgetSnapshot` and builds language only — never a score, never a load number,
/// never touches the store / LiquidHoyBuilder / CenitAnalytics.
struct TodaySpokenSummary: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case ready
        case restDay
        case unavailable   // nil or stale snapshot
    }

    let state: State
    let routineName: String?
    let word: String?
    let advice: String?

    /// Structural: no numeric score field exists on this type (invariant for tests).
    /// `word` / `advice` arrive already localized from the snapshot (same oracle as the widget).
    var spokenText: String {
        switch state {
        case .unavailable:
            return String(localized: "Open Cénit for today's reading")
        case .restDay:
            var parts = [String(localized: "Today is a rest day.")]
            if let word { parts.append(word) }
            if let advice, !advice.isEmpty { parts.append(advice) }
            return parts.joined(separator: " ")
        case .ready:
            var parts: [String] = []
            if let routineName {
                parts.append(String(localized: "Today is \(routineName)."))
            }
            if let word { parts.append(word) }
            if let advice, !advice.isEmpty { parts.append(advice) }
            return parts.joined(separator: " ")
        }
    }

    static func from(snapshot: TrainWidgetSnapshot?, now: Date = Date()) -> TodaySpokenSummary {
        guard let snapshot, !snapshot.isStale(asOf: now) else {
            return TodaySpokenSummary(state: .unavailable, routineName: nil, word: nil, advice: nil)
        }
        let word = snapshot.verdict?.word
        let advice = snapshot.verdict?.advice
        guard let today = snapshot.today else {
            return TodaySpokenSummary(state: .restDay, routineName: nil, word: word, advice: advice)
        }
        return TodaySpokenSummary(state: .ready, routineName: today.routineName,
                                  word: word, advice: advice)
    }
}
#endif
