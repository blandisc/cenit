import Foundation

// WeeklySchedulePlanner.swift — FER-377.
//
// Pure, deterministic placement of a group's `ideal` weekly layout onto a real week that may already
// have some days taken. Never overwrites a taken day; best-effort when there aren't enough free days.
// Foundation only, fully covered by `swift test` — no app, no store, no simulator.

public enum WeeklySchedulePlanner {

    /// Place `ideal` onto a week, respecting `taken` (a session never lands on a taken weekday).
    ///
    /// `weekOrder` is the display order of weekdays (Monday-first: `[2,3,4,5,6,7,1]`); it decides both
    /// tie-breaks and the order of the result. A session whose ideal weekday is free keeps it; a session
    /// whose ideal weekday is taken is re-placed onto the free day whose smallest index-distance (in
    /// `weekOrder`) to any already-used day is largest — so repeats of the same routine stay as spread
    /// out as the remaining room allows. Ties break to the earliest day in `weekOrder`. When no free day
    /// is left the session is dropped (best-effort).
    ///
    /// Invariants: no returned weekday is in `taken`; `result.count <= ideal.count`; a clean week
    /// (`taken` empty) returns `ideal` verbatim, reordered by `weekOrder`.
    public static func place(ideal: [StarterGroupSchedule.Session],
                             taken: Set<Int>,
                             weekOrder: [Int]) -> [StarterGroupSchedule.Session] {
        let index = Dictionary(uniqueKeysWithValues: weekOrder.enumerated().map { ($1, $0) })

        // A session on a free day stays; one on a taken day needs re-placing.
        var placed: [StarterGroupSchedule.Session] = []
        var displaced: [StarterGroupSchedule.Session] = []
        for session in ideal {
            if taken.contains(session.weekday) { displaced.append(session) }
            else { placed.append(session) }
        }

        var used = taken.union(placed.map(\.weekday))

        for session in displaced {
            let free = weekOrder.filter { !used.contains($0) }
            guard let first = free.first else { continue }   // best-effort: nothing free left, drop it
            // Score = (spread from used, earliness); pick the max. Higher spread wins; ties → earliest.
            var chosen = first
            var chosenScore = (minDistance(first, to: used, index: index), -(index[first] ?? 0))
            for day in free.dropFirst() {
                let score = (minDistance(day, to: used, index: index), -(index[day] ?? 0))
                if score > chosenScore { chosen = day; chosenScore = score }
            }
            placed.append((weekday: chosen, templateId: session.templateId))
            used.insert(chosen)
        }

        return placed.sorted { (index[$0.weekday] ?? 0) < (index[$1.weekday] ?? 0) }
    }

    /// Smallest index-distance from `day` to any weekday in `used`; `Int.max` when `used` is empty.
    private static func minDistance(_ day: Int, to used: Set<Int>, index: [Int: Int]) -> Int {
        guard let di = index[day] else { return 0 }
        var best = Int.max
        for u in used {
            guard let ui = index[u] else { continue }
            best = min(best, abs(di - ui))
        }
        return best
    }
}
