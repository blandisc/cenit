import SwiftUI

/// One stage interval of a night's sleep. `start`/`end` are elapsed seconds since the start of the
/// night (not absolute dates), so several intervals can share one 0...total axis without conversion.
public struct SleepInterval: Identifiable, Sendable {
    public var stage: SleepStage
    public var start, end: TimeInterval
    public let id = UUID()

    public init(stage: SleepStage, start: TimeInterval, end: TimeInterval) {
        (self.stage, self.start, self.end) = (stage, start, end)
    }

    /// Elapsed seconds the stage lasted — never negative, even given a reversed start/end pair.
    public var duration: TimeInterval { Swift.max(0, end - start) }
}
