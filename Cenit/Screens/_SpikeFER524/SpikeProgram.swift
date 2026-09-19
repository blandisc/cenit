#if DEBUG && CENIT_SPIKE_IALOCAL
#if canImport(FoundationModels)
import Foundation
import FoundationModels

// FER-524 spike DESECHABLE. Esquema @Generable que espeja cenit.workout.v1
// (WorkoutProgram / WorkoutRoutine / WorkoutExercise). El LLM SOLO transcribe
// lenguaje a campos; NUNCA calcula peso, progresión ni veredicto.

/// Un ejercicio de la rutina, espejo de `WorkoutExercise` (wire es-MX).
@available(iOS 26.0, *)
@Generable(description: "Un ejercicio de fuerza extraido del texto, sin inventar cifras")
struct SpikeExercise {
    @Guide(description: "Nombre del ejercicio tal como aparece en el texto, sin traducir (ej. sentadilla, press banca, RDL)")
    var nombre: String

    @Guide(description: "Tipo de medicion: weightReps, bodyweight, time o distance. Si no se dice, weightReps")
    var tipo: String

    @Guide(description: "Numero de series. Solo si el texto lo dice (ej. 4x8 → 4). Si falta, 1")
    var series: Int

    @Guide(description: "Repeticiones por serie. Solo si el texto lo dice (ej. 4x8 → 8). Si falta, nil")
    var reps: Int?

    @Guide(description: "Peso numerico en la unidad del programa. Parseo de lenguaje (80kg → 80), NUNCA inventar ni calcular. Si falta, nil")
    var peso: Double?

    @Guide(description: "Descanso en segundos. Parseo (2min → 120, 90s → 90). Si no se dice, nil. NUNCA sugerir")
    var descanso_seg: Int?

    @Guide(description: "Grupo de superserie (mismo entero = misma superserie). Si no hay superserie, nil")
    var superset: Int?
}

/// Una rutina (un dia del split), espejo de `WorkoutRoutine`.
@available(iOS 26.0, *)
@Generable(description: "Una rutina o dia del programa (ej. Empuje, Pierna)")
struct SpikeRoutine {
    @Guide(description: "Nombre de la rutina o dia (ej. Empuje, Jalon, Pierna A). Si el texto no lo nombra, usa un nombre corto descriptivo")
    var nombre: String

    @Guide(description: "Etiqueta informativa (ej. Lunes). Si no aparece, cadena vacia")
    var etiqueta: String

    @Guide(description: "Dia de la semana del plan: 1=lunes … 7=domingo. Si no se dice, nil")
    var dia: Int?

    @Guide(description: "Lista ordenada de ejercicios de esta rutina")
    var ejercicios: [SpikeExercise]
}

/// Programa completo, espejo de `WorkoutProgram` / cenit.workout.v1.
@available(iOS 26.0, *)
@Generable(description: "Programa de fuerza extraido de texto libre en espanol. Solo estructura lo dicho; no inventes series, reps, peso ni descanso")
struct SpikeProgram {
    @Guide(description: "Nombre del programa si el texto lo da; si no, cadena vacia")
    var programa: String

    @Guide(description: "Idioma del plan: siempre es")
    var idioma: String

    @Guide(description: "Unidad de peso del plan: kg o lb, segun el texto. Default kg")
    var unidad: String

    @Guide(description: "Rutinas del programa (una o mas)")
    var rutinas: [SpikeRoutine]
}

#endif
#endif
