---
name: canvas
description: >-
  Sesión de iteración EN VIVO sobre una pantalla: Codex edita directo en el
  checkout canónico (~/code/noop) mientras el usuario ve el canvas de Xcode
  (#Preview) refrescarse en segundos con cada edición. Sustituye al gate de
  preview HTML para trabajo de pantalla cuando el usuario está presente: el
  canvas ES el preview que aprueba. Solo carril ligero (UI/layout/copy de una
  pantalla); nada de BLE/migraciones/matemática en vivo. Dispáralo con /canvas
  FER-NN o /canvas «pantalla X».
---

# /canvas — iteración en vivo con el preview de Swift

Modo de trabajo a dos manos: tú editas, el usuario mira el canvas de Xcode.
La velocidad viene de que editas **directo en `~/code/noop`** (donde su Xcode
ya está abierto) y el canvas recompila incremental en segundos. Es una
excepción CONSENTIDA a la disciplina de worktree — con las guardas de abajo.

## Alcance

- **Solo carril ligero**: UI, layout, copy, estados visuales de UNA pantalla.
- Nada de BLE, migraciones, matemática de analytics ni cambios cross-paquete
  en vivo — eso va por el flujo pesado normal (/pm → /arquitecto → /implement).
- El DNA sigue siendo ley: solo tokens/componentes de `CenitDesign`.
- En sesión /canvas, el gate de preview HTML (`show_widget`) de /ui e
  /implement **se sustituye por el canvas vivo**: la aprobación del usuario
  mirando el canvas es la aprobación de diseño.

## 0 · Guardas (antes de tocar nada)

1. **Una sola sesión canvas a la vez.** `git -C ~/code/noop status --porcelain`:
   si hay cambios sin commitear que NO sean los `.xcstrings` que Xcode
   reformatea solo, otra sesión (o el usuario) está a medias — **para y
   pregunta**, no pises nada.
2. **Cero `xcodebuild` completo durante el loop.** El canvas es el build.
   Si `swift-frontend` está corriendo (el usuario compila al iPhone), espera
   antes de ediciones grandes o `xcodegen generate`.
3. Los `.xcstrings` sucios del canónico **no se tocan ni se commitean**
   (salvo inserción mínima de claves nuevas de la feature, a mano).

## 1 · Arranque

1. `git -C ~/code/noop fetch origin` y crea la rama del issue **en el
   canónico** desde `origin/iOS` (rama `fer-NN-slug` del issue Multica; issue a
   In Progress). Si es exploración sin issue, rama `blandisc/canvas-<tema>`
   y formalízala con /pm si sobrevive.
2. Asegura que la pantalla tenga un `#Preview` útil:
   - Estado simple → `#Preview` normal en el archivo de la pantalla.
   - Estados con datos → celda en `Cenit/App/AppMap.swift` sembrada con
     `ScreenshotFixtures` (mismo patrón que el mapa de Hoy).
3. Dile al usuario, explícito: **abre el archivo del preview, activa el
   canvas (⌥⌘↩) y fíjalo con el pin** — así el canvas no se cambia cuando tú
   edites otros archivos. Confirma que ya lo ve antes de iterar.

## 2 · Loop de iteración

- Ediciones **chicas e incrementales**; cada guardado refresca el canvas en
  segundos. Anuncia en una línea qué va a ver cambiar.
- **Cada guardado debe compilar.** Un error de compilación mata el canvas;
  si vas a hacer un cambio en varios pasos, hazlo en un solo Edit o avisa.
- Archivos nuevos/borrados → `xcodegen generate` (Xcode recarga solo) y
  avisa al usuario que el canvas puede parpadear.
- **Commit chico y frecuente** (checkpoint barato, rollback fácil, y protege
  contra pérdidas — regla de la casa: commit temprano).
- Si tocaste `Packages/**`, valida con `swift build`/`swift test` del paquete
  (loop rápido); nunca con build completo del app.

## 3 · Cierre

**Aprobado** → flujo normal de entrega: CHANGELOG, commit final (`git add`
SOLO tus archivos), push, PR a `iOS` (`Closes FER-NN`), squash-merge, issue a
Done, borrar rama, y regresar el canónico: `git -C ~/code/noop checkout iOS
&& git -C ~/code/noop merge --ff-only origin/iOS`. El canónico NUNCA se queda
parado en la rama de la sesión.

**Abortado / a medias** → commitea lo que haya en la rama, púshala, y regresa
el canónico a `iOS` limpio. Nada de trabajo sin commitear abandonado en el
canónico.
