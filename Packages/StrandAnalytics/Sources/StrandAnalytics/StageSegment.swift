import Foundation

// StageSegment.swift — one contiguous stretch of a night, labelled with the sleep stage it holds.
//
// This is three contracts wearing one hat, which is why the shape is frozen:
//
//   1. **Interface.** `AnalyticsEngine.encodeStages` / `decodeStages` translate an array of these to
//      and from text; `SleepRegularityIndex` reads the timeline that comes back.
//   2. **On-disk format.** The encoded array IS the literal JSON stored in
//      `CachedSleepSession.stagesJSON` (a `TEXT` column of the `sleepSession` table). Every night a
//      device already has on disk was written with these three keys, so renaming a property, adding
//      a required one, or changing a type would make those nights unreadable — the decoder would
//      return `nil` and the app would silently fall back to one undifferentiated block.
//   3. **Format between packages.** `StrandImport` re-declares the same three fields by hand
//      (it does not depend on this package) so that what it writes and what this package writes are
//      the same bytes. `Cenit/Screens/SleepDetailScreen` parses the JSON directly, without the type.
//      Three independent readers, one shape.
//
// The `stage` vocabulary is CLOSED and lower-case: `"wake"`, `"light"`, `"deep"`, `"rem"`. The
// screen that draws the hypnogram accepts those four (plus the legacy spelling `"awake"`) and
// DISCARDS anything else without raising — so an invented label does not fail loudly, it quietly
// loses minutes from the night. Add a label only by changing every reader in the same breath.
//
// Times are wall-clock unix seconds, the same clock as every other timestamp in this package.

/// A contiguous sleep-stage segment. Times are wall-clock unix seconds.
public struct StageSegment: Equatable, Sendable, Codable {
    public var start: Int
    public var end: Int
    public var stage: String  // "wake" | "light" | "deep" | "rem"

    public init(start: Int, end: Int, stage: String) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}
