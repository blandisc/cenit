# Ola 0 · Decidir y cortar — spec

Decisión: `docs/DECISIONS.md` 2026-10-15 «Camino C+». Plan: `docs/_plan-cenit-fuerza-2026-10-15.md`.
Tres issues de código, en este orden (B → C → E). Implementa Sonnet; verifica con `Tools/verify.sh`.

## B · La raíz es la sesión (tres estados)

**Objetivo.** Al abrir Cénit el usuario está a un toque de su primera serie. Una sola raíz, sin dock.

**Dónde vive.** Raíz nueva `Cenit/App/FuerzaRootView.swift` (nombre probable; el host es
`CenitApp/App/RootTabView.swift` / `TabRouter.swift`: la raíz nueva lo reemplaza como primera vista; el
dock `InstrumentTabBar` deja de montarse). Reusa, no reescribe: el héroe y la rutina de hoy de
`EntrenarView` / `Cenit/Screens/Entrenar/EntrenarHubHeroe.swift` y `ProgramServing`; la sesión en vivo
`LiveStrengthSheet` + `StrengthSessionModel`; el acta `ReceiptPrinterScreen`.

**Estados.**
1. *Antes* — si hay rutina para hoy: nombre, músculos, duración estimada, lista de ejercicios con su
   «siguiente paso» en la forma que ya existe (peso de la última vez y, si `ProgressionPlanner` lo propone,
   la subida; copy actual «Hoy mantengo…/sube…»). Un botón primario «Empezar». Si no hay rutina: la puerta
   de plan que ya existe (plantillas / importar / crear), sin pasos nuevos.
2. *Durante* — la sesión en vivo tal cual existe hoy (Focus, discos, cambiar ejercicio, descanso).
3. *Después* — el acta de la sesión (ticket) con «Listo» que regresa a *Antes* (ya con la rutina de
   mañana o «hoy ya entrenaste»).

**Hojas desde la raíz** (menú o botones secundarios en *Antes*, SIN pestañas): «Plan» (`WeeklyPlanEditorView`
y rutinas), «Progreso» (`WorkoutHistoryScreen`, marcas, biblioteca), «Ajustes» (`AjustesView`, podada en E).

**Qué queda sin puerta** (no se borra en B; se borra en E): Hoy/`TodayView`, `CuerpoView`, Tendencias,
Hoja, detalles de métrica (sueño, estrés, temperatura, esfuerzo, preparación), Comparar, edades, ciclo,
Respirar, Guardián, Explorador, Fuentes de datos, aviso matutino, historial FA, widgets de «la palabra»,
onboarding de seis actos (B lo deja como está; se reemplaza en ola 1). `AppMap`/fixtures de capturas: los
nodos de pantallas sin puerta se marcan omitidos para que el gate R3 no exija su fixture.

**Fuera de alcance.** Motor «siguiente paso» nuevo, onboarding nuevo, borrado de archivos, Watch.

**Criterios de aceptación.**
- [ ] Arranque en frío con rutina asignada: la primera pantalla muestra la rutina de hoy y «Empezar»; no
      hay barra de pestañas en ninguna pantalla.
- [ ] Toque en «Empezar» → sesión en vivo; terminar → acta; «Listo» → *Antes*.
- [ ] Sin rutina: la primera pantalla ofrece plantilla / importar / crear y, al elegir, cae en *Antes*.
- [ ] Plan, Progreso y Ajustes se abren desde *Antes* y regresan.
- [ ] Ninguna navegación alcanza las pantallas listadas «sin puerta» (gate de claves nav alcanzables en verde).
- [ ] Widget de rutina y Live Activity de serie siguen funcionando (deep link cae en *Antes*/*Durante*).
- [ ] `Tools/verify.sh` en verde (paquetes tocados + app build-for-testing); gates de diseño e i18n en verde.
- [ ] CHANGELOG con la entrada de usuario; `docs/ARCHITECTURE.md` actualizado si cambia la raíz de navegación.
**Carril:** pesado (feature con lógica de navegación nueva). **Etiquetas:** Feature, UI.

## C · Apple Salud a cuatro tipos, permiso tardío

**Objetivo.** La app pide solo: escribir entreno (+ energía activa), leer FC (en sesión), FC en reposo y
sueño. Y lo pide al cerrar la primera sesión, no al abrir la app.

**Dónde vive.** `CenitApp/Health/HealthKitBridge.swift` (`readTypes` / share types), descripciones de uso
en `Cenit/Resources/InfoPlist.xcstrings` (y las del Watch), el punto donde hoy se dispara la autorización
(onboarding / `AppModel`). Las lecturas que dependían de los tipos retirados (VFC, temperatura, SpO₂,
pasos, VO₂máx, energía en reposo, etc.) dejan de pedirse: si el código que las consume sigue en el árbol
sin puerta, no debe pedir permiso ni disparar consultas en arranque.

**Criterios.**
- [ ] El diálogo de Salud lista exactamente esos cuatro tipos de lectura y los dos de escritura.
- [ ] En arranque limpio no aparece el diálogo; aparece al terminar la primera sesión (una vez; «Ahora no»
      lo deja para Ajustes → Apple Salud).
- [ ] Sin permiso, la sesión y la progresión funcionan completas (ya era así: hilo «sin Salud»).
- [ ] Las descripciones de uso enumeran exactamente lo que se pide (5.1.3(i)).
- [ ] `verify.sh` en verde. CHANGELOG.
**Carril:** pesado (datos on-device). **Etiquetas:** Datos.

## E · Matriz de alcanzabilidad y barrido 1

**Objetivo.** Todo archivo de `Cenit/`, `CenitApp/`, `CenitWidgets/` que no sea alcanzable desde la raíz
nueva se borra; lo mismo para los símbolos de `CenitAnalytics` que ya nadie usa. Build verde y suite verde.

**Método.** Escribir `docs/specs/fuerza-v1/matriz-alcanzabilidad.md` (pantalla → alcanzable sí/no → acción)
ANTES de borrar; borrar por lotes con `verify.sh` entre lotes; actualizar `docs/FEATURES.md`, el registro
de enseñanza (`CenitEnsenanza`), el mapa vivo y las fixtures. Criterio de cierre de FER-380: `strings` del
binario sin «readiness», «preparación», «recovery»; `swift test` de cada paquete verde; `CenitUnitTests`
verde en simulador. `AjustesView` pierde las secciones de monitoreo, aviso matutino y fuentes de datos.

**Fuera de alcance.** `CenitDesign` (se poda en ola 5). `CenitImport` se borra solo si ya nadie lo importa
tras el barrido; si queda la lectura de sueño/FC en reposo ahí, se deja el mínimo.
**Carril:** pesado. **Etiquetas:** Infra.
