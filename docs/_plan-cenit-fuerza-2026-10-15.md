# Cénit Fuerza — plan de acción (PM, 2026-10-15)

> Propuesta del product manager (Claude) con carta blanca del dueño. **No implementa nada.** Cada ola se
> baja a issues de Multica y briefs para los carriles de implementación (Grok / DeepSeek / Sonnet) solo
> cuando el dueño dé el OK a este documento. Reemplaza, si se aprueba, el «camino B» del 2026-09-14 por un
> «camino C+» y se registra en `docs/DECISIONS.md`.

## 0 · Estado real (verificado en el repo)

| Hecho | Dato |
|---|---|
| Último commit | 2026-09-15 (FER-512). Un mes parado. |
| Tienda | No enviada; bloqueo de papeleo (FER-15). **Cero usuarios, cero datos que migrar.** |
| Motor de recuperación (`CenitAnalytics`) | 16,530 líneas |
| Pantallas de salud (Hoy, Hoja, Cuerpo, Tendencias, Sueño, Estrés, Temp, Comparar, Edad…) | ≈ 20,000 líneas |
| Importador Apple Salud (`CenitImport`) | 3,810 líneas; 25 tipos de HealthKit pedidos |
| Dominio de fuerza (`CenitTraining`) | 2,615 líneas puras, con tests |
| Sistema de diseño (`CenitDesign`) | 48,712 líneas (mucho sirve solo a pantallas de salud) |
| Watch | 2,573 líneas; registra series con la corona; **sin CoreMotion** (sensor de movimiento) |
| Tests | 286 archivos en paquetes + 77 en app |

## 1 · Tesis

**Cénit es el cuaderno de fuerza que te lleva de la mano.** Apple se queda con dormir, recuperarse y la
salud; Cénit se queda con la barra. El pitch cambia de «te dice cuánto cargar hoy y por qué» a:

> **«Abres, entrenas, y la app sabe cuál es tu siguiente paso.»**

Lo que vende no es un número de preparación: es que nunca tienes que pensar qué peso poner, cuándo subir,
ni cuándo bajar. Eso ninguna de las 12 apps de fuerza revisadas en septiembre lo hace bien en español, y
Apple no lo anunció (sus estructuras de series/reps siguen en beta sin API).

## 2 · Seis rupturas de paradigma

1. **La sesión es la app.** Al abrir estás a un toque de la serie 1 de hoy. Sin hub, sin mosaico de siete
   tiles, sin pestañas. Una pantalla con tres estados: *antes* (tu rutina de hoy y el siguiente paso),
   *durante* (la serie), *después* (el acta). Progreso y Plan son hojas que se abren desde ahí.
2. **Watch primero, iPhone después.** El iPhone se queda en la mochila. El Watch registra (corona hoy,
   repeticiones automáticas mañana); el iPhone revisa, edita y planea.
3. **Un dato por ejercicio: el siguiente paso.** «Sentadilla: 3×8 con 80 kg. Si sacas 8-8-8, la próxima
   son 82.5.» Nada de gráficas en la cara principal; las gráficas viven en el detalle.
4. **Apple Salud sale de la puerta de entrada.** La app pide permiso solo para *escribir* el entreno en
   Salud y leer pulso durante la sesión, y lo pide **al terminar la primera sesión**, no en el onboarding.
   El onboarding de seis actos se vuelve dos pantallas.
5. **Guiar de la mano es una máquina de estados, no un chat.** Doble progresión, semana ligera
   automática por estancamiento, sustituto cuando falta el aparato. Todo determinístico, citado y probado
   (regla del repo: matemática transparente). La IA local llega después y solo como lenguaje.
6. **Mismo código, app nueva.** No se parchan 983 archivos: se levanta un cascarón nuevo y se traen
   solo las pantallas de fuerza, una por una, con compilación verde en cada paso. Lo que no cruce, se
   borra. Los paquetes puros (`CenitTraining`, `CenitDesign`, `CenitStore`) se reusan.

## 3 · Qué se va, qué se queda

**Se va (sin puerta y después borrado):** `CenitAnalytics` entero salvo `TrainingLoad`/ACWR si se
conserva la carga de fuerza; `CenitImport`; pantallas Hoy, Hoja, Cuerpo/Tendencias, Sueño, Estrés,
Temperatura, Esfuerzo, Preparación, Comparar, Edad física/corporal, Ciclo, Respirar, Guardián de
enfermedad, Explorador de métricas, Fuentes de datos, aviso matutino, historial FA; widgets de «la
palabra»; Live Activity de pulso (se queda la de serie/descanso); 21 de los 25 tipos de HealthKit;
enseñanza y ayuda de todo lo anterior.

**Se queda:** sesión en vivo (`LiveStrengthSheet`, `StrengthSessionModel`), rutinas y plan semanal,
programa multi-semana con deload, progresión por ejercicio, RIR/AMRAP/drop, descansos (fijo y por pulso),
biblioteca y detalle de ejercicio, atlas muscular (sin cruce con recuperación), marcas, historial y
ciclos de subida, discos, acta/ticket, importar Strong/Hevy y plan por CSV, intervalos, Watch, widgets
de rutina, Live Activity de serie.

**Decisión abierta para el dueño (la única):** ¿se conserva una señal mínima «cómo amaneciste» (horas de
sueño y FC en reposo que Apple ya calcula; ~300 líneas, no 16,000) para que la progresión diga «dormiste
5 h, hoy mantengo»? Recomendación: **sí, opcional y apagada por defecto**, como una línea dentro de la
sesión, nunca como pantalla. Si dices «cero salud», el plan no cambia; se quita esa línea.

## 4 · Olas

### Ola 0 · Decidir y cortar (semanas 1-2) — carril ligero + 1 pesado
- Entrada en `DECISIONS.md`: «camino C+», con las seis rupturas y la respuesta a la decisión abierta.
- Spec `docs/specs/fuerza-v1/` : las tres pantallas-estado, el onboarding de dos pasos, permisos tardíos,
  esquema de base **nuevo** (v1 solo fuerza; se colapsan las 44 migraciones porque no hay usuarios).
- Cascarón `CenitFuerza` (target nuevo o el mismo target con `App/` vaciado): compila con cero pantallas.
- Matriz de alcanzabilidad: qué pantalla cruza, cuál no.
- DoD: build verde del cascarón; `strings` del binario sin «recovery/readiness/preparación».

### Ola 1 · El núcleo que guía (semanas 2-5) — carril pesado
- Migrar sesión en vivo, rutinas, plan, biblioteca, historial, marcas, discos, acta. Un dueño por archivo
  caliente; una pantalla por PR.
- **Motor «siguiente paso»** en `CenitTraining`: doble progresión (reps luego peso), regla de
  estancamiento (3 sesiones sin cumplir → bajar 10 % o cambiar rango), deload automático cada N semanas,
  sustituto por músculo cuando falta el aparato. Método citado (Helms, Schoenfeld) y tests.
- Pantalla *antes*: rutina de hoy + «siguiente paso» por ejercicio + botón único.
- Pantalla *después*: acta en tres líneas (qué subió, qué se mantuvo, qué sigue).
- Onboarding de dos pasos (elige plantilla o importa; empieza).
- DoD: de abrir la app a registrar la primera serie en < 10 s sin tocar ajustes.

### Ola 2 · El Watch cuenta por ti (semanas 5-8) — spike + carril pesado
- **Spike desechable de una semana**: CoreMotion (acelerómetro + giroscopio del Watch) para detectar
  repeticiones en movimientos cíclicos (sentadilla, press, remo, curl, jalón). Criterio para seguir:
  ≥ 90 % de aciertos en 5 ejercicios con el reloj en la muñeca habitual; si no se alcanza, se queda la
  corona y se cierra el tema con nota en DECISIONS.
- Si pasa: inicio/fin de serie automático → descanso arranca solo; la cuenta se confirma con un toque.
- Watch como registro completo sin iPhone (ya existe en parte: pulir y hacerlo la ruta principal).
- Complicación: siguiente serie / descanso.

### Ola 3 · Tienda (semanas 8-10)
- Cerrar el papeleo FER-15 (cuenta, identidad, privacidad, soporte, bundle id).
- Descripciones de uso de HealthKit solo para lo que se pide (dos tipos).
- Ficha de tienda con el pitch nuevo; capturas de las tres pantallas-estado y del Watch.

### Ola 4 · IA local como lenguaje (después de la tienda)
- Mismas tres puertas acordadas el 2026-09-14: crear rutina por texto o foto (salida tipada), acta en
  palabras, buscar/sustituir ejercicio en español. Foundation Models en el iPhone; nada en el Watch.
- **Regla de oro intacta:** el modelo es capa de lenguaje; `CenitTraining` sigue calculando. Sin modelo,
  la app es completa.
- Después, App Intents para Siri («registra 8 con 80») y el botón de Acción.

### Ola 5 · Poda y pago (v1.x)
- Podar `CenitDesign` a lo que usan las pantallas vivas (hoy 48 k líneas).
- Decidir modelo de cobro (hoy: gratis; decisión 2026-09-06).

## 5 · Cómo se mide

| Señal | Meta |
|---|---|
| Abrir → primera serie registrada | < 10 s |
| Series registradas desde el Watch | > 60 % de las series |
| «Siguiente paso» aceptado sin editar | > 70 % |
| Sesiones por semana por usuario activo | ≥ 2 |
| Líneas de código del app | ≈ 40 % de las actuales |

## 6 · Cómo se ejecuta sin gastar de más

- **Fable/Opus** (esta sesión): decisiones, specs, criterios de aceptación, revisión de PRs. No escribe
  código.
- **DeepSeek**: el borrado masivo y la matriz de alcanzabilidad (mecánico, bien especificado).
- **Grok**: migrar pantallas una por una con el brief de cinco partes; revisa adversarialmente lo que
  no escribió.
- **Sonnet**: el motor «siguiente paso» (lógica con tests) y el spike de CoreMotion.
- `/orquesta` por ola, con `/tablero` obligatorio. Una ola = un épico de Multica.

## 7 · Riesgos

- **Enredo Entrenar ↔ Hoy:** el héroe de Entrenar lee `LiquidHoyBuilder.hiloEntrenar`. Se corta con un
  tipo nuevo `SiguientePaso` en `CenitTraining`; no se intenta desenredar in situ.
- **CoreMotion no alcanza el 90 %:** se queda la corona; el spike es desechable por diseño.
- **Tentación de conservar «por si acaso»:** el criterio es la matriz de alcanzabilidad y el `strings`
  del binario, igual que en FER-380.
- **Proyecto Multica:** el workspace ahora mezcla issues `CEN-` de otros productos; confirmar el
  proyecto «Cénit iOS» antes de crear el épico.

## 8 · Qué sigue cuando des el OK

1. Respondes la decisión abierta (señal mínima «cómo amaneciste»: sí / no).
2. Escribo la entrada de `DECISIONS.md`, la spec de ola 0 y el épico en Multica con sus issues.
3. Lanzo `/orquesta` para la ola 0 y te muestro el tablero.
