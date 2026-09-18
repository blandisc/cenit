// FER-522 — read-only id+name list of exercises in the live strength session, for App Entity queries.
//
// Lives in CenitShared (Foundation-only). The app writes on session start/mutate and clears on end;
// `ExerciseEntityQuery` only ever READs it. Empty / missing = no live session (honest: Siri offers
// no exercises). Never carries sets/reps/weight — language only.
import Foundation

public struct ActiveSessionSnapshot: Codable, Equatable, Sendable {

    public struct Exercise: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let writtenAt: Date
    public let sessionId: String
    public let exercises: [Exercise]

    public init(writtenAt: Date, sessionId: String, exercises: [Exercise]) {
        self.writtenAt = writtenAt
        self.sessionId = sessionId
        self.exercises = exercises
    }

    // MARK: - App Group I/O

    private static let key = "siri.active.session"
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    public static func write(_ snapshot: ActiveSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Drop the snapshot (session ended / discarded). Entity queries then see an empty catalog.
    public static func clear() {
        defaults.removeObject(forKey: key)
    }

    public static func read() -> ActiveSessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
    }
}
