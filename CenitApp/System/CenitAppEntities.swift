#if os(iOS)
import Foundation
import AppIntents

// MARK: - RoutineEntity (FER-522)

/// Thin AppEntity for a routine — id + display name only. Never sets/reps/weight/DosePlan.
struct RoutineEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine")
    static var defaultQuery = RoutineEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct RoutineEntityQuery: EntityQuery {
    func entities(for identifiers: [RoutineEntity.ID]) async throws -> [RoutineEntity] {
        let catalog = RoutineCatalogSnapshot.read()?.routines ?? []
        let wanted = Set(identifiers)
        return catalog.filter { wanted.contains($0.id) }.map { RoutineEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        let catalog = RoutineCatalogSnapshot.read()?.routines ?? []
        return catalog.map { RoutineEntity(id: $0.id, name: $0.name) }
    }
}

extension RoutineEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [RoutineEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }
        let catalog = RoutineCatalogSnapshot.read()?.routines ?? []
        return catalog
            .filter { $0.name.lowercased().contains(needle) || $0.id.lowercased() == needle }
            .map { RoutineEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - ExerciseEntity (FER-522)

/// Thin AppEntity for an exercise in the live session — id + display name only.
struct ExerciseEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Exercise")
    static var defaultQuery = ExerciseEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct ExerciseEntityQuery: EntityQuery {
    func entities(for identifiers: [ExerciseEntity.ID]) async throws -> [ExerciseEntity] {
        let live = ActiveSessionSnapshot.read()?.exercises ?? []
        let wanted = Set(identifiers)
        return live.filter { wanted.contains($0.id) }.map { ExerciseEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        let live = ActiveSessionSnapshot.read()?.exercises ?? []
        return live.map { ExerciseEntity(id: $0.id, name: $0.name) }
    }
}

extension ExerciseEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }
        let live = ActiveSessionSnapshot.read()?.exercises ?? []
        return live
            .filter { $0.name.lowercased().contains(needle) || $0.id.lowercased() == needle }
            .map { ExerciseEntity(id: $0.id, name: $0.name) }
    }
}
#endif
