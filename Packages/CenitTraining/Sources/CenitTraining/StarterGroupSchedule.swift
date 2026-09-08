import Foundation

// StarterGroupSchedule.swift — FER-377.
//
// The per-`StarterTemplate.Group` weekly frequency + spacing recipe: how often each of a group's
// routines should run in a week, and on which days, applied to an EMPTY week. Pure data; Foundation
// only, no DB and no UI.
//
// Why: `applyTemplateGroup` used to drop each routine on the first free day (1:1, Monday-consecutive),
// so «Full body» trained 1×/week — the low side of the evidence. Training a muscle group ≥2×/week
// beats 1× for hypertrophy (Schoenfeld, Ogborn & Krieger 2016, Sports Medicine), and novices are
// guided to 2–3 full-body sessions/week (ACSM 2009). `ideal(for:)` encodes the defensible frequency;
// `WeeklySchedulePlanner.place` lays it onto the user's real week without overwriting a day they
// already scheduled. The day counts per split (3 / 4 / 6) are programming convention, not a cited
// number.
//
// Spacing is aligned on purpose with `ProgramTemplate.weekdays` (the multi-week program flow) so the
// two features can't silently drift — `StarterGroupScheduleTests` asserts that equality rather than
// deriving one from the other (they are separate features that happen to share a cadence today).

public enum StarterGroupSchedule {

    /// One planned session: the weekday (Calendar convention, 1…7) and the `StarterTemplate` id to run.
    public typealias Session = (weekday: Int, templateId: String)

    /// The preferred layout of a group applied to an EMPTY week, Monday-first. The weekly frequency is
    /// implicit in how often a `templateId` repeats. Days match `ProgramTemplate.weekdays` where a
    /// matching program exists (`full-body-3`, `upper-lower-4`, `ppl-6`); `home`/`mobility` have no
    /// program and carry their own cadence (bodyweight full-body 3×; a soft recovery day 2×, which is
    /// not tied to the hypertrophy floor).
    public static func ideal(for group: StarterTemplate.Group) -> [Session] {
        switch group {
        case .fullBody:
            return [(2, "full-body"), (4, "full-body"), (6, "full-body")]           // L/X/V — 3×
        case .upperLower:
            return [(2, "upper"), (3, "lower"), (5, "upper"), (6, "lower")]          // each half 2×
        case .pushPullLegs:
            return [(2, "ppl-push"), (3, "ppl-pull"), (4, "ppl-legs"),
                    (5, "ppl-push"), (6, "ppl-pull"), (7, "ppl-legs")]               // 6 days — 2×/muscle
        case .home:
            return [(2, "home"), (4, "home"), (6, "home")]                           // bodyweight, 3×
        case .mobility:
            return [(3, "mobility"), (6, "mobility")]                                // soft recovery day, 2×
        }
    }
}
