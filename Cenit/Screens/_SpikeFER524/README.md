# FER-524 · Spike DESECHABLE · IA local

**Investigacion, no produccion.** Prototipo aislado para medir si Foundation
Models on-device convierte texto/foto libre de una rutina (es-MX) en estructura
tipada `cenit.workout.v1` con calidad y latencia usables.

Todo vive aqui. Borrable con:

```bash
git rm -r Cenit/Screens/_SpikeFER524/
# y quitar la fila `#if DEBUG && CENIT_SPIKE_IALOCAL` en DataSourcesView.swift
```

Cero cambios a `Packages/**`. Cero escritura a la DB. Offline total.

## Como activarlo

1. En el scheme **Cenit** (Debug), agrega el flag de compilacion:

   ```
   SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) CENIT_SPIKE_IALOCAL
   ```

   O en *Build Settings → Swift Compiler - Custom Flags → Active Compilation Conditions*
   anade `CENIT_SPIKE_IALOCAL` solo a Debug.

2. Requiere Xcode/SDK con `FoundationModels` (iOS 26+ / Apple Intelligence).
   El director compila con ese SDK; este spike **no** se construye en el lane
   sin el framework (`#if canImport(FoundationModels)`).

3. Corre en un iPhone fisico con Apple Intelligence disponible (15 Pro / 17 Pro).
   Simulador puede servir para calidad en Mac Apple Silicon; la latencia de
   Simulador **no** es representativa.

4. Abre la app → Fuentes de datos → fila **«Spike FER-524 · IA local (dev)»**.

## Flujo

```
texto libre  ─┐
              ├→ LanguageModelSession.respond(generating: SpikeProgram)
foto ─OCR─────┘         ↓
              SpikeProgram → wire JSON cenit.workout.v1
                            ↓
              WorkoutProgramImporter.parse  (REAL, read-only)
                            ↓
              WorkoutExerciseReconciler     (REAL, read-only)
                            ↓
              muestra JSON + RoutineExercise[] en memoria + latencia ms
```

A/B vs baseline BYO-LLM (`WorkoutImportView`): mismo downstream, distinto
productor (on-device vs archivo que trae el usuario).

## Rubrica de medicion

Sobre el corpus embebido (`SpikeCorpus`, ~18 items) y rutinas reales del dueno:

| Metrica | Como | Meta orientativa (arquitecto) |
| --- | --- | --- |
| Resolucion de nombre | tras reconciler → `exerciseId` | ≥ 90 % |
| Exactitud series/reps/peso | diff vs lo dicho en el texto | ≥ 85 % |
| Alucinacion de cifra | cifra en salida ausente en entrada | ~ 0 (NO-GO si aparece) |
| Parse-valido | pasa `WorkoutProgramImporter` | ≥ 95 % |
| Latencia LLM (device) | cronometro de la pantalla | usable en 15 Pro (≈ 3–5 s tipica) |
| Latencia OCR | medida aparte | reportar, no mezclar con LLM |

**Regla de oro:** el modelo SOLO transcribe lenguaje («80kg» → peso 80 es
parseo). NUNCA calcula peso semilla, progresion ni veredicto.

Casos trampa del corpus (`sin-peso`, `solo-nombres`): si el modelo inventa
series/peso, es alucinacion → NO-GO.

## Go / no-go (del arquitecto)

**GO** si, en es-MX sobre el corpus: resolucion ≥ 90 %, exactitud campos ≥ 85 %,
alucinacion de cifra ~ 0, parse-valido ≥ 95 %, latencia usable en **15 Pro**,
y aporta sobre el baseline (texto/foto libre es lo que BYO-LLM no hace).

**NO-GO** si: cualquier cifra inventada/calculada; exactitud bajo el piso;
latencia inusable en 15 Pro; o **solo** el tier 20B (17 Pro) alcanza calidad.

Si GO → issues de seguimiento para superficies v1.x (crear rutina por
texto/foto, acta en palabras, buscar/sustituir). Este prototipo se descarta.

## Que mide el dueno en device

- Calidad en 15 Pro (piso 3B) y, si tiene, 17 Pro.
- Latencia cold/warm real (el cronometro de la UI).
- Disponibilidad: la pantalla reporta `SystemLanguageModel.availability`.

## Archivos

| Archivo | Rol |
| --- | --- |
| `SpikeProgram.swift` | `@Generable` espejo de cenit.workout.v1 |
| `SpikeLLMSession.swift` | availability + `respond(to:generating:)` |
| `SpikeProgramAdapter.swift` | wire JSON → importer → reconciler RO |
| `SpikeVisionOCR.swift` | `VNRecognizeTextRequest` es-MX |
| `SpikeFER524View.swift` | UI DEBUG |
| `SpikeCorpus.swift` | ~18 rutinas es-MX |
| `README.md` | este archivo |

## Restricciones

- `#if DEBUG && CENIT_SPIKE_IALOCAL` en todo.
- `import FoundationModels` / Vision solo bajo `canImport`.
- No toca produccion, paquetes ni motores.
- No PR de feature; rama de spike.
