import Foundation
import StrandModels

/// Which data sources feed the dashboard and the recovery baseline — a single user preference (FER-484).
/// The capture pipeline (the on-device stream + HealthKit) always writes ALL sources; the mode only filters what is
/// READ. `combined` is the historical behavior (the on-device row wins, Apple Health is the base / gap-fill).
/// Under the Apple-only pin (FER-1003) the live app is pinned to `.appleHealthOnly`; the other cases
/// remain for persistence/raw-value stability and later phases.
public enum DataSourceMode: String, Codable, CaseIterable, Sendable {
    /// On-device stream + Apple Health: the on-device row wins, Apple fills the gaps (the historical default).
    case combined
    /// Legacy on-device stream only — Apple Health is excluded from every read (a night without it stays empty).
    /// The raw value stays as it was written: any preference already saved on disk must still decode.
    case legacyOnly = "whoopOnly"
    /// Apple Health only — the on-device stream is excluded from every read (its rows stay stored, just unused).
    case appleHealthOnly

    /// True when Apple Health rows may be read. Always true under the Apple-only product pin.
    public var usesAppleHealth: Bool { true }
}

/// Applies a `DataSourceMode` to the per-source daily arrays BEFORE they enter the dashboard merge
/// (`Repository.mergeDaily`) and the baseline fold. Collapsed to the Apple-only branch under the
/// FER-1003 pin: on-device rows never enter; Apple is passed through unchanged.
public enum DataSourcePolicy {
    public static func filter(_ mode: DataSourceMode,
                              imported: [DailyMetric],
                              computed: [DailyMetric],
                              apple: [DailyMetric])
        -> (imported: [DailyMetric], computed: [DailyMetric], apple: [DailyMetric]) {
        _ = mode; _ = imported; _ = computed
        return ([], [], apple)
    }
}
