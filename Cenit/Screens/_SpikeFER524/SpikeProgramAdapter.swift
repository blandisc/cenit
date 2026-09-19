#if DEBUG && CENIT_SPIKE_IALOCAL
#if canImport(FoundationModels)
import Foundation
import FoundationModels
import CenitImport
import CenitTraining

// FER-524 spike DESECHABLE. Adaptador SpikeProgram → wire cenit.workout.v1
// → WorkoutProgramImporter (REAL) → WorkoutExerciseReconciler (READ-ONLY).
// No escribe en la DB: solo arma RoutineExercise[] en memoria para mostrarlos.

/// Resultado read-only del pipeline real de import (sin persistir).
@available(iOS 26.0, *)
struct SpikeImportPreview: Sendable {
    /// JSON wire (llaves espanolas) que entraria al BYO-LLM path.
    let wireJSON: String
    let program: WorkoutProgram
    /// Slots reconciliados (solo los que matchearon catalogo).
    let reconciled: [RoutineExercise]
    /// Nombres que el reconciler no resolvio (ni autoMatch).
    let unmatched: [String]
    /// Nombre importado → id de catalogo (resolve o autoMatch).
    let matches: [(importedName: String, exerciseId: String, exerciseName: String, auto: Bool)]
}

@available(iOS 26.0, *)
enum SpikeProgramAdapter {

    /// SpikeProgram → JSON wire espanol → importer REAL → reconciler READ-ONLY.
    static func preview(
        _ spike: SpikeProgram,
        catalog: [Exercise] = ExerciseCatalog.all,
        aliases: [String: String] = ExerciseAliasTable.bundled
    ) throws -> SpikeImportPreview {
        let wire = wireObject(from: spike)
        let data = try JSONSerialization.data(withJSONObject: wire, options: [.prettyPrinted, .sortedKeys])
        let wireJSON = String(data: data, encoding: .utf8) ?? "{}"
        let program = try WorkoutProgramImporter().parse(data)

        let reconciler = WorkoutExerciseReconciler(known: catalog, aliases: aliases)
        let unmatched = reconciler.unmatchedNames(in: program)
        let auto = reconciler.autoMatches(in: program)

        var matches: [(String, String, String, Bool)] = []
        var reconciled: [RoutineExercise] = []

        for (rIndex, routine) in program.routines.enumerated() {
            let routineId = "spike-preview-\(rIndex)"
            var position = 0
            for ex in routine.exercises {
                let resolved = reconciler.resolve(ex)
                let autoHit = resolved == nil ? auto[ex.name] : nil
                let hit = resolved ?? autoHit
                guard let exercise = hit else { continue }
                let isAuto = resolved == nil && autoHit != nil
                matches.append((ex.name, exercise.id, exercise.nameES ?? exercise.name, isAuto))
                let hasRest = ex.restSeconds != nil
                reconciled.append(RoutineExercise(
                    routineId: routineId,
                    exerciseId: exercise.id,
                    position: position,
                    targetSets: ex.sets,
                    targetReps: ex.reps,
                    targetWeightKg: ex.weightKg,
                    warmupPercents: ex.warmupPercents,
                    restMode: hasRest ? .fixed : .heartRate,
                    restSeconds: ex.restSeconds ?? 90,
                    supersetGroup: ex.supersetGroup
                ))
                position += 1
            }
        }

        return SpikeImportPreview(
            wireJSON: wireJSON,
            program: program,
            reconciled: reconciled,
            unmatched: unmatched,
            matches: matches
        )
    }

    /// Emite el diccionario wire de `cenit.workout.v1` (mismas llaves que BYO-LLM).
    static func wireObject(from spike: SpikeProgram) -> [String: Any] {
        let idioma = (spike.idioma == "en") ? "en" : "es"
        let unidad: String = {
            let u = spike.unidad.lowercased()
            if u == "lb" || u.contains("libra") { return "lb" }
            return "kg"
        }()

        let rutinas: [[String: Any]] = spike.rutinas.compactMap { routine in
            let ejercicios: [[String: Any]] = routine.ejercicios.compactMap { ex in
                let name = ex.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                var row: [String: Any] = [
                    "nombre": name,
                    "series": max(1, ex.series),
                ]
                let tipo = ex.tipo.trimmingCharacters(in: .whitespacesAndNewlines)
                if ["weightReps", "bodyweight", "time", "distance"].contains(tipo) {
                    row["tipo"] = tipo
                }
                if let reps = ex.reps, reps > 0 { row["reps"] = reps }
                if let peso = ex.peso, peso >= 0 { row["peso"] = peso }
                if let rest = ex.descanso_seg, rest >= 0 { row["descanso_seg"] = rest }
                if let ss = ex.superset { row["superset"] = ss }
                return row
            }
            guard !ejercicios.isEmpty else { return nil }
            var r: [String: Any] = [
                "nombre": routine.nombre,
                "ejercicios": ejercicios,
            ]
            let tag = routine.etiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty { r["etiqueta"] = tag }
            if let dia = routine.dia, (1...7).contains(dia) { r["dia"] = dia }
            return r
        }

        return [
            "schema": WorkoutProgram.currentSchema,
            "idioma": idioma,
            "unidad": unidad,
            "programa": spike.programa,
            "rutinas": rutinas,
        ]
    }
}

#endif
#endif
