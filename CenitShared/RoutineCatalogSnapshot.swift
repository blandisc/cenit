// FER-522 — read-only id+name catalog of routines for App Entity queries (Siri / Shortcuts).
//
// Lives in CenitShared (Foundation-only), same discipline as `TrainWidgetSnapshot`: the app writes
// after every dashboard publish; `RoutineEntityQuery` only ever READs it. Never opens the store,
// never carries sets/reps/weight/DosePlan — language only.
import Foundation

public struct RoutineCatalogSnapshot: Codable, Equatable, Sendable {

    /// Same staleness window as `TrainWidgetSnapshot` — past this, entity resolution still works by
    /// id, but a renamed/deleted routine may show a stale display name until the app runs again.
    public static let staleAfter: TimeInterval = 60 * 60 * 24 * 3

    public struct Entry: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let writtenAt: Date
    public let routines: [Entry]

    public init(writtenAt: Date, routines: [Entry]) {
        self.writtenAt = writtenAt
        self.routines = routines
    }

    public func isStale(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(writtenAt) > Self.staleAfter
    }

    // MARK: - App Group I/O

    private static let key = "siri.routine.catalog"
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    public static func write(_ snapshot: RoutineCatalogSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func read() -> RoutineCatalogSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RoutineCatalogSnapshot.self, from: data)
    }
}
