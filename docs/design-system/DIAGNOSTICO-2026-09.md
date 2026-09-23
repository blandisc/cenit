# Diagnóstico del sistema de diseño «El Eje»: septiembre 2026

> **Foto del 2026-09-23** (árbol en `22d1ff4`). Es un diagnóstico, no una norma. Los números se
> midieron con `rg` sobre el árbol de esa fecha. Si el código y este documento no coinciden, manda
> el código.
>
> **Alcance:** `Packages/CenitDesign` como producto (fundamentos, componentes, documentación,
> gobierno, accesibilidad, herramientas) y su adopción en `Cenit/`, `CenitApp/`, `CenitWidgets/` y
> `CenitWatch/`. Contra qué se compara: la práctica publicada de la industria (fuentes al final).

---

## 0. Veredicto en una página

**El sistema está en un nivel de madurez alto: 4 de 5.** Es poco común en un equipo de este
tamaño. La migración a una sola generación ya terminó en la app: los call-sites de `CenitMetrics`,
`CenitFont`, `CenitMotion`, `CenitPalette` e `InstrumentoTheme` en la app son **cero**. El 1 de
septiembre eran 577, 511, 59, 3 y 127. El gobierno automatizado, con un trinquete de deuda, una
matriz de gates validada contra su propio contrato y un censo por AST, supera a lo que publican
la mayoría de los sistemas corporativos.

Tres cosas lo detienen antes del nivel 5. Las tres tocan a la persona que usa la app, no al
código:

1. **La accesibilidad del texto tiene techo.** La app corta Dynamic Type en `xxxLarge`
   (`CenitApp/App/CenitApp.swift:111`), alrededor del 135 %. Apple pide 200 % o más para declarar
   «Larger Text» en la App Store. Además, el caption más usado (`LiquidType.caption`, 140 usos)
   mide 10.5 pt fijos.
2. **El vidrio propio solo reacciona a medias a los ajustes del sistema.** El sistema no lee ni
   `accessibilityReduceTransparency` ni `colorSchemeContrast`: 0 usos en todo el árbol. El
   `.ultraThinMaterial` de las recetas sí se vuelve opaco con «Reducir transparencia», pero los
   blancos al 46–92 %, los filos y los tintes propios no cambian.
3. **Los documentos contradicen al código sobre el modo oscuro.** El código ya resuelve 50 de 80
   colores por modo y Ajustes ofrece Sistema, Claro y Oscuro (FER-343). En cambio, `DESIGN.md`,
   `CLAUDE.md`, `ACCESIBILIDAD.md`, el `CATALOGO.md` generado y el JSON de tokens siguen diciendo
   que el oscuro está retirado, o muestran un solo valor. Esta es justo la clase de defecto
   FER-119: agentes y personas leen los documentos antes que el código.

### Calificación por dimensión

Las dimensiones combinan el marco de 6 ejes de NN/g, el modelo de zeroheight y el de Sparkbox.

| Dimensión | Nivel (1–5) | Resumen |
|---|---|---|
| Fundamentos (tokens) | **3.5** | Completos y con buenos nombres de rol, pero en una sola capa. Hay valores duplicados y el export no sigue DTCG 2025.10. |
| Componentes | **4.5** | 126 entradas con «cuándo sí / cuándo no», mapa de estados y `#Preview` obligatorio. Es de primer nivel. |
| Documentación | **3** | Abundante (18 documentos, unas 4 700 líneas) pero dispersa. Lo normativo convive con lo histórico y la verdad del modo oscuro está atrasada. |
| Gobierno y proceso | **5** | Gates y trinquete de deuda, un solo camino legal para subir la base, paridad de gates validada y censo AST. Es de referencia. |
| Accesibilidad | **3** | El contraste AA está probado con tests y hay disciplina en VoiceOver y en las áreas de 44 pt. Faltan AX1–AX5, «Reducir transparencia», «Aumentar contraste» y «Diferenciar sin color». |
| Calidad y verificación | **3.5** | 95 archivos de prueba y tests de contraste en claro, oscuro y OLED. No hay regresión visual con imágenes de referencia: 0 PNG, y los «snapshots» son arneses que escriben en `/tmp`. |
| Adopción | **4.5** | La app ya usa solo el dialecto canónico. El legado vive solo dentro del paquete. |
| Preparación para la IA | **4.5** | El catálogo está hecho para máquinas, con subagentes `/ui`, `/componente` y `/qa` y lints que atrapan la clase de defecto. La deriva de los documentos es el riesgo principal. |

---

## 1. Método

- **Medición interna:** conteos con `rg --glob '*.swift'` sobre app y paquete. Se leyeron
  `DESIGN.md`, `LIQUID-GLASS.md`, `CONTRATO.md`, `CATALOGO.md`, `ACCESIBILIDAD.md`, `CENSO.md`, la
  auditoría `historico/AUDITORIA-SISTEMA.md` (2026-09-01) como línea base, `DECISIONS.md`,
  `design-tokens.json`, `design-lint.yml`, `LiquidColor.swift`, `LiquidType.swift` y
  `LiquidGlassRecipes.swift`, además de los tests del paquete.
- **Investigación externa:** la especificación estable de tokens del W3C (DTCG 2025.10: formato,
  color y resolver), las pautas de Apple (HIG de tipografía, Liquid Glass de la WWDC25 y los
  criterios de las Accessibility Nutrition Labels), modelos de madurez (NN/g, zeroheight,
  Sparkbox), la arquitectura de tokens en tres capas y el versionado y la deprecación según
  Nathan Curtis (EightShapes).
- **Qué no se re-litiga:** las decisiones del dueño en `DECISIONS.md` (El Eje, regímenes mosaico y
  sobrio, `LiquidSpace` nombrada por valor, `cardGap`, el carve-out del Watch OLED). Cuando una
  recomendación roza alguna, se marca como **decisión del dueño**.

### Evolución desde la auditoría del 2026-09-01

| Símbolo en la APP | 2026-09-01 | 2026-09-23 | Tendencia |
|---|---|---|---|
| `LiquidColor.` | 843 / 56 archivos | **1 811 / 110** | ▲ adopción |
| `LiquidSpace.` | 660 / 66 | **1 598 / 101** | ▲ |
| `LiquidType.` | 348 / 33 | **1 049 / 89** | ▲ |
| `LiquidMotion.` | 82 / 36 | **139 / 51** | ▲ |
| `CenitMetrics.` | 577 / 51 | **0** | ✔ migrado |
| `CenitFont.` | 511 / 46 | **0** | ✔ |
| `theme.*` / `InstrumentoTheme` | 1 005 / 127 | **1 / 0** | ✔ |
| `CenitMotion.` | 59 | **0** | ✔ |
| Deuda en baseline (`token-exempt`) | 215 | **132** | ▼ |
| Deuda en baseline (`no-spacing-literal`) | 466 | **28** | ▼ |

En tres semanas se hizo la parte más cara de cualquier sistema: converger a un solo dialecto.

---

## 2. Fortalezas (qué conservar y proteger)

**F1. Gobierno ejecutable, no aspiracional.** `CONTRATO.md` no es una guía de estilo: es una
**matriz de gates** en JSON que `Tools/check-gate-parity.py` compara con el pre-commit, con
`verify.sh` y con CI. Muy pocos sistemas públicos garantizan que sus tres puntos de control digan
lo mismo. El **trinquete** (`design-drift-baseline.json`, «ningún conteo sube») y el **único
camino legal** para subir la base (label `baseline-alta` del dueño y un PR que solo toque la base)
aplican lo que la industria llama *deprecation-first governance with automated checks*, pero con
dientes.

**F2. Un catálogo pensado para decidir, no solo para listar.** `CATALOGO.md` sale del código y
cada pieza trae **rol → símbolo → archivo → cuándo usarla → cuándo no**, más un **mapa de
estados** («una situación, una pieza»). Es el formato que recomiendan los sistemas maduros
(Polaris, Atlassian), y aquí además no se puede desviar del código porque lo genera
`swift run CenitDesignTokens`.

**F3. Una taxonomía de excepciones con salida.** `// token-exempt(<categoria>)` con seis
categorías y la **regla ×3** («tres `falta-pieza` iguales son un componente que falta») convierte
las excepciones en backlog de piezas en lugar de deuda invisible. Pocos sistemas tienen un
mecanismo formal para descubrir componentes que faltan.

**F4. Un punto de vista propio y documentado.** «Cuatro colores que no se mezclan» (señal ·
módulo · juicio · marca), los regímenes **mosaico y sobrio**, «el numeral nunca miente» (`··`,
`—`, `~N`) y los numerales tabulares que ruedan con `.numericText()`. Es ADN de producto, no un
kit genérico: la prueba anti-*slop* tiene de dónde agarrarse. Y cada excepción viene con nombre y
razón (el azul del vigía, el «+ Serie» en `dataStrain`), que es justo lo que pide la buena
práctica: una divergencia documentada no se confunde con un error.

**F5. Contraste medido, no supuesto.** Los tests fijan ratios exactos (`LiquidTonoContrasteTests`,
`LiquidDarkTwinsContrasteTests`, `LiquidOLEDContrasteTests`, `FitnessAgeContrastTests`). El
generador calcula WCAG con la fórmula canónica. Los tokens deliberadamente no AA (`inkDim`,
`inkMuted`) están declarados como tales.

**F6. Un paquete aislado y portable.** Cero dependencias, concurrencia estricta, compila para
iOS, macOS y watchOS, y los fundamentos se prueban sin simulador. Es el patrón correcto para un
sistema multiplataforma en Swift.

**F7. Versionado con regla.** `CenitDesign.version = 1.0.0`, con SemVer explicado en lenguaje de
producto en `RETIRADAS.md` (el número chico sube cuando entra o sale una pieza; el grande, cuando
cambia una regla que la persona ve). Está alineado con Curtis: versionar *todas* las salidas del
sistema, no solo el código.

---

## 3. Hallazgos y áreas de oportunidad (ordenados por severidad)

Severidad: **Alta** afecta a la persona usuaria o a la veracidad del sistema. **Media** es costo
o riesgo de mantenimiento. **Baja** es higiene.

### H1 · Alta: Dynamic Type tiene techo en `xxxLarge` y hay texto fijo bajo el mínimo

**Evidencia**
- `CenitApp/App/CenitApp.swift:111`: `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` como tope
  global. Los tamaños AX1–AX5 nunca llegan a la app, salvo en pantallas con un cap propio.
- En `LiquidType`, **16 de 58 fuentes son de tamaño fijo**. Entre ellas: `caption` y sus variantes
  (10.5 pt, **157 usos**; solo `caption` suma 140), `displayXL`/`displayL`/`displayM` (54/30/40 pt,
  19 usos) y `etiquetaEje` y `orbita` (8 pt).
- `ACCESIBILIDAD.md §2` documenta el techo como decisión, pero no su costo.

**Contra la buena práctica**
- La **Accessibility Nutrition Label «Larger Text»** exige que el texto pueda crecer al **200 % o
  más** y que las tareas comunes se puedan completar así. `xxxLarge` queda en torno al 135 % del
  cuerpo. Hoy Cénit **no puede declarar esa etiqueta** con honestidad.
- La HIG pide tamaños mínimos legibles (11 pt para cuerpo en iOS) y fuentes propias ancladas a un
  *text style*. Space Grotesk ya se ancla con `relativeTo:` en 42 de 58 tokens, así que el
  mecanismo existe. Lo que falta es aplicarlo al resto.

**Recomendación**
1. Retirar el tope global. Dejar el cap solo por componente, con `token-exempt(sistema)` o
   `(dato)` donde la geometría lo exija (anillo, dial, keypad), que es la doctrina que el propio
   sistema ya enuncia en «Doctrina sin-scroll de Hoy»: con tallas AX vuelve el scroll.
2. Pasar la familia `caption*` (10.5) a `relativeTo: .caption2`. Es la de mayor impacto: 157
   usos en total.
3. Añadir un **gate** `no-fixed-text-font` (prohibición pura para texto de lectura, con excepción
   para geometría) y un test que recorra `LiquidType` y verifique que todo token de texto de
   lectura escala.
4. **Decisión del dueño:** el techo es una decisión registrada (FER-394), así que requiere su
   reversión explícita en `DECISIONS.md`.

### H2 · Alta: el vidrio propio responde a medias a «Reducir transparencia» y a «Aumentar contraste»

**Evidencia**
- `accessibilityReduceTransparency`: **0 usos**. `colorSchemeContrast`: **0**.
  `accessibilityDifferentiateWithoutColor`: **0**.
- Las recetas (`LiquidGlassRecipes.swift`) componen `.ultraThinMaterial` o `.thinMaterial`, que el
  sistema sí vuelve opaco, **más** capas propias: blancos al 46–92 % (`vidrioSuperficie`,
  `vidrioBorde`, `vidrioEspecular`), `papelDock` al 38 %, filos `LiquidAuroraEdge` y la plasta del
  veredicto. Esas capas no cambian con ningún ajuste.
- El `glassEffect` nativo aparece en 3 sitios (Entrenar), no en la receta central.

**Contra la buena práctica**
- En la WWDC25 («Meet Liquid Glass»), Apple explica que su material se adapta solo a Reducir
  transparencia, a Aumentar contraste (bordes y color más marcados) y a Reducir movimiento. Un
  vidrio propio renuncia a eso y **hereda la obligación** de hacerlo a mano.
- La HIG reserva el vidrio para **la capa de navegación**, no para el contenido, y desaconseja el
  vidrio sobre vidrio. El régimen **mosaico** pone vidrio teñido sobre contenido. Es una decisión
  de marca legítima, y el sistema ya la mitiga con `.superficieSolida` y `.pastillaSolida` para
  tarjetas internas, pero aumenta la necesidad del punto anterior.

**Recomendación**
1. Una sola compuerta en `liquidGlass(_:)` y `liquidGlass(tono:regimen:)`:
   - Con Reducir transparencia, cambiar a `superficieSolida` (ya existe) y apagar filos y
     especulares.
   - Con Aumentar contraste, un borde `tinta700` de 1 pt, subir el alfa del tinte y usar las
     variantes `rotulo` de mayor contraste.
2. Tests de las dos ramas, en el patrón de `LiquidThemeResolveTests`.
3. Un gate `no-glass-without-gate`, para que nada fuera de la receta pinte blur o alfa.
   `no-native-material` ya cubre la mitad.
4. En los elementos que codifican juicio solo con hue (plasta verde, ámbar o rojo; teselas del
   calendario), asegurar una segunda señal (palabra, forma o patrón) bajo «Diferenciar sin color».
   El sistema ya lo hace en el héroe con el veredicto en texto. Falta verificarlo en mosaicos y
   rampas.

### H3 · Alta: los documentos contradicen al código sobre el modo oscuro

**Evidencia**
- **Código:** `LiquidColor` resuelve **50 de 80** tokens con `LiquidTheme.dynamic(light:dark:)`.
  `AjustesView.swift:261-269` ofrece Sistema, Claro y Oscuro. El último commit del árbol es «El
  modo oscuro deja de pintar blanco encima del negro» (#1640). `DECISIONS.md` (2026-09-03)
  **reabre** el lienzo blanco (épico FER-343).
- **Documentos:** el manifiesto de `DESIGN.md` («El sistema oscuro sigue retirado (FER-430)»),
  `DESIGN.md §7` («Lienzo canónico = blanco… El sistema oscuro se retiró»), `CLAUDE.md` («The dark
  system is legacy (maintain, don't extend)»), `ACCESIBILIDAD.md` («lienzo blanco») y
  `CONTRATO.md` («el Watch no se pinta de blanco» como único tercer contexto).
- **Artefactos generados:** `CATALOGO.md` muestra **un solo valor** por color. Por ejemplo,
  `vidrioPastilla` y `vidrioSuperficie` salen idénticos, cuando en oscuro difieren (`#24201C` al
  92 % frente a `#1F1C18` al 94 %). `design-tokens.json` no tiene modos: solo 2 menciones de
  «dark», ambas en prosa.

**Por qué es alta.** El propio repo midió que «reimplementar lo existente» es su defecto más caro
(FER-119: 15 defectos) y que su causa es que los documentos enseñan lo que ya no es. Un agente que
lea `CLAUDE.md` va a diseñar una pantalla nueva **solo en claro**.

**Recomendación**
1. Una ola de documentación: el manifiesto de `DESIGN.md`, §7, `CLAUDE.md` (regla de diseño),
   `ACCESIBILIDAD.md` y `CONTRATO.md` (contextos de arbitraje) con **tres modos: claro, oscuro y
   Watch OLED**.
2. Que el generador de `CATALOGO.md` emita **dos columnas** (claro y oscuro) y el contraste de
   cada par.
3. Un test o check que falle si un token `LiquidTheme.dynamic` se publica en el catálogo con un
   solo valor. Es la misma disciplina que el drift de §8.2.

### H4 · Media: tokens en una sola capa, con valores duplicados

**Evidencia.** `LiquidColor` tiene 80 tokens planos que mezclan tres niveles:
- **Primitivos:** `tinta900`, `indigo`, `ambar`.
- **Semánticos:** `positivo`, `atencion`, `negativo`, `atencionTexto`.
- **De componente:** `verdeBotonAlto`, `particulaVerde`, `papelMatriz`, `celdaVaciaPip`.

Hay **duplicados como valores independientes**, no como alias:
- `positivo` y `verdeProfundo` valen `#00774B` / `#2EB27D`, definidos dos veces (líneas 70 y
  195).
- `atencion` y `ambar` valen `#C4631F`.
- `celdaVacia` y `tinta7` son el mismo 7 %.

Si alguien ajusta uno, el otro se desvía en silencio.

**Contra la buena práctica.** La arquitectura de tres capas, **primitivo → semántico →
componente**, es el consenso de la industria (Material 3 *color roles*, Atlassian, Polaris,
DTCG con alias `{…}`). Es la que hace barato el tema oscuro: se cambia la capa semántica y los
primitivos quedan. Además, el propio sistema ya piensa en roles: los «cuatro colores que no se
mezclan» son exactamente una capa semántica.

**Recomendación**
1. Sin mover un píxel: convertir los duplicados en **alias** (`public static let positivo =
   verdeProfundo`) y añadir un test que falle si dos tokens públicos independientes resuelven al
   mismo par claro/oscuro sin ser alias.
2. A mediano plazo: marcar en el código las tres capas (`LiquidColor.Primitivo`,
   `LiquidColor.<rol>`, y lo de componente dentro del componente), con la capa semántica
   organizada por los **cuatro colores**: señal, módulo, juicio y marca. Así el mapa del
   manifiesto se vuelve API.
3. **Decisión del dueño:** reorganizar nombres públicos cambia la API. Conviene hacerlo en la misma
   ola que el renombre `Liquid*` (H7).

### H5 · Media: el export de tokens no cumple DTCG 2025.10 y enseña primero la paleta vieja

**Evidencia**
- `design-tokens.json` declara el esquema DTCG, pero los colores van como **cadena hex**. La
  especificación estable (octubre 2025, módulo de color) exige un **objeto `{colorSpace,
  components}`**, con `hex` como fallback opcional. Herramientas como Penpot y Style Dictionary v5
  ya lo validan así.
- **Sin modos:** no usa el *Resolver Module* 2025.10, que es la forma estándar de declarar
  claro, oscuro y alto contraste.
- El archivo **abre** con `accent #18C98B`, `status` y `recovery` en `#FF4F73`, la paleta del
  sistema oscuro retirado (vía `CenitPalette`). Esa paleta tiene 0 usos en la APP y sigue viva
  solo dentro del paquete. `color.liquid`, lo canónico, aparece después.

**Recomendación**
1. Que `CenitDesignTokens` emita el formato 2025.10: objetos de color en `srgb` (o `display-p3`
   donde aplique) con `hex` de fallback.
2. Un `resolver` con los conjuntos `base` y `dark`, y `oled` para el Watch.
3. Reordenar para que `liquid` vaya primero y mover la paleta oscura a `legacy.*`, con
   `$deprecated: true` (campo del estándar).
4. Validar el JSON en `design-tokens.yml` contra el esquema oficial.

Costo bajo, porque el generador ya existe. El beneficio es la interoperabilidad: Figma
Variables, Penpot y un eventual widget web o watch-face.

### H6 · Media: no hay regresión visual automatizada

**Evidencia.** Los tests «snapshot» (`MetricDetailVisualSnapshotTests`, `ChartSnapshotTests`,
`InstrumentoSnapshotTests`, …) son **arneses** que escriben PNG en `/tmp` para mirarlos a ojo. El
propio código lo dice: «Not a CI assertion — a developer render harness». Hay **0 imágenes de
referencia** en el repo. Los gates cubren *literales*, no *píxeles*.

**Contra la buena práctica.** Los sistemas maduros comparan contra imágenes de referencia: en iOS,
`swift-snapshot-testing` de Point-Free; en la web, Chromatic o Percy. El foco está justo en las
combinaciones que los humanos no revisan: modo oscuro, AX5 y Aumentar contraste. Con tres modos y
dos regímenes, la matriz ya es demasiado grande para mirarla a ojo.

**Recomendación**
1. Un conjunto chico y de alto valor: los 10 componentes más usados del catálogo × {claro,
   oscuro} × {default, AX3} × {normal, Aumentar contraste}.
2. Imágenes de referencia versionadas y comparación con tolerancia perceptual en el host macOS
   que ya usan los tests de contraste.
3. **Tensión con la regla «cero dependencias»** del paquete: la librería puede vivir solo en el
   *test target*, o se puede escribir un comparador mínimo propio (`ImageRenderer` más un diff
   por canal, unas 100 líneas). Lo decide el dueño.

### H7 · Media: la nomenclatura arrastra tres generaciones

**Evidencia**
- El sistema se llama **El Eje**, pero la API es `Liquid*`: `LiquidColor`, `LiquidType`,
  `liquidGlass`.
- `LiquidType` se construye sobre `InstrumentoType.grotesk` (la puerta de Space Grotesk está en el
  módulo de la generación anterior).
- El archivo canónico se llama `LIQUID-GLASS.md`, un nombre ya retirado.
- Conviven español e inglés sin regla: `LiquidType.cuerpo` junto a `CenitFont.body`,
  `StatePill` junto a `LiquidStatePill`, `BackButton` junto a `LiquidCampoTexto`.

`DECISIONS.md` (2026-09-21) difiere el renombre de código «a una ola posterior».

**Contra la buena práctica.** El nombre de la API es la documentación que más se lee, porque
aparece en el autocompletado. Curtis recomienda que un renombre se haga **una sola vez**, con
**deprecación y alias** durante una versión mayor, no a goteo.

**Recomendación**
1. Una sola ola mecánica. Primero, la puerta pública de Space Grotesk pasa a `LiquidType` (o a su
   sucesor) e `InstrumentoType.grotesk*` queda `internal`.
2. Después, el renombre `Liquid*` → nombre de El Eje, con `@available(*, deprecated, renamed:)`
   en los viejos para que el compilador guíe la migración (misma palanca que la decisión 1A de
   FER-287).
3. Una regla escrita de idioma para símbolos: por ejemplo, rol en español y tipos de plataforma en
   inglés.
4. Subir a `CenitDesign 2.0.0`, según la regla de `RETIRADAS.md`.

### H8 · Media: el legado sigue vivo dentro del paquete y sin marca de deprecación

**Evidencia.** Dentro del paquete quedan `CenitFont` (153 usos, 39 archivos), `InstrumentoTheme`
(143 / 47), `InstrumentoType` (140 / 28), `CenitMotion` (30 / 12) y `CenitPalette` (29 / 10).
Solo **2** anotaciones `@available(*, deprecated)` en todo el paquete. Como la APP ya está en cero,
estos símbolos solo se sostienen entre sí: componentes viejos que usan tokens viejos. Algunos se
conservan a propósito por rollback (`Hypnogram`, `YearHeatStrip`, según `RETIRADAS.md`).

**Recomendación**
1. Marcar como deprecados todos los símbolos públicos de generación anterior que tengan 0 usos en
   la APP. El compilador avisa y los agentes dejan de ofrecerlos.
2. Convertirlos a `internal` cuando sea posible, porque así salen del autocompletado de la app.
3. Programar el lote de poda: la lista §3.1 y §3.2 de `historico/AUDITORIA-SISTEMA.md`, re-censada.
4. Que el dueño fije una fecha de caducidad al rollback de `Hypnogram` y `YearHeatStrip`.

### H9 · Baja-media: la documentación está dispersa y mezcla norma con historia

**Evidencia.** 18 documentos en `docs/design-system/`, unas 4 700 líneas.
- Tres auditorías y un censo están marcados «Foto histórica… no sirve para decidir», pero viven al
  lado de los normativos.
- `DESIGN.md` dedica más de la mitad (§8, unas 330 líneas) a la generación **anterior**, mientras
  que lo canónico vive en `LIQUID-GLASS.md`.
- §1 a §4 de `DESIGN.md` aún documentan `CenitPalette`, `CenitFont`, `CenitMetrics` y
  `CenitMotion` (0 usos en la APP) antes que los tokens vigentes.

**Contra la buena práctica.** La arquitectura de información de un sistema maduro separa
**fundamentos, componentes, patrones y contenido** (lo normativo) de **registros de cambio y
decisiones** (lo histórico). Quien llega debe encontrar primero lo vigente.

**Recomendación**
- Mover `AUDITORIA-*`, `CENSO.*`, `INVENTARIO-UN-SOLO-VIDRIO.md` e `ICONOS-BORRADOR.md` a
  `docs/design-system/historico/`.
- Reescribir `DESIGN.md` como índice corto: manifiesto → fundamentos El Eje → catálogo →
  accesibilidad → lenguaje. Pasar §8 a `historico/instrumento.md`.
- Renombrar `LIQUID-GLASS.md` en la misma ola que H7.

### H10 · Baja: el gobierno vive en regex, con evasiones conocidas y costo de fricción

**Evidencia.** Hay unas 26 reglas en `check-design-drift.py`, casi todas regex. El propio
`CONTRATO.md` reconoce su límite («contrasta texto, no ejecución»). `CENSO.md` midió las evasiones
por AST: 146 `.frame(height:)` y 109 `.frame(width:)` decorativos, 63 `Color.clear`, 10
`.offset`, declarados «indecidibles con regex». Cada regla nueva además suma a la matriz de tres
patas.

**Recomendación**
1. El AST ya existe: `Tools/DesignCensus` usa swift-syntax. Promover a **gate** las 3 o 4
   detecciones de mayor valor (frames decorativos con literal, `clipShape(RoundedRectangle)`
   crudo).
2. Consolidar reglas hermanas (las tres `no-*-literal` en una regla parametrizada) para que la
   matriz no crezca de forma lineal.
3. Medir cuánto tardan los PR en pasar los gates. Si el gobierno cuesta más de lo que evita, el
   sistema lo sentirá antes en el ritmo que en la calidad.

### H11 · Baja: Reducir movimiento no tiene compuerta central

**Evidencia.** 22 sitios en la APP y 51 en el paquete leen Reduce Motion por su cuenta.
`ACCESIBILIDAD.md §4` ya lo lista como deuda («copy-paste por sitio»).

**Recomendación.** Integrar la compuerta en `LiquidMotion`: cada animación de `LiquidMotion`
resuelve a `nil` o `.identity` bajo Reduce Motion, y los modificadores `.liquidEntrada` y
`.liquidPress` ya centralizan la mayoría. Añadir un gate que prohíba `.animation(` con token de
motion fuera de esos modificadores.

---

## 4. Hoja de ruta propuesta

La ordenan el impacto en la persona usuaria y el costo. Cada fila es un issue candidato para
`/pm`. **Carril:** P = pesado, L = ligero, según `CLAUDE.md`.

| # | Iniciativa | Hallazgos | Carril | Esfuerzo | ¿Requiere al dueño? |
|---|---|---|---|---|---|
| 1 | **Documentación dice la verdad del modo oscuro**: manifiesto, `CLAUDE.md`, ACCESIBILIDAD, CONTRATO; catálogo con dos columnas | H3 | L | S | No (ejecuta una decisión ya tomada) |
| 2 | **Dynamic Type sin techo**: tope global fuera, `caption*` escalable, gate `no-fixed-text-font` | H1 | P | M | **Sí**: revierte FER-394 |
| 3 | **Compuerta de accesibilidad del vidrio**: Reducir transparencia → sólido; Aumentar contraste → borde y tinte; Diferenciar sin color en mosaicos | H2 | P | M | No |
| 4 | **Alias de duplicados y test anti-duplicado** en `LiquidColor` | H4.1 | L | S | No |
| 5 | **Tokens DTCG 2025.10**: objetos de color, resolver claro/oscuro/OLED, legado con `$deprecated` | H5 | L | S–M | No |
| 6 | **Regresión visual mínima**: 10 componentes × modo × tamaño × contraste | H6 | P | M | **Sí**: dependencia o comparador propio |
| 7 | **Deprecación formal del legado interno y lote de poda** | H8 | L | M | Fecha del rollback |
| 8 | **Ola de nombres El Eje** (API, archivos, regla de idioma), con 2.0.0 | H7, H4.2 | P | L | **Sí**: API pública y regla de idioma |
| 9 | **Arquitectura de docs** (normativo e `historico/`) | H9 | L | S | No |
| 10 | **Gates por AST y consolidación de reglas** | H10, H11 | P | M | No |

Con 1 a 5, el sistema pasa de 4 a 4.5. Con 6 a 8, llega a nivel 5: un sistema que cualquier
persona, humana o agente, usa bien sin preguntar, en todos los modos y tamaños.

---

## 5. Fuentes

**Externas**
- W3C Design Tokens Community Group, [primera versión estable de la especificación (2025.10)](https://www.w3.org/community/design-tokens/2025/10/28/design-tokens-specification-reaches-first-stable-version/). Módulos [Format](https://www.designtokens.org/tr/drafts/format/), [Color](https://www.designtokens.org/tr/drafts/color/) y [Resolver](https://www.designtokens.org/tr/drafts/resolver/).
- Penpot, [issue #9305: el `$value` de color en DTCG 2025.10 exige objeto](https://github.com/penpot/penpot/issues/9305). Style Dictionary, [DTCG](https://styledictionary.com/info/dtcg/).
- Apple, [Meet Liquid Glass (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/219/): capa de navegación, no vidrio sobre vidrio, adaptación automática a Reducir transparencia, Aumentar contraste y Reducir movimiento.
- Apple, [HIG de tipografía](https://developers.apple.com/design/human-interface-guidelines/foundations/typography/) y [The details of UI typography (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10175/).
- Apple, [Accessibility Nutrition Labels](https://apps.apple.com/us/story/id1814164299) y los [criterios de Dark Interface](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria/): Larger Text ≥ 200 %, Sufficient Contrast, Differentiate Without Color, Reduced Motion.
- Six Colors, [Soaping up Liquid Glass: less transparency, more contrast](https://sixcolors.com/post/2025/11/soaping-up-liquid-glass-less-transparency-more-contrast/).
- NN/g, [Design-System Maturity: A 6-Dimension Framework](https://www.nngroup.com/articles/design-system-maturity/). zeroheight, [Design System Maturity Model](https://zeroheight.com/maturity/).
- Nathan Curtis (EightShapes), [Versioning Design Systems](https://medium.com/eightshapes-llc/versioning-design-systems-48cceb5ace4d) y [Visual Breaking Change in Design Systems](https://medium.com/eightshapes-llc/visual-breaking-change-in-design-systems-1e9109fac9c4).
- Arquitectura de tokens en tres capas: [Design Tokens and Theming Architecture](https://sujeet.pro/articles/design-tokens-and-theming). Gobierno: [SeaLab, Governance Models, Metrics, and ROI](https://sealab.design/blog/design-system-governance/).

**Internas.** `DESIGN.md`, `LIQUID-GLASS.md`, `CONTRATO.md`, `CATALOGO.md`, `ACCESIBILIDAD.md`,
`CENSO.md`, `historico/AUDITORIA-SISTEMA.md`, `RETIRADAS.md`, `docs/DECISIONS.md`, `design-tokens.json`,
`Tools/design-drift-baseline.json`, `LiquidColor.swift`, `LiquidType.swift`,
`LiquidGlassRecipes.swift`, `CenitApp/App/CenitApp.swift` y `AjustesView.swift`.

---

## 6. Seguimiento (2026-09-23, misma sesión)

| Hallazgo | Estado | Nota |
|---|---|---|
| H1 Dynamic Type | **Abierto: decisión del dueño** | El tope sale de un comentario de FER-394 en `CenitApp.swift` («no prometemos las 5 tallas de accesibilidad: romperían los layouts densos de un vistazo»). No está en `DECISIONS.md`. Desde entonces FER-501 hizo que 7 layouts cedan a tallas AX y varios componentes ya tienen camino de columna única que la app nunca alcanza. Recomendación: levantar el tope por etapas (primero `.accessibility3`, que ya pasa el 200 % de la etiqueta de Apple), manteniendo caps por componente para anillo, dial, keypad y tab bar. |
| H2 Vidrio y accesibilidad | **Abierto: carril pesado** | No cambia nada para quien no activa esos ajustes. Se ejecuta con verificación en simulador. |
| H3 Modo oscuro en docs | **Hecho en prosa** | DESIGN, CLAUDE.md, CONTRATO, ACCESIBILIDAD, RETIRADAS, LENGUAJE, contrato de hojas, LIQUID-GLASS, ARCHITECTURE y las instrucciones de `/ui` y `/criterio`. Pendiente: la columna oscura en `CATALOGO.md` y los modos en `design-tokens.json` exigen cambiar el generador en Swift (FER-451 resuelve en `.light` a propósito) y correrlo en macOS. |
| H4 Tokens y duplicados | **Matizado** | Este repo decidió «rol ≠ valor» (FER-273/275): dos nombres con el mismo valor pueden ser dos roles legítimos. `positivo`/`verdeProfundo` y `atencion`/`ambar` son iguales en claro **y** en oscuro, así que el cambio correcto no es fusionarlos, sino que el rol apunte al primitivo (`positivo = verdeProfundo`) para que no diverjan por accidente. Es Swift: pendiente de una sesión con toolchain. |
| H5 DTCG 2025.10 | Abierto | Cambio en el generador (Swift). |
| H6 Regresión visual | Abierto: decisión del dueño | Dependencia de pruebas o comparador propio. |
| H7 Nombres | Abierto: decisión del dueño | API pública. |
| H8 Deprecaciones | Abierto | Swift. |
| H9 Docs dispersas | **Hecho en parte** | Seis fotos históricas en `historico/` con README. `DESIGN.md §8` no se movió: contiene el bloque que regenera `CenitDesignTokens`. |
| H10 Gates por AST | Abierto | Refactor de tooling; beneficio bajo frente a su riesgo hoy. |
| H11 Reduce Motion central | Abierto | Swift. |

**Por qué el resto sigue abierto.** Esta sesión corre en Linux sin toolchain de Swift, y
`CenitDesign` depende de SwiftUI, que no existe en Linux. Ningún cambio de Swift podía pasar por
`Tools/verify.sh`, y el repo no acepta Swift sin verificar.
