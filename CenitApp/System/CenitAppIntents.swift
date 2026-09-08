#if os(iOS)
import Foundation
import AppIntents

/// Buzón de lo que un App Intent pidió mientras la app podía estar dormida. Un intent no
/// alcanza al `AppModel` vivo, así que deja aquí su encargo y la app lo recoge la próxima vez
/// que pasa a primer plano.
enum PendingIntents {
    enum Action: String { case markMoment }

    /// A queued action plus the instant it was requested. The queue can sit for hours — an intent
    /// run from the lock screen only drains when the app next becomes active — so the request time
    /// has to travel with the action: a `markMoment` stamped at drain time is a marker for the wrong
    /// moment, which defeats the point of the intent.
    struct Entry {
        let action: Action
        let date: Date
    }

    private static let key = PrefKey.pendingIntents.rawValue
    /// Shared App-Group store, with the same logged `.standard` fallback as `AppGroup.sharedDefaults`
    /// (FER-32) instead of a silent no-op when the entitlement is missing.
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func append(_ action: Action, at date: Date = Date()) {
        let store = defaults
        let encoded = "\(action.rawValue)|\(stamp.string(from: date))"
        store.set((store.stringArray(forKey: key) ?? []) + [encoded], forKey: key)
    }

    static func drain() -> [Entry] {
        let store = defaults
        let queued = store.stringArray(forKey: key) ?? []
        store.removeObject(forKey: key)
        let drainedAt = Date()
        return queued.compactMap { decode($0, fallback: drainedAt) }
    }

    /// Parses an `action|ISO8601` pair. Entries written by a build that predates the timestamp are
    /// bare action names: they keep working across the update by falling back to the drain time (the
    /// old behaviour) instead of being dropped on the floor.
    private static func decode(_ raw: String, fallback: Date) -> Entry? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = parts.first, let action = Action(rawValue: String(name)) else { return nil }
        let date = parts.count == 2 ? stamp.date(from: String(parts[1])) : nil
        return Entry(action: action, date: date ?? fallback)
    }
}

/// Deja marcado un «momento» con su hora, desde Siri, Spotlight o Atajos, sin abrir la app.
struct MarkMomentIntent: AppIntent {
    static var title: LocalizedStringResource { "Mark a Moment" }
    static var description = IntentDescription("Record a timestamped moment in Cénit.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // La hora del encargo viaja con él: la app puede tardar horas en recogerlo.
        PendingIntents.append(.markMoment, at: Date())
        return .result(dialog: "Moment marked.")
    }
}

/// Publica los intents de Cénit a Siri, Spotlight y la galería de Atajos, sin que el usuario
/// tenga que configurar nada.
struct CenitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkMomentIntent(),
            phrases: ["Mark a moment in \(.applicationName)"],
            shortTitle: "Mark a Moment",
            systemImageName: "mappin.and.ellipse")
    }
}
#endif
