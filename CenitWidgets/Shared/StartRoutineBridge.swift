// FER-95 · E14 — the cross-process signal for the home-screen «Empezar» button.
// FER-522 — also carries an optional named `routineId` from `StartRoutineIntent` (Siri / Shortcuts).
//
// Shared source: compiled into BOTH the app and the widget extension, mirroring `RestActivityBridge`
// (App-Group inbox, drained by the app). The widget's `StartTodayRoutineIntent` writes a today
// request; `StartRoutineIntent` may write a named id. The app drains on activation and turns it into
// `TabRouter.startTodayTraining()` / `startTraining(routineId:)` — the SAME paths the Daily Brief's
// «Empezar» already uses.
import Foundation

public enum StartRoutineBridge {
    private static let key = "train.widget.startRequested"
    private static let routineIdKey = "train.widget.startRoutineId"
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    /// What the app should start after draining. `today` = previous Bool-true behaviour (widget /
    /// «arranca la de hoy»); `named` = a specific routine id from Siri.
    public enum Request: Equatable, Sendable {
        case today
        case named(String)
    }

    /// Called from the widget extension's `StartTodayRoutineIntent` (today) or `StartRoutineIntent`
    /// (optional named id). `nil` / omitted = today — additive over the pre-FER-522 Bool flag.
    public static func request(routineId: String? = nil) {
        if let routineId {
            defaults.set(routineId, forKey: routineIdKey)
        } else {
            defaults.removeObject(forKey: routineIdKey)
        }
        defaults.set(true, forKey: key)
    }

    /// Called by the app on activation. Returns the pending request (if any) and clears both keys
    /// so a drain never re-fires on the next activation. A payload written before FER-522 (Bool
    /// only, no routineId) drains as `.today`.
    public static func drain() -> Request? {
        let requested = defaults.bool(forKey: key)
        guard requested else { return nil }
        defaults.removeObject(forKey: key)
        let id = defaults.string(forKey: routineIdKey)
        defaults.removeObject(forKey: routineIdKey)
        if let id, !id.isEmpty { return .named(id) }
        return .today
    }
}
