---
name: inject
description: >-
  Sesión de iteración EN VIVO sobre la app corriendo: Codex edita directo en
  el checkout canónico (~/code/noop) y la pantalla del Simulador cambia en
  segundos SIN recompilar, con los datos y el estado reales de la sesión. Es el
  hermano de /canvas — canvas itera un #Preview aislado, inject itera la app de
  verdad (navegación, datos de la DB, estado vivo). Solo carril ligero
  (UI/layout/copy de una pantalla). Dispáralo con /inject FER-NN o /inject
  «pantalla X».
---

# /inject — iteración en vivo sobre la app corriendo

Tú editas, el usuario mira el Simulador cambiar solo. La diferencia con
`/canvas` es qué estás mirando:

| | `/canvas` | `/inject` |
|---|---|---|
| Superficie | `#Preview` aislado | la app corriendo |
| Datos | fixtures | la DB real, estado vivo |
| Ciclo | recompila incremental | **no recompila nada** |
| Cuesta | segundos | segundos |

Usa `/inject` cuando el estado importa (una pantalla a media sesión, datos
reales, navegación) y `/canvas` cuando quieras un estado fijo y aislado.

Igual que `/canvas`, editas **directo en `~/code/noop`** — es una excepción
CONSENTIDA a la disciplina de worktree, y aquí es estructural: la inyección
solo alcanza al checkout desde el que se compiló la app corriendo.

## Alcance

- **Solo carril ligero**: UI, layout, copy, estados visuales de UNA pantalla.
- Nada de BLE, migraciones, matemática de analytics ni cambios cross-paquete
  en vivo — eso va por el flujo pesado (/pm → /arquitecto → /implement).
- El DNA sigue siendo ley: solo tokens/componentes de `CenitDesign`.
- La aprobación del usuario mirando el Simulador sustituye al gate de preview
  HTML (`show_widget`) de /ui e /implement.

## 0 · Guardas

1. **Una sola sesión a la vez** sobre el canónico. `git -C ~/code/noop status
   --porcelain`: si hay cambios sin commitear que no sean el churn conocido de
   `.xcstrings`, otra sesión está a medias — **para y pregunta**.
2. **Cero `xcodebuild` completo durante el loop**, y nunca mientras el usuario
   compila (`pgrep swift-frontend`). Dos builds a la vez = OOM de la máquina.
3. Los `.xcstrings` sucios del canónico no se tocan ni se commitean.

## 1 · Arranque — verifica, no supongas

Antes de prometer nada, comprueba que la cadena está viva:

```bash
pgrep -lf InjectionNext                      # la app debe estar corriendo
pgrep -lf 'Cenit.app/Cenit$'                 # y la app del Simulador también
ps eww <pid> | tr ' ' '\n' | grep INJECTION  # INJECTION_PROJECT_ROOT presente
```

Si falta algo: Xcode tiene que estar **lanzado desde InjectionNext** (menú
`Launch Xcode`), y el esquema `Cenit` lleva `INJECTION_PROJECT_ROOT=$(SRCROOT)`
(ya está en `project.yml`) — sin eso solo reacciona a un ⌘S dentro de Xcode y
tus ediciones son invisibles.

**Luego revisa el cableado de la pantalla** (ver §2). Si los hooks están mal
puestos, no hay nada que iterar hasta arreglarlo con UN rebuild.

## 2 · La regla que hace o rompe todo

> Los hooks de Inject van en la vista **NO privada** más externa del archivo.

`@ObserveInjection` + `.enableInjection()` colgados de un `private struct` son
**inertes en silencio**: la inyección reporta `✅ Hot reload complete` y la
pantalla no cambia. Swift emite los miembros de un tipo `private` como símbolos
locales y `-interposable` solo alcanza los globales.

No hace falta tocar niveles de acceso: el dylib inyectado trae una copia fresca
del archivo **completo**, tipos privados incluidos. Basta interponer un símbolo
global de ese archivo — típicamente el `body` del struct internal que construye
la vista privada — para que arme la copia nueva con todo adentro. Patrón de
referencia: `Cenit/Screens/EntrenarView.swift`.

Comprobar si un símbolo es alcanzable (`T` = global, `t` = local):

```bash
DY=~/Library/Developer/Xcode/DerivedData/Cenit-*/Build/Products/Debug-iphonesimulator/Cenit.app/Cenit.debug.dylib
nm $DY | grep "5Cenit12EntrenarViewV4body" | awk '{print $2}'
```

⚠️ Mide sobre **`Cenit.debug.dylib`**, no sobre `Cenit.app/Cenit`: en Xcode 16+
el ejecutable son ~57K de puro lanzador y el código real vive en el dylib.

**«Unhide Symbols» NO sirve para esto.** Es para thunks de argumentos por
defecto, no para tipos `private`. No gastes tiempo ahí.

## 3 · Loop de iteración

- Ediciones **chicas e incrementales**. Anuncia en una línea qué va a cambiar.
- **Cada edición debe compilar.** Un error deja el dylib viejo corriendo y la
  pantalla mintiendo.
- **Verifica que aterrizó** — no confíes en el log, confía en la pantalla:

```bash
xcrun simctl io booted screenshot /tmp/probe.png    # y LÉELO
```

  Si dudas, confirma que hubo inyección nueva:
  `ls -t <container>/tmp/eval_injection_*.dylib | head -1`

- **Commit chico y frecuente** (checkpoint barato, rollback fácil).

## 4 · Lo que la inyección NO puede hacer

Estos cambios necesitan un rebuild — hazlos de golpe y avisa al usuario:

- agregar, quitar o renombrar **propiedades con almacenamiento** (incluye
  agregar `@ObserveInjection`, que es una propiedad envuelta);
- cambiar **firmas** de funciones;
- agregar o reordenar métodos en una clase no-`final`;
- archivos nuevos o borrados → `xcodegen generate` + rebuild.

Cambiar el **cuerpo** de una función o propiedad computada: eso sí, siempre.

## 5 · Trampas conocidas de este repo

- **Los worktrees roban el escaneo de logs.** `INJECTION_PROJECT_ROOT` apunta a
  la raíz del repo y los worktrees viven bajo `.Codex/worktrees/`. Peor: el
  modo de log-parsing elige el DerivedData compilado **más recientemente**, así
  que un build en un worktree se lo roba al canónico y aparece
  `Could not locate command`. Mapea con:
  `plutil -extract WorkspacePath raw ~/Library/Developer/Xcode/DerivedData/Cenit-*/info.plist`
- **El stdout de InjectionNext va a la consola de Xcode**, no al log del
  simulador — `simctl log show` no lo captura. Si necesitas el log, pídeselo
  al usuario.
- Un `git pull`/`stash pop` reescribe muchos archivos de golpe y el watcher
  intenta inyectarlos todos: esperado, es ruido.

## 6 · Cierre

**Aprobado** → flujo normal de entrega: CHANGELOG si es visible al usuario,
commit final (`git add` SOLO tus archivos), push, PR a `iOS` (`Closes FER-NN`),
squash-merge, issue a Done, borrar rama, y regresar el canónico:
`git -C ~/code/noop checkout iOS && git -C ~/code/noop merge --ff-only origin/iOS`.
El canónico NUNCA se queda parado en la rama de la sesión.

**Abortado / a medias** → commitea lo que haya en la rama, púshala, y regresa
el canónico a `iOS` limpio.

Ver también: `docs/BUILD.md` § hot reload, y `/canvas` para iterar un `#Preview`.
