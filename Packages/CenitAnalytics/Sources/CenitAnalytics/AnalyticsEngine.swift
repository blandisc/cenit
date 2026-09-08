import Foundation

// AnalyticsEngine.swift — the two small conversions the whole app agrees on: civil-day keys and the
// sleep-stage codec.
//
// Nothing here computes anything about the body. These are pure translations between a form the code
// uses and a form the database stores, and they live together because both are *naming* decisions
// that, once written to disk, can never drift:
//
//   • Civil-day keying (`dayString`, `localMidnight`, `futureLocalDaysToPrune`). Every daily row is
//     addressed by a `"yyyy-MM-dd"` string. Change how that string is produced and every row already
//     stored answers to a different name.
//   • The sleep-stage codec (`encodeStages` / `decodeStages`) — the text form of a night's timeline.
//
// Pure, deterministic, database-free: the timezone arrives as a parameter, never from a clock.

public enum AnalyticsEngine {

    /// The one formatter behind every day key. Three settings carry the whole contract, and all three
    /// are load-bearing:
    ///
    ///   • `en_US_POSIX` — so the pattern means what it says regardless of the device's region. Under
    ///     a locale with its own calendar, `yyyy-MM-dd` would render a different year entirely.
    ///   • UTC — the day boundary is applied by the caller, by shifting the instant. The formatter
    ///     itself must never move a date.
    ///   • `yyyy-MM-dd` — fixed width, zero-padded, so a plain string `<` between two keys is exactly
    ///     chronological order. Half the queries in the app lean on that.
    ///
    /// Built once and shared: constructing a `DateFormatter` per call is expensive enough to show up
    /// when keying a few thousand rows.
    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Format a unix-seconds timestamp as a `YYYY-MM-DD` day string in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Default 0 = UTC, which keeps pure-function callers and tests on
    /// UTC. The device's LOCAL civil day is obtained by shifting the instant by the offset and
    /// formatting in UTC — one displacement instead of a calendar, which is what keeps day-keys
    /// deterministic and dedup-stable across sources. (FER-226: `dailyMetric.day` is the local civil day.)
    public static func dayString(_ ts: Int, tzOffsetSeconds: Int = 0) -> String {
        isoDay.string(from: Date(timeIntervalSince1970: TimeInterval(ts + tzOffsetSeconds)))
    }

    /// Unix-seconds instant of LOCAL midnight for the civil day `ts` falls on, in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Used as the inclusive lower bound of the additive-totals window
    /// (steps + calories), replacing the old UTC-midnight floor. Pure; default 0 = UTC midnight. (FER-226)
    public static func localMidnight(_ ts: Int, tzOffsetSeconds: Int = 0) -> Int {
        let local = ts + tzOffsetSeconds
        let flooredLocal = local - ((local % 86_400) + 86_400) % 86_400
        return flooredLocal - tzOffsetSeconds
    }

    /// Which `stored` day-keys fall strictly AFTER `today` (the device's local civil day) and were NOT
    /// (re)written this run — the spurious "future-in-local" rows the one-time UTC→local re-bucket
    /// prunes (FER-226). Pure so the prune's selection is testable without the app/store. Past and
    /// today rows are never returned, so a day that couldn't be recomputed keeps its row (no data loss);
    /// `written` excludes a freshly-written future row defensively (the re-group never writes future).
    public static func futureLocalDaysToPrune(stored: [String], today: String,
                                              written: Set<String>) -> [String] {
        stored.filter { $0 > today && !written.contains($0) }
    }

    /// Serialize a night's timeline to the text stored in `CachedSleepSession.stagesJSON`, or `nil`
    /// if it cannot be encoded. The result is a JSON ARRAY of segments — `[{start,end,stage}]` — which
    /// is exactly the form `decodeStages` expects and the form `CenitImport` writes by hand.
    ///
    /// Two shapes live in the stored column and must keep living side by side: this array, and an
    /// older imported shape that is a dictionary of totals per stage with no timeline at all. The
    /// decoder tells them apart by failing on the second, so callers can fall back to a single coarse
    /// interval. Encoding only ever produces the array.
    static func encodeStages(_ stages: [StageSegment]) -> String? {
        guard let data = try? JSONEncoder().encode(stages) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a COMPUTED `stagesJSON` (the `[{start,end,stage}]` segment array `encodeStages` writes)
    /// back to `[StageSegment]`. Returns nil for the IMPORTED dict-of-totals form (no per-segment
    /// timeline) or empty/malformed input, so callers fall back to a coarse `[start,end]` interval.
    /// The counterpart of `encodeStages`; reused by SleepView and the SRI orchestration (FER-214).
    public static func decodeStages(_ json: String?) -> [StageSegment]? {
        guard let json, let data = json.data(using: .utf8),
              let segs = try? JSONDecoder().decode([StageSegment].self, from: data),
              !segs.isEmpty else { return nil }
        return segs
    }
}
