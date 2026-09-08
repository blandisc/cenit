# Decisiones del dueño — no re-litigar

Registro versionado de las decisiones de producto y proceso ya tomadas por el dueño.
Regla: antes de proponer un cambio que toque uno de estos temas, lee su entrada; si la
propuesta la contradice, la conversación empieza por «quiero revertir la decisión X»,
no por re-abrirla como si fuera nueva. Toda decisión nueva del dueño se **añade aquí en
el mismo PR** que la implementa (una línea basta: fecha, decisión, por qué).

## Producto

- **2026-08-30 · Primer uso de Entrenar = «el split decide» (FER-251, opción A).** Una
  acción primaria (los 3 chips, cada uno abre SU grupo con la primera rutina en preview y
  el CTA «Usar este plan»); «Desde cero» e «Importar» como filas secundarias; ningún tap
  único escribe rutinas ni agenda la semana. Consecuencia directa (asunción del director,
  validada por QA): `CrearPlanScreen` («Tres caminos», FER-137) se ARCHIVÓ — sus tres
  caminos quedaron accesibles en directo y la pantalla quedó sin ninguna puerta de entrada.
  Revivirla es una reversión explícita de esta entrada, no un accidente.

- **2026-06 · Cero banda.** La banda de terceros nunca existió para los usuarios de Cénit: la
  app es 100% Apple Health. Ningún copy, doc o feature nuevo la menciona como vigente
  (épico FER-1003; axioma «mundo nuevo cero banda»).
- **2026-07 · Solo iOS.** Las demás plataformas se retiraron; el app target es `Cenit`.
- **2026-07 · Veredicto v4.** Las 7 decisiones del plan del veredicto quedaron fijadas
  (ver memoria «plan-veredicto-v4-handoff»); el umbral del héroe por ejes NUNCA usa |z|≤1.
- **2026-08 · Hoy.** Tema por hora RETIRADO (FER-398). Cosmos APAGADO (2026-08-06).
  Las 8 decisiones de la auditoría de Hoy (2026-08-16, FER-73…80) y las 7 previas
  (2026-08-13) no se re-abren.
- **2026-08 · Sheets Liquid.** Las 5 excepciones del dueño al rediseño de sheets (FER-29)
  no se tocan.
- **2026-08-22 · Preparación.** «Tus tres señales» PROHIBIDO como título; el ámbar de
  identidad = ámbar de juicio (doradoTemp); `.combine` por ítem (FER-129).
- **2026-08-24 · Entrenar post-épico.** Biblioteca, tope de descanso 3:00 y Guía quedan
  en statu quo; QUEDABAN (FER-147), renombres (FER-148/150) y Progreso % con gates
  CSO+CDO (FER-149) ya ejecutados.
- **2026-08 · Anomalías vitales:** solo FC en reposo (FER-48).
- **Señales:** temperatura de piel reemplaza a SpO₂.
- **2026-08-28 · Foco gestos (FER-187).** Además del «⤢» y el grabber-tap: (a) tap del cromo
  sin celdas de la tarjeta activa (thumb + nombre; no las filas/TapZones de peso-reps) entra
  a foco; (b) arrastre del grabber ⌄ hacia abajo sale. El DragGesture vive SOLO en el
  grabber de `FocoCabecera`, nunca sobre el ScrollView de Foco.
- **2026-09-03 · Respaldo por iCloud (auditoría de estrés).** La DB de salud SÍ se respalda
  por iCloud/dispositivo — **NO se excluye** (`isExcludedFromBackup` no se pone en
  `StorePaths`). El dueño prioriza que el historial se restaure al migrar de iPhone sobre la
  exclusión estructural. Un audit que vuelva a marcar «DB no excluida del backup» describe
  algo INTENCIONAL; revertir es reabrir esta entrada. (Cénit no hace llamadas de red propias;
  el respaldo es el de iCloud del propio usuario, cifrado en su cuenta — más el export/import
  local de `DataBackup`.)
  **Reversión parcial 2026-08-29 (orden del dueño, #1356):** el punto (a) queda DEROGADO — el tap
  del cromo (thumb + nombre) de la tarjeta activa YA NO entra a foco; **abre el DETALLE del
  ejercicio** (`detailExercise`). El foco queda SOLO en el «⤢» y en el «Enfoque» del «···».
  El punto (b) del grabber sigue vigente.
- **2026-08-30 · CTA de arranque = una sola voz** (FER-249). Verde de marca vía
  `LiquidGlassButton(.primary)` en TODOS los contextos, incluido día de descanso. El ámbar
  `dataStrain` queda como excepción nombrada SOLO en el pill «+ Serie». «Hoy subes» habla en
  `verdeCarga` (identidad de carga), nunca `verdePrimario`.
- **2026-09-06 · Identificadores congelados de ARCHITECTURE §2, DESCONGELADOS** (FER-398).
  La ruta en disco pasa a `Cenit/cenit.sqlite` y las preferencias al prefijo `cenit.*`, con
  **una migración única al arrancar** (`StorePaths.migrateLegacyContainerIfNeeded` —un rename
  atómico de carpeta, luego sidecars primero y archivo principal al final, reanudable— y
  `PrefMigration.migrateLegacyKeysIfNeeded`, copiar-y-luego-borrar sobre `PrefKey.allCases`).
  Estaban congelados porque renombrarlos a secas reseteaba una instalación viva; con la
  migración eso deja de ser cierto, y la app deja de llevar el nombre del proyecto anterior en
  su propio disco. Los tags de esquema `noop.workout.v1` / `noop.diet.v1` NO entran aquí: son
  contrato de cable de `StrandImport` y se mueven con ese paquete.

## Proceso

- **2026-08-28 · Cerrar es parte de entregar.** El issue se pasa a `done` en el **mismo
  paso** que se borra la rama, no como trámite posterior; y todo cierre (de issue en
  `/implement`, de corrida en `/orquesta`) corre `Tools/cleanup.sh --apply`. Origen: la
  retro del 2026-08-28 encontró 3 issues verdes-pero-mentirosos (hasta 26 días) y 7.9 GB
  en 22 worktrees fósiles. La receta de poda que ya existía era **ciega por diseño**:
  detectaba ramas entregadas con `merge-base --is-ancestor`, que el squash-merge —el
  único modo de merge del repo— invalida siempre. La señal buena es «la rama tuvo
  upstream y ya no está en `origin`» (FER-194).
- **2026-07-11 · Orquestación:** preview solo frena en pantalla nueva/rediseño;
  auto-merge a iOS salvo riesgo; el alcance por corrida lo fija el dueño al invocar.
- **2026-08-25 · Contrato de flujo:** topes de vueltas adversariales (2 ligero / 3
  pesado, excepción: datos corruptos o copy que miente sobre el cuerpo); lotes, no gotas;
  en vivo por default para retoques visuales; verificación proporcional; `/orquesta`
  default para trabajo multi-paso con Fable/Opus orquestando, Sonnet implementando,
  DeepSeek en lo mecánico y Grok SOLO revisando; tablero obligatorio en toda corrida.
- **2026-08-27 · Reversión parcial del reparto de modelos (orden del dueño):** Grok
  VUELVE al carril de implementación — «para ir más rápido, paralelizar y ahorrar
  tokens» — SOLO para lotes bien especificados (componentes contra mock, wiring,
  trabajo de paquete con spec de 5 partes cerrado) y SOLO vía `grok-lane.sh`
  (worktree determinista + permisos que sí escriben + prohibido compilar; la
  verificación la corre el director). Lo delicado (migraciones, motores, BLE,
  concurrencia) sigue en Claude, y cuando Grok teclea, la revisión adversarial la
  hace OTRA familia — Grok nunca se auto-revisa. Revierte parcialmente el punto
  «Grok SOLO revisando» del contrato 2026-08-25; la falla de agosto tenía causa
  raíz de tooling (hook-discovery + acceptEdits), resuelta por el wrapper.
- **2026-08-31 · Reparto afinado: implementa siempre Sonnet o Grok, Grok primero.** Quien
  teclea es SIEMPRE Sonnet o Grok, con **preferencia a Grok** (más barato, buen implementador,
  otra familia de modelos). **El carril pesado-delicado** (BLE/protocolo, migración DB,
  motor/mates, concurrencia, invariantes, safe-trim) **se queda en Claude** — esto CONFIRMA el
  2026-08-27, no lo revierte. **DeepSeek sale del reparto por defecto**: deja de ser carril
  estándar y queda como opción experimental solo si el dueño lo pide (`deepseek-lane.sh` sigue
  vivo). Afina el 2026-08-27; se implementa en la skill `/orquesta`.
- **2026-09-03 · «Prueba roja primero» es paso ejecutado de `/qa`, no nota.** Una prueba de
  comportamiento nueva no cuenta como criterio cumplido hasta demostrarla ROJA en el commit base
  (ver el fuente viejo → correr solo esa prueba → FAIL → restaurar); verde sin el cambio = FAIL por
  «test verde-de-nacimiento». El principio ya estaba en memoria y aun así salieron 3 pruebas así en
  la ola 1 → se sube a paso ejecutado en la skill `/qa` y a la auto-verificación del implementador.
- **2026-09-03 · Afinación del reparto: las pantallas del sistema de diseño NO van a Grok.**
  Una pantalla que toca símbolos de `CenitDesign` y/o el catálogo `Localizable.xcstrings` se rutea
  a **Sonnet**, no a Grok. Grok headless no compila ni grepea confiable y en UI hace dos fallas
  estructurales (no aleatorias): **inventa símbolos** (p. ej. `LiquidMotion.interactive`) y
  **re-serializa el catálogo entero**. La mitigación «grepea cada símbolo antes de usarlo» (FER-299)
  ya existía y **volvió a fallar** en la ola 1 de Entrenar → se sube de mitigación a regla de ruteo.
  Grok se queda con lógica/CSV/wiring/mecánico bien especificado (su acierto en esta ola fue el
  lector CSV, FER-328); «Grok primero» sigue para todo lo demás. Afina el 2026-08-31, no lo revierte.
  Evidencia: E9 (FER-333, #1480) no compiló + re-serializó el catálogo → re-ruteado a Sonnet; E3
  (FER-330, #1479) re-serializó `Localizable.xcstrings`. Se implementa en la skill `/orquesta`.
- **2026-09-04 · Re-fundamentar el spec PESADO sobre HEAD vigente es paso ejecutado de `/orquesta`, no nota.**
  En corridas largas multi-peer, `origin/iOS` avanza decenas de commits entre el taller de `/arquitecto` y
  la implementación; un spec correcto al escribirse **caduca**. Antes de teclear una pieza pesada se verifican
  los **símbolos-ancla en el árbol vigente** (el tipo/columna/eco/wire que va a tocar), no en el spec, y si
  cambiaron se re-corre `/arquitecto` sobre el HEAD del día. El mitigante existente (memoria
  `subagentes-grounding-worktree-viejo` + «fetch fresco» de `ui`/`ux`) no lo previno: cubre la caducidad al
  AUTORAR o para subagentes de juicio, no el spec pesado que teclea el director sobre su worktree, ni cuando
  la propia ola previa mergea y mueve el árbol. Corolario: si la pieza cruza un límite de serialización/módulo,
  la verificación del spec incluye un **probe Codable** (`swift <archivo>` contra los tipos reales) antes de
  comprometer el acoplamiento. Evidencia (ola 2 de Entrenar): caducaron DOS specs — C1 (el wire `CenitShared`
  era domain-free, no llevaba los tipos del motor; Decisión A cerrada con probe, #1513) y C4 (el eco YA existía
  en `UnifiedWorkoutHistory`, mergeado por la ola previa #1502). Misma escalación que «prueba roja» y el ruteo
  de Grok (2026-09-03). Se implementa en la skill `/orquesta`.
- **2026-08-31 · Dos agentes nuevos + retro que aprende sin frenar.** (a) `criterio` —
  subagente-espejo del dueño (lee DECISIONS.md + CLAUDE.md + memoria) que el loop consulta para
  dudas de gusto reversibles en vez de adivinar o frenar; marca 🚩 lo que sí requiere al dueño.
  (b) `componente` — subagente-autor del sistema de diseño: crea la pieza nueva en `CenitDesign`
  (verifica CATÁLOGO, preview + OK, `#Preview`, regenera CATÁLOGO/CENSO) en vez de inventarla
  inline. (c) `retro` — Fase 5 de `/orquesta`, **post-entrega y en background, NUNCA gate**: el
  código se entrega y se anuncia hecho ANTES de retro. Destila aprendizajes con **vara alta**
  (general + accionable + nuevo), prefiere gate/lint sobre nota, cap de 3, y descartar es lo
  sano. Objetivo: hacer de `/orquesta` un loop que mejora sin acumular basura ni ralentizarse.
- **2026-08-26 · Build del iPhone:** sigue siendo manual y al ritmo del dueño — no se
  agenda ni se automatiza.
- **2026-08-30 · El build del iPhone es OPCIONAL, no un paso del flujo (aclara 2026-08-26).**
  El flujo termina en «mergeado a `origin/iOS` + sincronizado a `~/code/noop`». Compilar e
  instalar en el iPhone desde Xcode es cosa del dueño, cuando él quiera: nunca es un gate,
  nunca cierra ni «completa» un cambio, nunca se agenda ni automatiza. Ningún flujo, skill ni
  rutina lo añade como último paso ni trata un cambio como inconcluso hasta estar en el teléfono.
- **DNA:** «Instrumento diurno» es canónico; el sistema oscuro es legacy (mantener, no
  extender). **Superseded 2026-08-29** por «Un solo vidrio: unificar en Liquid Glass · El Eje»
  (abajo); el sistema oscuro sigue retirado.
- **2026-08-29 · Un solo vidrio: unificar en Liquid Glass · El Eje** (épico FER-229). Un solo
  lenguaje de ADN: la receta de vidrio teñido de El Eje bajo el nombre «Liquid Glass». Lienzo
  blanco (ya decidido el mismo día). Dos regímenes, una receta: **Mosaico** (muchos módulos /
  Entrenar: cada tesela se tiñe con su identidad) y **Sobrio** (default; un dato dominante — el
  color vive en el número y su gota, superficie clara). Cuatro colores que no se mezclan:
  identidad de señal · identidad de módulo · juicio (verde/ámbar/rojo del veredicto) · voz de
  marca (verde CTA); `verdeCarga` ≠ verde del veredicto (`verdePrimario`). «Instrumento diurno /
  papel cálido» queda muerto como marco y en migración (punto de vista absorbido; pantallas de
  papel migran; componentes de papel se borran al migrar su último consumidor). Watch OLED es la
  única excepción viva del sistema oscuro retirado. Nombre fundido en API: `liquidGlass` +
  `LiquidTono`.
- **2026-08-29 · Fondo de pantalla blanco (revierte parcialmente el «papel cálido» del DNA):**
  el lienzo de TODAS las secciones (Hoy, Tendencias, Entrenar, Ajustes) pasa de papel cálido a
  blanco, vía el componente compartido `pantallaFondo` (`CenitColor.pantalla`). El papel cálido
  (`InstrumentoTheme.paper`) sigue vivo para tarjetas, hojas y toolbars; Hoy conserva sus
  partículas (`LiquidAtmosfera`) sobre el mismo blanco. Orden del dueño en sesión /inject.
- **2026-09-03 · Modo oscuro: se REABRE «lienzo canónico blanco» (revierte parcialmente la decisión de arriba).**
  Cénit tendrá tres estados de apariencia — Seguir al sistema (default) · Claro · Oscuro — épico **FER-343**
  (sub-issues FER-344…FER-357). El modo oscuro NO es un volteo de color: rediseña lienzo, vidrio, sombras
  (`LiquidElevation`), héroe Metal y gráficas para suelo negro, con contraste AA verificado por prueba (host
  macOS). `CenitColor.pantalla` y el stack `LiquidColor` pasan a resolver por modo (contrato de A1/FER-345);
  `OKLab.darkened`/`tonoCampo` son algoritmos solo-para-claro y se re-encaminan por un helper mode-aware.
  Decisiones del dueño: **D1** = tonos de dato oscuros SOLO en el iPhone (el Apple Watch no se toca; acota
  «el dato no cambia por pantalla» a «no cambia dentro de un mismo aparato/modo»); **D2** = widgets y Live
  Activity siguen el modo del sistema (delta a la regla 2026-09-03 que los anclaba a `fondoAlto`; la Dynamic
  Island se queda en `LiquidOLED`); **D3** = onboarding/entrada/Términos también en oscuro. Plan blindado con
  Grok (8 rondas adversariales → CONVERGED). Por qué: uso nocturno/OLED y paridad con el resto de iOS; el
  arranque probado es `LiquidOLED` + su arnés de contraste (`LiquidOLEDContrasteTests`).
- **2026-08-29 · Distancia y sombra de tarjeta unificadas a un token cada una:** todo elemento tipo
  tarjeta usa `CenitMetrics.cardGap` para su separación y `LiquidElevation.tarjeta` para su sombra
  (las tarjetas teñidas conservan su sombra de color). Un solo lugar por cada cosa. Orden del dueño.
- **2026-08-29 · La consola de la sesión viva vuelve a ocultarse (revierte FER-167 R19):** el keypad
  de la sesión de fuerza gana la tecla ⌄ para bajarlo y ver la tabla completa; se reabre tocando
  cualquier celda de peso/reps (`beginEditing`). Orden del dueño en sesión /inject.

## Cómo revertir una decisión

Se puede — son decisiones, no leyes físicas. El camino: el dueño lo pide explícitamente,
se anota aquí la reversión con fecha y razón, y recién entonces se implementa.

## 2026-08-29 · Entrenar — terminar a medias y descanso sin reloj (FER-250, lote E)

Tres decisiones del dueño para el rediseño del cierre de sesión y el descanso sin Apple Watch:

1. **Sesión parcial = entrenamiento normal.** Si el usuario termina a la mitad y elige «guardar lo hecho», el entrenamiento parcial **cuenta igual** que uno completo: entra al historial, suma volumen y mantiene la racha/constancia. Lo que hiciste es trabajo real (paridad con Hevy). No se marca como «incompleto».
2. **Avisos de sesión ON por defecto durante un entrenamiento activo.** Sin reloj, al terminar el descanso la app **avisa (sonido + vibración) y mantiene la pantalla encendida**, aunque hoy ambos vienen apagados de fábrica. Fuera de una sesión activa, nada cambia. El Watch es una mejora, no un requisito.
3. **Descanso de respaldo = el de la rutina.** Cuando una rutina pide «descanso por pulso» pero no hay reloj, se cae al **tiempo objetivo que ya define la rutina**; si no define ninguno, a un default sensato (90 s). No un fijo global.

Contexto: la 2.ª auditoría de Entrenar (revisión Grok UX) encontró que hoy no hay salida honesta a media sesión (la única es minimizar, que descarta todo) y que el descanso sin reloj castiga al caso más común. Carril pesado: toca `StrengthSessionModel`, la Hoja, la píldora de minimizar y el Watch.

## 2026-09-01 · Sistema de diseño — cuatro decisiones tras la re-auditoría (FER-287)

Cuatro decisiones del dueño para cerrar la re-auditoría del sistema de diseño:

1. **(1A) Las 8 escalas puenteadas de `CenitMetrics` se deprecan de golpe**, no por lotes — la presión de warnings del compilador es la palanca para que los ~566 call-sites migren, en vez de una migración incremental sin urgencia.
2. **(2A) `OutlineCapsule` gana una variante decorativa/overlay** para absorber las 28 cápsulas hechas a mano en el código, dentro del épico de Entrenar (no como trabajo aparte).
3. **(3A) Entrenar migra al vidrio de afuera hacia adentro**: Biblioteca → Detalle → Editor semanal → Progresión/Descanso/Tickets → Historial → Sesión en vivo.
4. **(4A) El renombre `StrandDesign` → `CenitDesign`** (incluye `CenitIcon`/`CenitCTAButton`/`CenitOpacity`/`CenitFormat`) **va al final**, después de cerrar Entrenar. `StrandFont`/`StrandPalette`/`StrandMotion` NO se rebautizan — se retiran en su momento, no se renombran.

## 2026-09-03 · Corrida nocturna FER-299 — decisiones tomadas por el director (dueño ausente)

El dueño delegó todas las decisiones de la corrida («tú toma todas las decisiones y llévalo hasta el final»). Quedan aquí para que sean reversibles explícitamente:

1. **El renombre es `CenitDesign`, no «Zenit Design».** El dueño lo dictó por voz como «Zenit»; la marca es Cénit y la decisión 4A (FER-287) ya fijaba `CenitDesign`. Ejecutado en FER-290: paquete, módulo, carpetas, ejecutable de tokens, tests, y los 4 símbolos `CenitIcon`/`CenitCTAButton`/`CenitOpacity`/`CenitFormat`. `StrandFont`/`StrandPalette`/`StrandMotion` conservan su nombre (mueren, no se renombran).
2. **No existe un `LiquidColor.papel` cálido.** Grok lo inventó (#F4F1E8, el papel Instrumento) para sustituir `theme.paper`; se rechazó: el lienzo Liquid es `fondoAlto`. Ningún token Liquid reproduce el papel cálido de la generación anterior.
3. **La geometría congelada por el QA de FER-295 manda sobre la adopción de piezas.** «＋ SET» sigue en `OutlineCapsule .sm .vidrio` (no `HojaCapsulaAccion`, que sube el dibujo a 44 pt). «Change rest» pasa de 13 a 10 pt de padding horizontal porque el catálogo declara que `rowVPad`/`s250` absorbe 9/10/11/13.
4. **El peso de una fuente grotesk se pide por token, nunca con `.weight(...)`.** `Font.weight` no cambia la cara de una fuente `.custom` nombrada por PostScript; `LiquidType` gana `captionRegular/Fuerte/Negrita`, `captionLecturaNegrita`, `relojCompacto` y las sucesoras de `StrandFont` (`pie`, `cuerpoLista`, `subtituloFila`, `filaConteoNumero`).
5. **Las dos reglas nuevas del gate nacen como prohibición pura.** `no-deprecated-metrics` y `no-instrumento-theme` tienen deuda cero en iOS tras L1–L7; el Watch y los Widgets conservan el carve-out FER-219.
6. **`SetActionPills` es vista muerta**: se migró de paso pero nadie la consume; va a backlog para borrarla, no se rediseña.

## 2026-09-03 · Watch y Widgets salen del carve-out Instrumento (FER-309, dueño)

Orden del dueño («también hay que migrar watch y widgets, entra en loop… hasta que ya no tengas hallazgos»). Revierte explícitamente el carve-out FER-219: `InstrumentoTheme` deja de ser canónico en `CenitWatch/` y `CenitWidgets/`. Decisiones del director para ejecutarlo:

1. **Widgets de pantalla de inicio y Live Activity en pantalla bloqueada: lienzo Liquid** (`fondoAlto`, `LiquidType`, `LiquidSpace`, tonos de dato de `LiquidColor`), igual que la app.
2. **Watch y Dynamic Island: Liquid sobre OLED.** El negro se queda (OLED + HIG del Watch); las tintas vienen del set nuevo `LiquidOLED` (`fondo`, `superficie`, `tinta`, `tintaSecundaria`, `tintaTerciaria`, `borde`, `bordeFuerte`, `verde`, `ámbar`). Los tonos de dato son los mismos que en el iPhone: el dato no cambia de color por pantalla.
3. El gate deja de excluir `CenitWidgets/` y `CenitWatch/` de `no-legacy-api`, `no-instrumento-theme`, `no-deprecated-metrics` y `no-weight-on-grotesk` cuando la deuda de cada raíz llegue a cero (misma disciplina que FER-306: prohibición pura, sin baseline).


## 2026-09-02 · FER-85 (transcripción) y decisiones de la ola 1 de Entrenar (dueño)

**FER-85 — la app aconseja, no bloquea.** Vivía en código (`EntrenarView.swift`, «Otra forma ›») y no aquí.
Orden del dueño (2026-08-16): «yo sí quiero que el usuario, si quiere, le pueda subir». Consecuencias
vigentes: con veredicto ámbar/rojo la sesión siembra el peso anterior y la subida queda a un toque («subir
de todos modos»); editar a mano nunca se bloquea; el bloque «Otra forma ›» NUNCA lee el veredicto ni
reordena sus puertas (sugerir Movilidad el día «Recupera» fue retirado a propósito); el veredicto nunca
cambia la rutina del día.

**Ola 1 de Entrenar (épico FER-323), decisiones cerradas por el dueño el 2026-09-02** tras el taller
adversarial (`docs/specs/ola1-entrenar/`):
1. **La carga NO vota en el veredicto en esta ola** (D-Q12). El eje de carga del acta sigue siendo
   contexto («never flips the verdict»); ninguna pantalla dice que una sesión cambia el veredicto. La
   pieza «la carga vota» es FER-336 (ola 1b, gate /cso).
2. **Se pregunta «¿qué tan duro estuvo?» siempre al cerrar fuerza, también con reloj** (D-Q13; ciencia:
   Falk Neto 2020, Day 2004, Sweet 2004, Haddad 2017; Apple pide Esfuerzo en fuerza). Prellenado
   «sugerido», un toque, saltable. Con reloj el esfuerzo manda la carga de fuerza; la FC queda como costo
   cardiovascular. Nunca «el mayor de los dos».
3. **Cumplir reps con ≥2 reps en reserva → sube en 1 sesión** (D-Q1, Helms 2016). El ritmo se elige por
   ejercicio; en rutinas existentes nace «Constante» (D-Q6).
4. **El contador de semanas solo avanza en semanas con ≥1 sesión** (D-Q2).
5. **Semana ligera = series ×0,5, peso igual** por default; la opción con peso usa el mismo 7,5 % del
   deload reactivo: una sola familia de «bajar» (D-Q3).
6. **Cuatro motores de programa = las plantillas existentes + semanas; sin biblioteca de coaches** (D-Q4).
7. **La celda de reps de «las que puedas» arranca vacía** (D-Q7). **«Programa» fuera del primer uso**
   (D-Q8). **Sin rutinas desde nombres importados** (D-Q9). **La semana ligera cambia solo kicker y meta
   del héroe existente** (D-Q10; no se reabre v18).
8. **Vocabulario en palabras:** «reps en reserva» (nunca «Q»/«Quedaban»), «las que puedas», «bajar y
   seguir», «llegué al fallo», «semana ligera» (nunca «descarga»), «esfuerzo estimado».
9. **Regla de selectores:** segmentado solo para etiquetas de una palabra o número; opciones con
   explicación → lista con palomita; valor que abre pantalla → fila con chevron; acciones → botones cortos.
10. **Un «bajar y seguir» es sub-serie de su madre en la sesión viva** (E6, director 2026-09-02, gate
    /qa D3): borrar la madre en la hoja borra sus escalones (no tienen sentido sin ella). En la base
    el invariante es el opuesto y sigue: un escalón huérfano conserva `mode = drop`, nunca se promueve
    y nada se borra al guardar. En superserie el escalón va ANTES del salto al compañero: «bajar y
    seguir» pertenece a la misma serie. Un escalón que no baja (madre en la barra sola) no se inserta.
11. **Programa (E10, director + gate /biomecanico 2026-09-02):** «semana entrenada» (D-Q2) = semana con
    ≥ 1 sesión SERVIDA por el programa (`programWeek` no nulo); movilidad, sesión rápida y «repetir del
    historial» no avanzan el contador. El lineal de novato sube cada sesión solo en barra Y ≤ 8 reps
    (el curl de barra a 12 va a dos sesiones). En semana ligera la descarga reactiva AVISA («llevas 3
    sin cumplir») y no propone «bajar a»: la propuesta íntegra reaparece en la semana 1 del ciclo
    siguiente. Con «menos series y peso» el −7,5 % va sobre el peso final de la semilla («la última
    vez»), no solo sobre el plan.

## 2026-09-04 · Loop 4 (FER-339/340/341) · decisiones del director

- **Material solo vía receta (FER-340).** Un `.ultraThinMaterial`/`.regularMaterial` suelto es vidrio fuera de sistema. Regla `no-native-material` en las tres patas del gate; la única casa legítima es `LiquidGlassRecipes.swift`. Diálogos y tarjetas de captura ya pasan por receta.
- **Sin exenciones nuevas en loop 4.** `FocoMetrics.contentTop` (26 pt, sin escalón exacto) pasa a `LiquidSpace.s700` (28 pt) en vez de abrir `token-exempt(falta-pieza)`: la escala manda, no el píxel heredado. Misma línea que la decisión de loop 3 (AppMap queda en baseline, no en exención).
- **Halo/glow es pieza (`LiquidGlow`).** Blur + fill a mano en pantallas queda prohibido por criterio; la pieza entra al catálogo.
- **Texto de lectura con `@ScaledMetric` + `.system(size:)` NO es hallazgo** (Ronda 2 D2, hub Entrenar y RestEditor): escala con Dynamic Type por diseño; la auditoría lo excluye.


## 2026-09-06 · Demolición R1 · decisiones del dueño (3 issues)

- **Progresión ENCENDIDA por defecto en los 4 motores (FER-414, A).** Reafirma Ola 1 #11: «el lineal de novato sube cada sesión». El builder `Program.withProgression` configuraba el ritmo pero dejaba `progressionEnabled` en off, así que ningún motor subía ni descargaba. Ahora nace vivo; el motor sigue decidiendo QUÉ slot sube y cuándo (solo weightReps; barra ≤8 reps cada sesión, el resto cada dos). No cambia rutinas hechas a mano fuera de un programa.
- **«Necesidad» de sueño = meta fija con respaldo, no la media propia (FER-409, A).** La media propia + clamp generaba deuda por construcción (las noches largas no pagaban las cortas). Se sustituye por una meta poblacional citada. Detalle en el PR de FER-409.
- **Copy honesto ya sobre datos Apple (FER-407, A).** Corregir el subset factual del copy que dice «mientras duermes / RMSSD / RSA» sobre datos Apple despiertos/de todo el día. El resto (exponer el constructo real y variar el copy) queda como trabajo mayor en el mismo issue.

## 2026-09-06 · Cénit rumbo a la App Store (decisiones del dueño, épico FER-380)

- **2026-09-06 · Gratis hoy, cobrar después.** Cénit se publica en la App Store sin costo. Cualquier
  función de pago futura se anuncia en la app y en la ficha antes de entrar en vigor. Los términos
  (v3.0) y la política de privacidad ya no prometen «gratis para siempre» ni «no comercial».
- **2026-09-06 · Código 100 % propio (sala limpia).** Todo remanente de los autores del proyecto
  anterior se reescribe con protocolo de sala limpia: quien lee lo heredado solo escribe una
  especificación funcional (firmas públicas + QUÉ, nunca CÓMO); un revisor busca fugas; quien
  implementa borra lo heredado antes de empezar y trabaja solo desde la especificación; el oráculo
  son pares entrada→salida, nunca código de prueba. Cierre: `git blame -w -M -C -C -C` sin líneas de
  los autores anteriores. Nota legal: la reescritura reduce pero no elimina el riesgo de obra
  derivada; queda pendiente validarlo con un abogado y, en paralelo, pedir al autor original una
  licencia comercial. El historial de git se conserva; `NOTICE` lleva una nota histórica obligatoria
  por la licencia del código que existió antes.
- **2026-09-06 · Copyright y repositorio.** `LICENSE` pasa a PolyForm Noncommercial 1.0.0 con
  «Copyright 2026 Fernando Iracheta» como licenciante (el dueño puede comercializar; terceros no).
  El repositorio de GitHub se renombra a `blandisc/cenit`; los remotes del fork se eliminan. La
  carpeta local sigue siendo `~/code/noop` (renombrarla rompería memoria, worktrees y scripts).
- **2026-09-06 · Cero rastro del proyecto anterior, de WHOOP y de la banda.** Cénit es 100 % Apple
  Watch / Apple Health. Ninguna mención en código, textos, docs ni identificadores (salvo la nota
  histórica de `NOTICE` y «banda» en sentido estadístico). Gate: `Tools/check-band-copy.py`.
- **2026-09-06 · Identificadores «congelados» descongelados (FER-398).** La base de datos vive en
  `<AppSupport>/Cenit/cenit.sqlite` y las preferencias bajo `cenit.*`, con una migración única al
  arrancar (mover carpeta completa, sidecars primero; copiar-y-borrar claves). Los tags de esquema
  persistidos `noop.workout.v1`/`noop.diet.v1` se aceptan al leer y se emiten como `cenit.*`.
  El archivo de respaldo en iCloud Drive pasa de `NOOP-backup.sqlite` a `Cenit-backup.sqlite`; el
  viejo se adopta al primer respaldo (se renombra al lugar del nuevo, junto con su `.prev`) para que
  la rotación siga el mismo linaje en vez de dejar una copia congelada al lado.
  Excepción a la migración de preferencias: `exerciseMediaEnabled`/`exerciseMediaMissedIds` NO se
  migran, se borran — al retirar la tarjeta de descargas de Ajustes se fue su único apagador, así que
  copiar un `true` heredado habría dejado red encendida sin control (ver FER-919).
- **2026-09-06 · Excepción única al append-only de migraciones (FER-393).** Las 43 migraciones
  heredadas de `CenitStore` se sustituyen por UNA migración fresca con identificador `v43` creada a
  partir del volcado factual del esquema: la base del dueño (ledger v1…v43) no ejecuta ninguna
  sentencia; una instalación nueva crea el esquema completo de golpe; la siguiente migración es
  `v44`. Nunca reusar `v1`…`v42`. En adelante, append-only otra vez.
- **2026-09-06 · El aviso temprano de enfermedad se reencuadra.** «Señales de carga inusual» en vez
  de «posible enfermedad» (título, descripción, notificación y catálogo de métricas), con el hedge
  «no es un diagnóstico» intacto (riesgo de revisión 1.4.1).

## 2026-09-06 · Sistema de aprendizaje de Cénit (épico FER-428) · decisiones del dueño

Diagnóstico: Cénit enseña bien el veredicto y casi nada de lo demás — quien no tiene reloj sale del
onboarding sin ver el Acta ni el Ciclo, la noche 4 y la noche 14 pasan sin que nadie lo diga, nada se
puede volver a aprender (tips de una vez, sin Ayuda ni Novedades), Tendencias no se nombra en ningún
copy, y el sistema se pudre solo (README/FEATURES.md/tarjeta del taller desfasados). Opción elegida:
3 («todo, incluido el onboarding»). Diez decisiones, no se re-litigan:

- **D1 Onboarding: «La espera enseña»** (las frases durante el sync). El Acta sigue siendo pantalla,
  como en FER-109. «Te leo en voz alta» queda como segundo movimiento SOLO si el dueño reabre
  explícitamente el Acta; «El relevo» no.
- **D2 Novedades:** fila en Ajustes con punto de no leído + tarjeta de una vez al fondo de Hoy solo
  en cambios mayores. Nunca un modal.
- **D3 Sin reloj:** sí ve un Ciclo adaptado (sin aviso matutino), 5 toques.
- **D4 Hitos** (noche 4, noche 14…): tarjeta de una vez debajo del héroe, con puerta al Acta. Nunca
  encima de la palabra.
- **D5** Registro en Swift tipado. **D6** El gate falla la build para pantallas nuevas (baseline
  para las existentes).
- **D7 Ayuda** = «Cómo funciona Cénit» en Ajustes **y** un «?» en la cabecera de las cuatro pestañas
  que abre esa misma pantalla en la sección de la pestaña.
- **D8** Tips con cadencia diaria, grupo ordenado por pestaña, hasta 3 apariciones; los de la
  primera sesión de fuerza exentos.
- **D9** Los tips inline no reabren la decisión anti coach-marks (uno a la vez, junto al control,
  nunca sobre la palabra, nunca repitiendo el Acta).
- **D10** Sin checklist de arranque.

Cinco principios que van en cada lote del épico: (1) después de la palabra, nada; (2) se enseña en
el momento en que ocurre; (3) todo lo que se enseña una vez se puede volver a ver; (4) cada gesto
tiene un botón; (5) una funcionalidad sin pieza de enseñanza no se mergea (D6, `Tools/check-ensenanza.py`).

## 2026-09-07 · Adiós «Strand»: renombre total a `Cenit*` (FER-478, dueño)

Orden explícita del dueño: «Cénit no se acabó, Strand se acabó.» **Revierte explícitamente** dos
decisiones previas que hasta hoy mandaban:

- La **4A (FER-287, 2026-09-01)** y su ejecución **FER-290 (2026-09-03)**, que fijaban que
  `StrandFont`/`StrandPalette`/`StrandMotion` **NO se renombraban** («mueren, no se renombran»).
- La política de `docs/ARCHITECTURE.md` de que los paquetes de núcleo/datos/analítica
  **conservaban su prefijo `Strand*`** heredado de la era NOOP.

A partir de FER-478 el prefijo `Strand` desaparece del árbol vivo. Renombres ejecutados
(sustitución de token, sin colisiones):

- **Paquetes:** `StrandModels → CenitModels`, `StrandAnalytics → CenitAnalytics`,
  `StrandTraining → CenitTraining`, `StrandImport → CenitImport` (directorio, módulo, `Package.swift`,
  `project.yml`, imports, matriz de CI `swift-packages.yml`).
- **Tokens de diseño** (dentro de `CenitDesign`): `StrandFont → CenitFont`,
  `StrandPalette → CenitPalette`, `StrandMotion → CenitMotion`, `StrandTone → CenitTone`,
  `StrandElevation → CenitElevation`, `StrandAnimationModifier → CenitAnimationModifier`; y los
  modificadores en minúscula `strandAnimation/strandElevation/strandOverline → cenit*`.

Lo que **no** se tocó a propósito: la palabra inglesa `stranded` (comentarios/CHANGELOG) y el token
`Strain*` (la carga fisiológica — es otra palabra, no el prefijo). Las entradas históricas de este
archivo y del CHANGELOG **no se reescriben** (esta entrada las supersede; la historia queda como
rastro). El linter de diseño (`Tools/check-design-drift.py`), los scripts de horneado
(`Tools/bake-exercisedb/*.py`) y el censo del sistema de diseño se actualizaron a los nombres `Cenit*`.
## 2026-09-07 · «Tu patrón» para sueño, esfuerzo, eficiencia y pasos (FER-438) · director /orquesta FER-428, reversible por el dueño

Gates de ciencia (/cso) y estadística (/estadistico) corridos antes de implementar; sus reportes son
el contrato. Cuatro decisiones:

1. **VFC queda SIN bloque «Tu patrón»** hasta tener una serie densa de RMSSD nocturno. El bloque de
   FER-209 leía `avgHrv` a través de la lente que lo anula en toda fila Apple: nunca pintó. No se
   revive sobre el SDNN de Apple (la literatura predice débil justo esa relación: Zhang 2025, RMSSD
   sí, SDNN no). Issue de seguimiento: «VFC: Tu patrón con RMSSD nocturno denso».
2. **Se retiran los dos drivers de esfuerzo de FER-239.** `priorDayStrain` disparaba por
   construcción (con esfuerzo 0 en días de descanso, la autocorrelación lag 1 es −π/(1−π): «suele
   ser menor el día después» para cualquiera que no entrene dos días seguidos; describía el
   calendario). `sameDayRecovery` nunca disparó (`recovery` es nil en toda fila Apple). El bloque
   de esfuerzo queda con «eficiencia de anoche → esfuerzo».
3. **El gate es honesto o no es:** estadístico por relación (Spearman donde entra esfuerzo o pasos,
   Pearson donde ambas series son continuas), p sobre n efectivo (Bartlett, ρ₁ truncada a ≥ 0) en
   los pares cruzados, piso de clase minoritaria (≥ 10 días con y sin entreno cuando hay ceros),
   y Benjamini-Hochberg sobre la familia completa calculada en una sola pasada (q < 0.05). En los
   tres pares lag +1 del esfuerzo (sueño, eficiencia, FC en reposo) la Spearman es **parcial**:
   controla por el esfuerzo del día de la y (esfuerzo[D+1], Fisher 1924, df = n_eff − 3), porque sin
   ese control el calendario de entrenos (no entrenar dos días seguidos) se pintaba como patrón. El
   `|r| ≥ 0.20` se queda rotulado como cosmético. Los pisos 42 / 56 (eficiencia) y el 10 son knobs
   de producto, rotulados como tales. Consecuencia aceptada: «todavía» será lo normal; el gate
   protege el falso positivo, no el falso negativo.
4. **Cinco relaciones nuevas, con cita en el pie de cada métrica:** esfuerzo[D] → sueño[D+1]
   (Kredlow 2015, Atoui 2021); sueño[D] → sueño[D+1] (Borbély 1982/2022); eficiencia[D] →
   esfuerzo[D] (Atoui 2021, Lambiase 2013); esfuerzo[D] → eficiencia[D+1] (Kredlow 2015);
   eficiencia[D] → pasos[D], sin el día en curso (Atoui 2021, Lambiase 2013, Mead 2019). FC en
   reposo conserva las dos suyas, ahora con Spearman en la de esfuerzo y con las citas correctas
   (Dettoni 2012, Faust 2020, Stanley 2013; «Plews 2013» no trataba sueño). Las demás métricas
   (estrés, temperatura, SpO₂, FC, VO₂ máx, carga, regularidad, latencia, despertares, etapas,
   rendimiento) quedan explícitamente sin bloque, con la razón en `docs/ANALYTICS.md`.

Un solo hogar para el copy: `WhatMovesItFinding.phrase` resuelve `patron.<relación>.<rises|falls>`
del catálogo; ninguna pantalla vuelve a llevar su propio switch de frases.

## 2026-09-07 · `sleep.priorNight` a parcial de 2º orden (FER-480) · director, reversible

Hallazgo del CDO en el re-check posterior a FER-438: el fix de FER-438 (parcial de Spearman de 1er
orden) arregló los tres pares lag +1 del esfuerzo, pero **no tocó** el auto-lag `sleep.priorNight`
(sueño de hoy ← sueño de la noche anterior), que hereda el MISMO confound de calendario en ambos
extremos del par a la vez — la noche larga del día de entreno (extremo x) y la noche corta del día
siguiente, que rara vez también entrena (extremo y, por la autocorrelación ρ₁ ≈ −0.39 del esfuerzo).
En una fixture de puro calendario (`sleep = 420 + 35·W(i)`, sin rebote real) el auto-lag daba
r = −0.405, p = 0.0015; Monte-Carlo (n = 59, 2000 sims) disparaba falso el 17.3 % de las veces.

**Decisión: extender el motor a un parcial de Spearman de 2º orden** (`CorrelationEngine.
spearmanPartial2`), controlando esfuerzo[D] Y esfuerzo[D+1] a la vez — no degradar ni retirar la
relación, porque el parcial de 2º orden SÍ la deja estimable honestamente: en la misma fixture de
puro calendario cae a r ≈ −0.016, p ≈ 0.91 (deja de disparar), y en una fixture con un rebote real
superpuesto al mismo calendario sigue disparando (r ≈ −0.99). Método elegido: recursión de la
fórmula de Fisher (1924) — el parcial de orden 1 aplicado tres veces para sacar z1 de x, y y z2, y
una cuarta vez para sacar el z2 residual — en vez de invertir una matriz de regresión; es
algebraicamente el mismo coeficiente que dejaría una regresión por mínimos cuadrados de los
midranks de x e y sobre {z1, z2} en los residuos (`CorrelationEngineOracleTests` cruza ambos
caminos). p por t exacta con df = n − 4 (dos grados de libertad, uno por control).

El resto de la familia (los tres pares lag +1 ya arreglados por FER-438 con parcial de 1er orden, y
`strain.efficiency` / `steps.efficiency`) queda intacto: mismo gate (n efectivo Bartlett, piso de
clase minoritaria ≥ 10, Benjamini-Hochberg, `minAbsR` 0.20, `maxQ` 0.05, pisos de n). El comentario
del test y la nota de archivo que llamaban «legítimo» a este disparo (`WhatMovesItTests`,
`WhatMovesIt.swift`) quedan corregidos: era el mismo artefacto de calendario que FER-438 ya había
identificado en los pares cruzados, solo que sin corregir en el auto-lag. El copy
`patron.sleep.priorNight.*` no cambia — la relación sigue existiendo y dispara cuando el rebote es
real; lo que cambia es cuándo el gate la deja pasar.

## 2026-09-08 · Cierre de «Cénit rumbo a la App Store» — dos arreglos de proceso (director, retro FER-380)

Al cerrar la corrida del épico FER-380 (código 100 % propio + cero rastro de NOOP/WHOOP/banda),
el retro destiló dos aprendizajes que recurrían y no estaban codificados. Ambos son reversibles y
los aplicó el director; se suben aquí para no re-litigarlos.

**1 · El choque de `CHANGELOG.md` entre corridas paralelas se mata con `merge=union`, no
reconciliando a mano.** Se creó `.gitattributes` en la raíz con `CHANGELOG.md merge=union`. El
driver nativo `union` anexa ambos lados en vez de conflictuar — la misma resolución «conservar
ambas entradas» que el director hacía a mano en cada corrida (recurrió en FER-323, ola 1 de sala
limpia #1549, y palanca B FER-479/#1590, cuyo único choque fue el CHANGELOG con FER-482). Elimina
la clase entera. El workaround previo («sacar el CHANGELOG a un PR de docs aparte») sigue siendo
válido para lotes grandes, pero ya no es obligatorio para el choque simple de dos entradas.

**2 · Un barrido «cero rastro de X» debe verificar el ARTEFACTO de una instalación NUEVA, no solo
grepear el fuente.** Regla nueva para el DoD de cualquier trabajo de remoción de marca/origen: la
marca vive en dos ejes — (a) datos-en-reposo de instalaciones legadas y (b) identificadores que el
código ESCRIBE en runtime (deviceId de partición, columna source, tags persistidos). El eje (b)
sobrevive a un `grep` del fuente porque solo nace neutro si se voltean las constantes
centralizadas. **Criterio de cierre: un `strings` del binario más un volcado de la base de una
instalación fresca no contienen la marca** — el grep del fuente no basta. Siete frentes de FER-380
se declararon done y el barrido forense final descubrió que las instalaciones nuevas seguían
escribiendo la marca en los deviceId de partición; eso motivó la palanca B (migración v44 +
flip de constantes, FER-479). Esta regla la hubiera atrapado antes. Complementa —no reemplaza— el
cierre de sala limpia por autoría (`git blame -w -M -C -C -C = 0 líneas de prosa`).
