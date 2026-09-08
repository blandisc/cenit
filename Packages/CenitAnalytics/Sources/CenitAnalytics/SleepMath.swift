import Foundation
import CenitModels

// SleepMath.swift — the single source of truth for sleep "need" and accumulated "debt" (FER-339).
//
// Before this, the Sleep Detail screen and the InsightEngine (what the coach reports) each computed
// sleep debt their OWN way — the detail vs a personal need (mean asleep, 7.5 h floor), the engine vs a
// fixed 8 h target — so the user saw two different debts for the same nights. Both now consume this.
//
// FER-409 (owner decision A, 2026-09-06): "need" is now a FIXED published target, not the user's own
// trailing mean. The personal-mean definition made debt positive by construction — any night below your
// own average counted as debt while nights above never paid it back, so even a 9-h-average sleeper with
// normal variance always "owed" sleep. A fixed target lets a good sleeper reach zero debt and is honest
// to explain. Both consumers (Sleep Detail + InsightEngine) read this one place.
public enum SleepMath {

    /// Nightly sleep target: a FIXED 7.5 h (450 min), within the 7–9 h recommended for healthy adults
    /// (Hirshkowitz et al., 2015, *Sleep Health* 1(1):40–43). Not personalized: debt is measured against
    /// the recommendation, not against your own (possibly short) habit.
    public static let recommendedTargetMinutes = 450.0
    /// Back-compat alias — identical value, now a fixed target rather than a personal-mean floor.
    public static let needFloorMinutes = recommendedTargetMinutes
    /// Trailing window (nights) for accumulated debt.
    public static let debtWindow = 7

    /// Nightly sleep need (minutes): the fixed recommended target, independent of how much the user
    /// personally sleeps. `days` is kept for call-site compatibility (and a future personalized model
    /// behind a citation) but is deliberately unused today.
    public static func needMinutes(_ days: [DailyMetric] = []) -> Double {
        _ = days
        return recommendedTargetMinutes
    }

    /// Accumulated sleep debt (minutes) over the trailing `debtWindow`: per-night shortfall vs
    /// `needMinutes`, floored at 0 per night (one long night doesn't pay off a short one).
    public static func debtMinutes(_ days: [DailyMetric]) -> Double {
        let need = needMinutes(days)
        return days.suffix(debtWindow)
            .compactMap { $0.totalSleepMin }
            .reduce(0.0) { $0 + max(0.0, need - $1) }
    }
}
