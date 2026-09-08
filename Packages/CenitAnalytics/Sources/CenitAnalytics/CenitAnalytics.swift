// CenitAnalytics — the arithmetic Cénit does about your body, on your phone.
//
// WHAT THIS PACKAGE IS. Every engine here turns data Apple Health already holds — heart beats, sleep
// windows, workouts, nightly temperature — into the readings the app shows. It runs entirely on the
// device: no server, no account, no network call, not even an optional one. There is nothing to opt
// out of because there is nothing to send.
//
// WHAT EVERY ENTRY POINT PROMISES. Pure and deterministic. No database, no clock, no timezone read
// from the system, no stored state between calls: the same inputs give the same numbers forever. The
// timezone and "today" arrive as arguments. That is what lets the whole package be tested with
// `swift test`, with no simulator, no app and no hardware — and it is the property to protect first
// when adding anything here.
//
// THE ENGINES, one line each:
//
//   Effort and pulse
//   • `HRZones`       — max HR by age, five display zones, and time spent in each.
//   • `StrainScorer`  — cardiovascular load on a 0–21 logarithmic scale, from TRIMP.
//   • `HRVAnalyzer`   — RMSSD, SDNN, pNN50 over beat-to-beat intervals, after artifact rejection.
//   • `Calories`      — resting and active energy from heart rate, or from duration alone.
//   • `RecoveryScorer` — nocturnal resting heart rate, and the three-way band cuts.
//   • `VitalBands`    — is tonight's vital "in range" for THIS person, and on what evidence.
//
//   Baselines and verdicts
//   • `Baselines`     — the robust personal baseline every z-score in the package is measured against.
//   • `ReadinessEngine` — today's signals, training-load ratio and monotony, into one verdict.
//   • `Preparedness`  — the per-axis consensus the app actually shows.
//
//   Sleep, autonomics, training and the rest live beside them, each documented in its own file.
//
// HOW HONEST THESE NUMBERS ARE. They are APPROXIMATIONS, and the files say so one by one: each engine
// names the published method it follows, cites it, and states where it departs. Cénit is not a medical
// device, does not diagnose anything, and none of this is medical advice. When the data is not enough
// to answer, the engines return "no reading" rather than a plausible-looking number — an absent value
// is a truthful answer and an invented one is not.

/// Package identity. Not a data-format version: nothing here is persisted by this package.
public enum CenitAnalytics {
    public static let version = "0.1.0"
}
