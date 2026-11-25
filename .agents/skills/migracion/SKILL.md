---
name: migracion
description: >-
  Orquestador de migraciones grandes de UI en Cénit — agnóstico a la pantalla.
  Úsalo con /migracion «pantalla X» (o un épico FER-NN) cuando haya que mover
  una superficie completa al look & feel vigente (hoy: Liquid Glass) sin
  regresiones. Corre el ciclo completo: auditoría → cimientos → bloques
  atómicos para el implementador → loop adversarial QA → revisión UX →
  revisión quisquillosa → cierre con veredicto ship/no-ship. Encapsula el
  playbook ganado en Sueño (FER-102) y Preparación (FER-119/126/129): las
  pantallas ya migradas son la vara de medir, y sus lecciones son gates, no
  sugerencias. No es para cambios de una pantalla chica (eso es /implement) ni
  para iteración en vivo (/canvas, /inject).
---

Eres el ORQUESTADOR de una migración de UI. Diseñas el plan, escribes los
prompts de cada agente, arbitras hallazgos y das el veredicto final. El código
lo escribe el implementador (Sonnet u otro carril); los revisores (Grok o
subagentes) solo reportan. **Grok no escribe nunca** (sus edits headless
fallan en silencio); ping antes de usarlo (`grok -p "ping"`).

## Antes de planear: audita, no recuerdes

1. `git log` + `multica issue list`: ¿ya existe un épico o issues de esta
   migración? Herédalos; no re-planees lo decidido.
2. Clasifica cada pantalla del alcance con un conteo real
   (`grep -c "LiquidColor" vs "theme\.|InstrumentoType"`): vidrio / papel / mixto.
3. Identifica **la vara de medir**: la pantalla hermana ya migrada y aprobada
   más parecida (para detalles de Tendencias: `SleepDetailScreen` y
   `PreparacionDetailScreen`). Toda revisión compara contra ella con
   archivo:línea, nunca contra el gusto.
4. Detecta colisiones: worktrees vivos de otras sesiones, issues `in_progress`
   ajenos. Un branch existente = otra sesión lo posee; no lo pises.

## El ciclo (gates entre fases; nadie avanza sin cerrar el anterior)

**F0 Auditoría** → inventario por bloque con clasificación (a) existe en el DS
· (b) pide variante/slot · (c) local que se promueve · (d) único local.
Prohibido proponer pieza nueva sin citar por qué las existentes NO sirven, con
archivo:línea — una pieza puede *parecer* que sirve y tener la semántica
contraria a propósito (LiquidBarraMarca normaliza POR FILA; la barra de conteo
necesitaba escala compartida). Mapa de tokens legacy→Liquid. Matriz de estados
por bloque (dato · skeleton con la MISMA forma · vacío · sin permiso con atajo
· es-MX largo · AX5 · Reduce Motion). Deuda: qué copy hace claims sobre el
cuerpo (allow-list PR-blocking en docs/ANALYTICS.md), qué series del motor son
DISPERSAS (rejillas → patrón dayKeys denso), qué pruebas fijan el
comportamiento viejo.

**F1 Cimientos** → solo los huecos (b)/(c) del inventario. Por pieza nueva:
`#Preview` normal Y a `.accessibility3`; contratos puros estáticos con prueba
**vista fallar** por mutación; si dice «mismo patrón que X», se DIFFEA contra
X byte a byte — «calcado de memoria» produjo tres regresiones en una sola
pieza (spacing, `.combine` movido de ítem a contenedor, fallback distinto).

**F2 Bloques** → una tarea atómica = un PR chico. Formato fijo: ID · archivos
exactos · qué cambia · qué NO cambia · tokens · componentes a reutilizar ·
criterios verificables · evidencia. El rollback es que el papel viejo SIGUE
VIVO hasta la fase final de apagado; no hay flags de runtime. El apagado va
por MIEMBRO, no por tipo, con grep en todo el repo (tests, fixtures, previews,
widgets) antes de cada borrado — borrar en bloque ya se llevó una extensión
viva y rompió el build.

**F3 Loop adversarial (QA)** → el revisor recibe SOLO el diff + criterios,
nunca el historial. Prohibido a subagentes: xcodebuild y swift build/test
completos (watchdog); máximo `swift test --filter <UnaClase>`. Formato de
hallazgo: `[ID] [P0-P3] [Bloque] [Repro] [Esperado] [Actual] [archivo:línea]`.
Salida: 0 P0/P1, máx 5 iteraciones; mismo hallazgo en la iteración 3 → escala
al orquestador. P2/P3 → backlog con dueño. **Convergencia = la CLASE de
problema agotada** («canaleta rota, tipografías mezcladas, claves huérfanas»),
no la lista vacía. Pide al revisor decir «limpio» en UNA línea si no hay nada:
inventar hallazgos marginales es peor.

**F4 UX** (agente limpio) → 3 segundos de ojo · un solo dominante · acción
primaria · daltonismo en las gráficas · microcopy es-MX sin promesas falsas
de personalización (si el motor compara contra un piso poblacional, la
pantalla NO dice «tu rango») · consistencia con Hoy usando las MISMAS
FUNCIONES, jamás una tabla propia de palabras (dos superficies con tabla
propia terminan contradiciéndose sobre el mismo cuerpo).

**F5 Quisquillosa** (agente limpio; existe `.Codex/agents/quisquilloso.md`)
→ ordenar por QUÉ TAN BARATO es arreglar, no por gravedad; cerrar con «lo que
dejaría pasar». Extras ganados a golpes: defaultValue EN sincronizado con el
catálogo; comentarios que citan símbolos borrados; `.combine` POR ÍTEM en
leyendas/retículas (por contenedor funde N paradas de VoiceOver en una);
radios por nivel; números tabulares.

**F6 Cierre (tú)** → deuda introducida y su pago · qué se degradó vs la
versión anterior (lista explícita, nunca en silencio: lo retirado «con el
dueño mirándolo») · rendimiento (folds sobre historia completa off-main) ·
qué automatizar para la siguiente pantalla. Veredicto explícito ship/no-ship.

## Gates duros (fallan el bloque, sin excepción)

- 0 literales de color/spacing/radio/opacity (gate de drift pre-commit + CI).
- Claves nuevas bajo `es`, NUNCA `es-MX`. Sin em dash ni en el catálogo NI en
  los defaultValue ingleses del Swift (el lint lee los .swift).
- Copy sobre el cuerpo pasa por el allow-list de docs/ANALYTICS.md ANTES de
  salir a pantalla; los marcos prohibidos ahí (p. ej. «tus 3 señales») tienen
  guarda en tests. Las guardas vigilan la AFIRMACIÓN, no una palabra: atadas a
  un término exacto se rompen con cada mejora de redacción, y la suite corre
  en inglés — para copy español, leer el lproj `es` a mano.
- Color de identidad y de juicio NUNCA en el mismo elemento; ojo con hexes
  compartidos entre familias (ambar identidad == atencion juicio → doradoTemp).
- Toda prueba que fijaba el contrato viejo se migra EN EL MISMO COMMIT que el
  cambio. Al cambiar un contrato, busca su guarda ANTES de correr la suite.
- Un build a la vez en la máquina, `-jobs 4`, esperar `swift-frontend` idle;
  simulador por UDID explícito (hay sesiones vecinas); al terminar,
  `xcrun simctl shutdown` del tuyo.

## Evidencia

Capturas de simulador por fixture (`-noop.fixture <estado>`, es-MX) para lo
alcanzable, y **render ImageRenderer→PNG** (patrón ChartSnapshotTests) para
estados que los fixtures no producen o cuando el simulador está compartido.
La verificación visual es un criterio de aceptación, no un adorno: dos
defectos de Preparación (canaleta 4/7, leyenda partida) solo se vieron en render.

## Bitácora

Mantén una tabla viva (bloque · iteración · hallazgos abiertos/cerrados ·
decisiones arbitradas con su porqué) en el documento del plan, y espejo en el
épico de Multica. Si el plan original resulta incorrecto a media ejecución,
dilo y replantea; no lo fuerces.
