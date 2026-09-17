import Foundation

// DosePlan.swift · FER-491 · Ola 2 MOTOR.
//
// Typed, versioned session plan computed ONCE by the app (`DosePlanner`) and projected by
// iPhone / Watch / widget. Never re-derived on a surface; never carries the training-load
// ratio (ACWR). Foundation-only so CenitTraining stays pure and `swift test` can probe Codable.
//
// Placement: lives here (not under the app-target `CenitShared/` folder) because CenitWidgets
// does not import that folder (only `AppGroup.swift`), while app + Watch already depend on
// CenitTraining. Widget projections read fields written into `TrainWidgetSnapshot` by the app.

/// Cross-surface session dose for one civil day. `version` bumps when the wire shape changes.
public struct DosePlan: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Same window as `TrainWidgetSnapshot.staleAfter` (3 days).
    public static let staleAfter: TimeInterval = 60 * 60 * 24 * 3

    public var version: Int
    public var computedAt: Date
    /// Local civil day key (`yyyy-MM-dd`).
    public var dayKey: String
    public var routineId: String
    public var routineName: String
    public var programWeek: Int?
    public var deload: Bool
    public var verdict: Verdict
    public var exercises: [DoseExercise]

    public init(version: Int = DosePlan.currentVersion,
                computedAt: Date,
                dayKey: String,
                routineId: String,
                routineName: String,
                programWeek: Int? = nil,
                deload: Bool = false,
                verdict: Verdict,
                exercises: [DoseExercise]) {
        self.version = version
        self.computedAt = computedAt
        self.dayKey = dayKey
        self.routineId = routineId
        self.routineName = routineName
        self.programWeek = programWeek
        self.deload = deload
        self.verdict = verdict
        self.exercises = exercises
    }

    public func isStale(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(computedAt) > Self.staleAfter
    }

    public func isForToday(dayKey today: String) -> Bool {
        self.dayKey == today
    }

    /// `yyyy-MM-dd` in the given calendar's time zone (matches app `DayKey.local` / Analytics day keys).
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0, m = c.month ?? 0, d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public struct Verdict: Codable, Equatable, Sendable {
        public var tone: String
        public var word: String
        public var advice: String?
        public init(tone: String, word: String, advice: String? = nil) {
            self.tone = tone; self.word = word; self.advice = advice
        }
    }
}

/// One exercise inside a `DosePlan`, in routine order.
public struct DoseExercise: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var name: String
    public var order: Int
    public var workSets: [DoseSet]
    public var restSeconds: Int
    public var restMode: String?
    public var hrRestReference: String?
    public var hrRestValue: Double?
    /// FER-491 rule 3 hook («descansos más largos»): always nil until a cited method lands.
    public var restBumpSeconds: Int?
    public var heldRaise: DoseRaise?
    /// Familia 1: served via `ProgramDeload.apply` (sets already cut). Mutually exclusive with
    /// marking leftover sets `optional` for the same exercise.
    public var lightWeek: Bool

    public init(exerciseId: String, name: String, order: Int, workSets: [DoseSet],
                restSeconds: Int, restMode: String? = nil,
                hrRestReference: String? = nil, hrRestValue: Double? = nil,
                restBumpSeconds: Int? = nil, heldRaise: DoseRaise? = nil,
                lightWeek: Bool = false) {
        self.exerciseId = exerciseId
        self.name = name
        self.order = order
        self.workSets = workSets
        self.restSeconds = restSeconds
        self.restMode = restMode
        self.hrRestReference = hrRestReference
        self.hrRestValue = hrRestValue
        self.restBumpSeconds = restBumpSeconds
        self.heldRaise = heldRaise
        self.lightWeek = lightWeek
    }
}

/// One planned set inside a `DoseExercise`.
public struct DoseSet: Codable, Equatable, Sendable {
    public var reps: Int?
    public var repsRangeTop: Int?
    public var seedWeightKg: Double?
    public var kind: SetKind
    /// Familia 2: excess work set kept in the plan but marked optional for today (FER-85).
    /// Does not cut or persist the routine. A completed optional set still counts for progression.
    public var optional: Bool

    public init(reps: Int? = nil, repsRangeTop: Int? = nil, seedWeightKg: Double? = nil,
                kind: SetKind = .work, optional: Bool = false) {
        self.reps = reps
        self.repsRangeTop = repsRangeTop
        self.seedWeightKg = seedWeightKg
        self.kind = kind
        self.optional = optional
    }
}

/// Raise earned by progression but held by today's verdict (`!allowsRaise`).
public struct DoseRaise: Codable, Equatable, Sendable {
    public var fromKg: Double
    public var toKg: Double
    public var phrase: String

    public init(fromKg: Double, toKg: Double, phrase: String) {
        self.fromKg = fromKg; self.toKg = toKg; self.phrase = phrase
    }
}

// MARK: - Pure marking (no new numeric floor)

public enum DosePlanMath {
    /// Marks excess work sets as `optional` using the existing `ProgramDeload.lightWorkSetCount`
    /// boundary (half the work sets, min 1). Not a new floor rule: same count the light week already
    /// uses. No-op when `markOptional` is false. Warm-ups stay non-optional.
    public static func markOptionalSets(_ sets: [DoseSet], markOptional: Bool) -> [DoseSet] {
        guard markOptional else { return sets.map { var s = $0; s.optional = false; return s } }
        let workCount = sets.filter { $0.kind == .work }.count
        let keepRequired = ProgramDeload.lightWorkSetCount(workCount)
        var seenWork = 0
        return sets.map { set in
            var out = set
            guard set.kind == .work else { out.optional = false; return out }
            seenWork += 1
            out.optional = seenWork > keepRequired
            return out
        }
    }
}
