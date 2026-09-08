#!/usr/bin/env python3
"""Inject Spanish (es) translations into Cenit/Resources/Localizable.xcstrings.

Reads the English (en) base values and adds an `es` stringUnit for each key.
The translation is authored in Latin American / Mexican Spanish (tuteo, "esta
Mac", "banda" for a wearable band). The generic `es` locale is used so every Spanish
device — es-MX, es-419, es-ES — resolves to it via the system fallback chain.

Format placeholders (%@, %lld, %%) are preserved. Pure symbol / placeholder-only
strings are passed through unchanged. Re-runnable: existing `es` units are
overwritten so this file stays the source of truth for the Spanish translation.
"""
import importlib.util
import json
import re
from pathlib import Path

CATALOG = Path("Cenit/Resources/Localizable.xcstrings")
FINDER = Path(__file__).resolve().parent / "find-dead-strings.py"


def load_finder():
    """Import Tools/find-dead-strings.py (hyphenated, so not a normal module)."""
    spec = importlib.util.spec_from_file_location("find_dead_strings", FINDER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

# English key -> Spanish value. Keys must match the catalog exactly.
ES: dict[str, str] = {
    "Night · %lld cycles": "Noche · %lld ciclos",
    "Night": "Noche",
    # FER-878 — Pulido de «Hoy» al ADN §8.7 / handoff Detalle de Tendencias.
    # Regla de copy FER-642/836: toda comparación es «vs tu base»; sin em-dash (·, :, coma).
    "vs your baseline": "vs tu base",
    "At your baseline": "En tu base",
    "No baseline of your own yet": "Sin base propia aún",
    "computed on your phone": "calculado en tu teléfono",
    "The five marks below add up to your recovery of %lld.":
        "Las cinco marcas de abajo suman tu recuperación de %lld.",
    "The longer a mark, the more that signal weighed today.":
        "Mientras más larga la marca, más pesó esa señal hoy.",
    "HRV (how your heart's timing varied overnight) carries the most weight, because it's the earliest sign of how recovered you are.":
        "La VFC (cómo varió el ritmo de tu corazón durante la noche) es la que más pesa, porque es la señal más temprana de qué tan recuperado estás.",
    # Barrido de em-dashes (claves de copy nuevas tras el reemplazo · / : / punto).
    "Support Cénit · donate or get in touch": "Apoya a Cénit · dona o escríbenos",
    "Short night · low confidence": "Noche corta · confianza baja",
    "All %lld nights are in. Computing your first verdict.":
        "Las %lld noches están completas. Calculando tu primer veredicto.",
    "Your own baseline sharpens each night · you're at %lld.":
        "Tu base se afina cada noche · vas en %lld.",
    # Atribución por cobertura en Recuperación estimada (día Apple-only): el bloque «Hoy, vs tu normal»
    # ahora siempre presente, mostrando dirección por señal vs tu norma de Apple (sin puntos).
    "Where the signals Apple recorded sat vs your usual. Today's number is an estimate, so there's no point-by-point breakdown.":
        "Dónde quedaron las señales que registró Apple frente a tu normal. El número de hoy es un estimado, así que no hay desglose punto por punto.",
    "Above your usual": "Por arriba de tu normal",
    "Below your usual": "Por abajo de tu normal",
    "Around your usual": "En tu normal",
    "Recorded": "Registrado",
    "No resting HR last night": "Sin FC en reposo anoche",
    "No sleep data last night": "Sin datos de sueño anoche",
    "Not recorded last night": "No se registró anoche",
    # Flujo Entrenar v4 — primer uso (5a): renglón de plantillas + Constancia vacía.
    "Your sessions will appear here, each in its routine's color.": "Tus sesiones aparecerán aquí, en el color de su rutina.",
    # FER-830 — reconciliación Ola 3: calendarios Sueño/Esfuerzo.
    "Calendar · 90 nights": "Calendario · 90 noches",
    "Tap a night to see its sleep.": "Toca una noche para ver su sueño.",
    "Tap a day to see its strain.": "Toca un día para ver su esfuerzo.",
    # FER-832 — Estrés: calendario de 90 días.
    "Tap a day to see its stress.": "Toca un día para ver su estrés.",
    # FER-833 — VO₂max: 2 tiles compactos (categoría + edad equivalente).
    "FITNESS CATEGORY": "CATEGORÍA DE FORMA",
    "EQUIVALENT AGE": "EDAD EQUIVALENTE",
    # FER-826 — Landing de Tendencias §8.7: micro-leyenda + leyenda de orígenes.
    "Today's values · last month's trends": "Valores de hoy · tendencias del último mes",
    "band": "banda",
    "computed": "calculado",
    # FER-824 — Pasos: 3 tiles + «Qué mueve tus pasos».
    "TODAY": "HOY",
    "7-DAY AVG": "MEDIA 7 D",
    "STREAK": "RACHA",
    "What moves your steps": "Qué mueve tus pasos",
    # FER-806 — Tendencias v2: sello de origen + toggle compacto Media/Rangos.
    "Computed": "Calculado",
    "Mean": "Media",
    "today, in progress": "hoy, en curso",
    # FER-831 — Recuperación: Panorama 2×2 (pronóstico + rango + estabilidad + carga).
    "Panorama": "Panorama",
    "Tomorrow": "Mañana",
    "Rising": "Al alza",
    "Falling": "A la baja",
    "A forecast is a projection, not a guarantee.":
        "El pronóstico es una proyección, no una garantía.",
    # FER-459/469 — «N días/noches» por banda en la lista de rangos. Las líneas
    # «%lld of the last %lld days/nights in this range» y «%lld days» ya existen en el catálogo.
    "%lld day": "%lld día",
    "%lld night": "%lld noche",
    # "%lld nights": plural-managed in the String Catalog (one/other, FER-912) — no re-add (clobbers plural).
    # FER-763 — Temperatura de piel reemplaza a Oxígeno en sangre en la retícula de SEÑALES + su hoja.
    "Measured at your wrist; the deviation from your personal baseline matters more than the absolute value. An isolated reading is usually noise, like a cold room or how the sensor sat. A sustained run is what's worth a look.":
        "Medida en tu muñeca; importa la desviación de tu base personal, no el valor absoluto. Una lectura aislada suele ser ruido, como un cuarto frío o cómo quedó el sensor. Una racha sostenida es lo que vale la pena mirar.",
    "Running warm": "Ligeramente elevada",
    "Below your base.": "Debajo de tu base.",
    "In your base.": "En tu base.",
    "Running warm vs your base.": "Ligeramente por encima de tu base.",
    "Well above your base, worth a look.": "Muy por encima de tu base, vale la pena revisar.",
    # Detalle de Vital — rediseño narrativo (Hoy → Tu historia → (Tu patrón) → Método)
    # Hero overlines («{métrica} · hoy»)
    # Hero — lectura de hoy, palabra de veredicto y contexto de 7 días
    "min %@ · max %@ · resting %@ bpm": "mín %@ · máx %@ · reposo %@ bpm",
    "min %@ · max %@ bpm": "mín %@ · máx %@ bpm",
    "Normal for you": "Normal para ti",
    "Unusual for you": "Inusual para ti",
    "Healthy": "Sano",
    "7-day level · %@": "nivel 7 días · %@",
    "7-day level · %@ %@": "nivel 7 días · %@ %@",
    # Header readings (re-encuadradas a «hoy», ya no «el promedio de la última semana»)
    "Higher HRV usually means better recovery. What matters is your trend, not any single day's number.": "Más variabilidad suele ser mejor recuperación. Lo que importa es tu tendencia, no el número de un día.",
    "Your pulse when your body is calm. Lower usually means better fitness; a rise above your normal can be fatigue.": "Tu pulso cuando el cuerpo está en calma. Más bajo suele ser mejor estado; una subida sobre tu normal puede ser fatiga.",
    "One of your steadiest signals. A rise above your own normal can be an early sign that something is taxing you.": "De tus señales más estables. Una subida sobre tu propio normal puede ser señal temprana de que algo te está exigiendo.",
    "The oxygen in your blood, read at your wrist while you sleep. A healthy adult usually stays at 95% or above.": "El oxígeno en tu sangre, medido en la muñeca mientras duermes. Un adulto sano suele mantenerse en 95% o más.",
    # Banda inline «hoy vs tu rango»
    "your normal range · %lld nights": "tu rango normal · %lld noches",
    "healthy zone ≥ 95%": "zona sana ≥ 95%",
    "Healthy zone": "Zona sana",
    # Selector media móvil ⇄ rangos + caption del modo rangos + etiquetas de banda
    "Ranges": "Rangos",
    "Where you fall against the typical ranges.": "Dónde caes frente a los rangos típicos.",
    "Athlete": "Atleta",
    "Excellent": "Excelente",
    "Typical": "Típica",
    "Sedentary": "Sedentario",
    "Very active": "Muy activo",
    # Caption de la gráfica que nombra la banda (explica las líneas horizontales)
    "7-day moving average · the band is your normal range.": "Media móvil de 7 días · la franja es tu rango normal.",
    # Indicador «días dentro de tu rango» (HRV/FC reposo/Respiración)
    # Overlines de sección
    "Your story": "Tu historia",
    "Your pattern": "Tu patrón",
    "Your day": "Tu día",
    "Reference range": "Rango de referencia",
    # Tira de stats (celdas tocables)
    "Average": "Promedio",
    "Range": "Rango",
    "Nights < 95%": "Noches < 95%",
    "of %lld": "de %lld",
    "Min": "Mín",
    "Max": "Máx",
    # Disclosure de consistencia (lenguaje llano + mini-visual estable/variable)
    # SpO₂ — disclosure de la zona sana
    # Tu patrón
    "What moves it": "Qué la mueve",
    "trend, not cause": "tendencia, no causa",
    "Other signals from last night": "Otras señales de anoche",
    "Resting HR %@": "FC en reposo %@",
    # Temperatura de piel — rediseño narrativo
    "First night warmer": "1.ª noche más cálida",
    "%lld nights warmer": "%lld noches más cálidas",
    "First night cooler": "1.ª noche más fría",
    "%lld nights cooler": "%lld noches más frías",
    "Variation": "Variación",
    # Cuerpo es-MX — cadenas huérfanas del «mapa del día» (FER-433/377) + detalles de
    # Estrés / Sueño / Esfuerzo que nunca se extrajeron al catálogo y caían al inglés.
    # StressDayMapView — «Momentos primero»
    'Your highest point today was at %@.': 'Tu punto más alto de hoy fue a las %@.',
    'no event on your calendar': 'sin evento en tu calendario',
    # StressBarsStrip — gráfica por hora arrastrable (FER-447)
    'no reading': 'sin lectura',
    'during activity or sleep': 'durante actividad o sueño',
    'All day: %@. Not matched to a moment.': "Todo el día: %@. No se cruza con un momento.",
    'now': 'ahora',
    # StressDetailScreen — «Tus patrones» + «Ve tu historial»
    'of last month': 'del último mes',
    'Steadiness': 'Estabilidad',
    'week to week': 'semana a semana',
    'Very steady': 'Muy estable',
    # SleepDetailScreen — «Tus patrones», etapas vs típico, etiquetas de VoiceOver
    'How well': 'Qué tan bien',
    'Stages': 'Etapas',
    'Sleep debt': 'Deuda de sueño',
    '%lld%% of your need': '%lld%% de lo que necesitas',
    '%@, %lld%% last night': '%@, %lld%% anoche',
    ', typical %lld%%': ', típico %lld%%',
    # StrainDetailScreen — «Ve tu historial»
    # RecoveryDetailScreen — «Tus patrones» + accesibilidad de gráficas
    'Usually': 'Normalmente',
    # SkinTempDetailScreen — banda «típico»
    'typical': 'típico',
    # CuerpoView — tarjeta de Actividad
    # MetricInfoSheet — accesibilidad de la gráfica de tendencia
    '14-day trend with classification bands': 'tendencia de 14 días con bandas de clasificación',
    # FER-409 / 390 — Resumen post-sesión de fuerza + toggle «Guardar en Apple Salud»
    "Summary": "Resumen",
    "Effort": "Esfuerzo",
    "What this session cost your body.": "Lo que le costó a tu cuerpo esta sesión.",
    "Duration": "Duración",
    "No heart rate this session.": "Sin frecuencia cardiaca esta sesión.",
    "Volume": "Volumen",
    "Sets": "Series",
    "Record": "Marca",
    "Max weight": "Peso máximo",
    "Most reps": "Más repeticiones",
    "Best set": "Mejor serie",
    "Low cardiovascular cost. Your body barely felt it.": "Costo cardiovascular bajo. Tu cuerpo apenas lo resintió.",
    "A session that counted. Give yourself some rest.": "Un esfuerzo que sí contó. Date tu descanso.",
    "A demanding session. Make sleep a priority today.": "Una sesión exigente. Prioriza dormir hoy.",
    "First time logging these. From here on you'll see your progress.": "Primer registro de estos ejercicios. A partir de aquí vas a ver tu progreso.",
    "Today's muscles": "Músculos de hoy",
    "Save workouts to Apple Health": "Guardar entrenamientos en Apple Salud",
    "Your strength sessions appear in Health and count toward your Move ring, with estimated calories.": "Tus sesiones de fuerza aparecen en Salud y cuentan para tu anillo de Movimiento, con calorías estimadas.",
    # FER-397 — Estrés: fallback al último día con dato (tope ayer, fechado)
    # FER-388 — Patrones de estrés por evento
    '«%@» tends to coincide with higher stress.': '«%@» tiende a coincidir con tu estrés alto.',
    '«%@» tends to coincide with lower stress.': '«%@» tiende a coincidir con tu estrés bajo.',
    # FER-378 — Patrones de estrés por momento del día
    'Your patterns': 'Tus patrones',
    'Your stress tends to run higher in the %@.': 'Tu estrés tiende a ser más alto por las %@.',
    'Your stress tends to run lower in the %@.': 'Tu estrés tiende a ser más bajo por las %@.',
    'Your stress tends to run higher on %@.': 'Tu estrés tiende a ser más alto los %@.',
    'Your stress tends to run lower on %@.': 'Tu estrés tiende a ser más bajo los %@.',
    'Your stress usually peaks around %@.': 'Tu estrés suele alcanzar su punto más alto alrededor de las %@.',
    'mornings': 'mañanas',
    'afternoons': 'tardes',
    'evenings': 'noches',
    'late nights': 'madrugadas',
    # FER-351 — Variantes del Foco por tipo de ejercicio
    'Time': 'Tiempo',
    'Bodyweight': 'Peso corporal',
    'reps': 'reps',
    'time': 'tiempo',
    'Added weight': 'Lastre',
    'optional': 'opcional',
    'optional · bodyweight only': 'opcional · solo peso corporal',
    'Stop and save': 'Parar y registrar',
    'Stop': 'Parar',
    'Goal %@': 'Objetivo %@',
    'Zone %lld': 'Zona %lld',
    'distance': 'distancia',
    '%lld reps': '%lld reps',
    'Decrease added weight': 'Bajar lastre',
    'Increase added weight': 'Subir lastre',
    'Decrease distance': 'Bajar distancia',
    'Increase distance': 'Subir distancia',
    'Start the timer': 'Iniciar el cronómetro',
    'Stop the timer': 'Parar el cronómetro',
    'Distance %@ %@': 'Distancia %@ %@',
    'miles': 'millas',
    # FER-386 — Plantillas de arranque
    'Start from a template': 'Empieza con una plantilla',
    'Begin with a proven base and edit it to taste.': 'Empieza con una base probada y edítala a tu gusto.',
    'Push Pull Legs': 'Empuje · Jalón · Pierna',
    'Full body': 'Cuerpo completo',
    'Upper / Lower': 'Torso / Pierna',
    'At home': 'En casa',
    'Push day': 'Empuje',
    'Pull day': 'Jalón',
    'Leg day': 'Pierna',
    'Upper body': 'Torso',
    'Lower body': 'Inferior',
    'chest, shoulders, triceps': 'pecho, hombro, tríceps',
    'back, biceps': 'espalda, bíceps',
    'quads, glutes, hamstrings': 'cuádriceps, glúteo, femoral',
    'the whole body': 'todo el cuerpo',
    'chest, back, arms': 'pecho, espalda, brazos',
    'full legs': 'pierna completa',
    'no equipment': 'sin equipo',
    'strength': 'fuerza',
    'Templates': 'Plantillas',
    'Add to my routines': 'Agregar a mis rutinas',
    "It's copied into «My routines». You can edit it like any routine.": 'Se copia a «Mis rutinas». Podrás editarla como cualquier rutina.',
    '%lld sets': '%lld series',
    '%lld seconds': '%lld segundos',
    'Preview this template': 'Ver esta plantilla',
    'Back to templates': 'Volver a plantillas',
    # FER-377 — Estrés × calendario: el «mapa del día»
    'Stress through the day': 'Estrés a lo largo del día',
    'Connect my calendar': 'Conectar mi calendario',
    'Open Settings': 'Abrir Ajustes',
    "Your calendar isn't available on this device because of a system restriction.": 'Tu calendario no está disponible en este dispositivo por una restricción del sistema.',
    "Choose which calendars to cross with your stress. You'll only see the ones you pick; nothing is shared.": 'Elige qué calendarios cruzar con tu estrés. Solo verás los que elijas; nada se comparte.',
    'Choose calendars': 'Elegir calendarios',
    'Crossing your day…': 'Cruzando tu día…',
    "I'm still learning your rhythm: I need a few days of waking readings to mark your peaks. Your events are already here.": "Aún estoy aprendiendo tu ritmo, necesito unos días de lecturas de vigilia para marcar tus picos. Tus eventos ya están aquí.",
    'All day': 'Todo el día',
    'Calendars: %@': 'Calendarios: %@',
    '· change': '· cambiar',
    "We'll only cross the ones you pick.": 'Solo cruzaremos los que elijas.',
    'There are no calendars on this iPhone yet.': 'Aún no hay calendarios en este iPhone.',
    'All day: %@. Not matched to a moment.': 'Todo el día: %@. No se cruza con un momento.',
    '(untitled)': '(sin título)',
    'Calendar access is off. Turn it on in Settings › Privacy & Security › Calendars › Cénit to see this cross-reference.': 'El acceso a tu calendario está desactivado. Actívalo en Ajustes › Privacidad y seguridad › Calendarios › Cénit para ver este cruce.',
    # FER-372 — Dieta: tracking diario (% de apego + checklist tri-estado)
    'Diet · today': 'Dieta · hoy',
    'adherence · %lld of %lld meals': 'apego · %lld de %lld comidas',
    'Mark your meals · 0 of %lld': 'Marca tus comidas · 0 de %lld',
    "Today's meals": 'Comidas de hoy',
    'Adherence · 7 days': 'Apego · 7 días',
    '7-day adherence trend': 'Tendencia de apego de 7 días',
    'Followed': 'Cumplí',
    'Swapped': 'Sustituí',
    'Skipped': 'Salté',
    # FER-385 — Coach: la dieta como palanca/experimento (etiqueta del comportamiento)
    'I followed my diet': 'Seguí mi dieta',
    # FER-402 — Dieta: navegación por día en el tracker (accesibilidad)
    'Previous day': 'Día anterior',
    'Next day': 'Día siguiente',
    # FER-401 — Dieta: elegir la opción/equivalente por comida
    'pick what you ate': 'elige la que comiste',
    'Other': 'Otra',
    # FER-431 — Dieta: ciclo semanal
    'Rest day · no meals planned': 'Día libre · sin comidas hoy',
    "Rest day: your plan has no meals today. Come back tomorrow or use ‹ ›.": "Día libre, tu plan no tiene comidas hoy. Vuelve mañana o usa ‹ ›.",
    'Days': 'Días',
    "That plan's cycle isn't supported: it must be daily or weekly.": "El ciclo de ese plan no es válido, debe ser diario o semanal.",
    "One of the meals has invalid days: use weekday numbers 1–7. Check the file and try again.": "Una comida tiene días inválidos, usa números de día 1–7. Revisa el archivo e inténtalo de nuevo.",
    "A weekly plan needs each meal's days. Check the file and try again.": 'Un plan semanal necesita los días de cada comida. Revisa el archivo e inténtalo de nuevo.',
    # FER-412 — Dieta: recordatorios locales por comida
    'Meal reminders': 'Recordatorios por comida',
    'On · %lld meals with a time.': 'Activos · %lld comidas con hora.',
    'Your plan has no suggested times.': 'Tu plan no trae horas sugeridas.',
    'Notifications are turned off.': 'Las notificaciones están desactivadas.',
    'Open Settings': 'Abrir Ajustes',
    'Did you mark this meal?': '¿Ya marcaste esta comida?',
    'Diet reminder': 'Recordatorio de dieta',
    # FER-410 — Dieta: calendario/heatmap de apego
    'Adherence · history': 'Apego · histórico',
    'Each cell is a day · greener = higher adherence. Tap a day to view it.': 'Cada celda es un día · más verde = más apego. Toca un día para verlo.',
    'Your daily adherence will appear here as you mark your meals.': 'Tu apego de cada día aparecerá aquí conforme marques tus comidas.',
    # FER-411 — Dieta: reglas/notas/objetivos del plan
    'Note: ': 'Nota: ',
    'Indications': 'Indicaciones',
    'Plan target · reference': 'Objetivo del plan · referencia',
    "Only what your plan declared. Cénit doesn't count calories.": 'Solo lo que tu plan declaró. Cénit no cuenta calorías.',
    # FER-403 — Dieta: captura a mano (formulario sin IA)
    'Capture by hand instead': 'Mejor captúralo a mano',
    'Diet · by hand': 'Dieta · a mano',
    'Build your plan': 'Arma tu plan',
    'Plan name': 'Nombre del plan',
    'Meals': 'Comidas',
    'Short name': 'Nombre corto',
    'Food': 'Alimento',
    'Add food': 'Agregar alimento',
    'Equivalent option': 'Opción equivalente',
    'Add meal': 'Agregar comida',
    'or equivalent': 'o equivalente',
    'Remove food': 'Quitar alimento',
    # FER-381 — Acerca de y soporte adelgazado: subtítulo acortado
    # FER-371 — Dieta: pantalla de captura (BYO-LLM)
    'Diet': 'Dieta',
    "You don't have a plan yet": 'Aún no tienes un plan',
    'Capture the diet your nutritionist gave you and follow it day to day.': 'Captura la dieta que te dejó tu nutriólogo y síguela día con día.',
    'Capture my plan': 'Capturar mi plan',
    'Capture plan': 'Capturar plan',
    "Bring your nutritionist's plan": 'Trae el plan de tu nutriólogo',
    'Copy the prompt and paste it into your trusted AI, along with your plan (PDF or photo).': 'Copia el prompt y pégalo en tu IA de confianza, junto con tu plan (PDF o foto).',
    'Copied': 'Copiado',
    'Copy prompt': 'Copiar prompt',
    "Bring back the file it gives you: paste it or upload it.": 'Trae el archivo que te dé: pégalo o súbelo.',
    'Upload .json file': 'Subir archivo .json',
    'Continue': 'Continuar',
    'Paste the result here…': 'Pega aquí el resultado…',
    'Paste your plan': 'Pega tu plan',
    'Review your plan': 'Revisa tu plan',
    'Your plan': 'Tu plan',
    'Save plan': 'Guardar plan',
    'Meal': 'Comida',
    'or': 'o',
    'Replace plan': 'Reemplazar plan',
    "We couldn't read that as a plan file. Paste the full result your AI gave you, or upload the .json.": 'No pudimos leer eso como un archivo de plan. Pega el resultado completo que te dio tu IA, o sube el .json.',
    "That file isn't a Cénit diet plan. Make sure you used the prompt above.": 'Ese archivo no es un plan de dieta de Cénit. Asegúrate de haber usado el prompt de arriba.',
    "The plan's language isn't supported: it must be Spanish or English.": "El idioma del plan no es compatible, debe ser español o inglés.",
    'That plan has no meals. Check the file and try again.': 'Ese plan no tiene comidas. Revisa el archivo y vuelve a intentar.',
    'One of the meals has no food options. Check the file and try again.': 'Una de las comidas no tiene opciones de alimentos. Revisa el archivo y vuelve a intentar.',
    'One of the meals has an empty option. Check the file and try again.': 'Una de las comidas tiene una opción vacía. Revisa el archivo y vuelve a intentar.',
    'The daily targets must be numbers. Check the file and try again.': 'Los objetivos diarios deben ser números. Revisa el archivo y vuelve a intentar.',
    # FER-69 — Reskin «Automatizaciones» a «Instrumento» + saneo Mac-only
    'Double-tap': 'Doble toque',
    'Shortcut name': 'Nombre del atajo',
    'Wear & presence': 'Uso y presencia',
    'Run a Shortcut when taken off': 'Ejecutar un atajo al quitártela',
    'Run a Shortcut when put back on': 'Ejecutar un atajo al ponértela',
    'Haptic coaching': 'Coaching háptico',
    'HR-zone coaching': 'Coaching por zona de FC',
    'Resting stress nudge (experimental)': 'Aviso de estrés en reposo (experimental)',
    'Smart alarm': 'Alarma inteligente',
    'Enable smart alarm': 'Activar alarma inteligente',
    "Presence automation: set a Focus, pause media, set away…": "Automatización de presencia, activa un modo de Concentración, pausa el audio, márcate ausente…",
    'Reverse the above when you return.': 'Revierte lo anterior cuando regresas.',
    'Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings.': 'Zumba cuando llegas a tu zona más alta (baja el ritmo) y otra vez cuando te recuperas. Usa tu FC máx de Ajustes.',
    "A gentle buzz when your HRV drops while your heart rate is calm: a cue to take a paced breath. Rate-limited to once every 15 minutes; off by default.": "Un zumbido suave cuando tu HRV baja mientras tu pulso está en calma, una señal para respirar con calma. Limitado a una vez cada 15 minutos; apagado por defecto.",
    "Watches your resting HR, HRV, skin temperature and respiration against your own 28-day baseline. On-device and approximate: informational only, not a diagnosis.": "Vigila tu FC en reposo, HRV, temperatura de la piel y respiración contra tu propia base de 28 días. En el dispositivo y aproximado, solo informativo, no un diagnóstico.",
    "Needs at least 14 days of history. When two or more signals drift together you get a notification: at most once a day.": "Necesita al menos 14 días de historial. Cuando dos o más señales se desvían juntas, recibes una notificación, máximo una vez al día.",
    # FER-337 — Rediseño de Ajustes a «Instrumento»: raíz + sub-pantallas (Unidades, Log) + huérfanos rehubicados
    'Units & format': 'Unidades y formato',
    'Data & sources': 'Datos y fuentes',
    'About & support': 'Acerca de y soporte',
    'Display': 'Visualización',
    "Your data is always stored the same way: this only changes how distances, weights, heights and temperatures are shown.": 'Tus datos siempre se guardan igual; esto solo cambia cómo se muestran distancias, pesos, estaturas y temperaturas.',
    'View imported data': 'Ver datos importados',
    'Automations': 'Automatizaciones',
    # FER-338 — Reskin «Datos y fuentes» + visor Apple Health a «Instrumento»: cadenas nuevas/visibles
    'Import': 'Importar',
    'Coverage': 'Cobertura',
    'Backup': 'Respaldo',
    'Nothing imported yet': 'Aún no importas nada',
    'On an iPhone: Health app, tap your photo, Export All Health Data, then import the .zip here in Data Sources.': 'En un iPhone: app Salud, toca tu foto, Exportar todos los datos de salud, y luego importa el .zip aquí en Datos y fuentes.',
    "Steps, heart, sleep, body composition and VO₂ max: read locally on this iPhone.": "Pasos, corazón, sueño, composición corporal y VO₂ máx, leídos localmente en este iPhone.",
    'Apple-logged': 'Registrado por Apple',
    # FER-312 — Pregúntale (Coach): los 2 strings que faltaban en es (setup + footnote de privacidad)
    # FER-299 — Honestidad estadística de Insights: framing de asociación + autocorrelación
    "Association, not cause: moving together isn't one driving the other.": "Asociación, no causa, moverse juntas no es que una empuje a la otra.",
    'carry-over': 'arrastre',
    # FER-277 — Detalle de Recuperación: bloque de pronóstico «Mañana, si descansas igual»
    'Tomorrow, if you rest the same': 'Mañana, si descansas igual',
    'Still calibrating': 'Aún calibrando',
    'rising': 'subiendo',
    'falling': 'bajando',
    # FER-264 — Tendencia: comparar contra el periodo previo del mismo largo + excluir el día en curso
    '%@ vs last week': '%@ vs la semana pasada',
    '%@ vs last quarter': '%@ vs el trimestre pasado',
    '%@ vs the previous 6 months': '%@ vs el semestre pasado',
    '%@ vs last year': '%@ vs el año pasado',
    'Stable this week': 'Estable esta semana',
    'Stable this quarter': 'Estable este trimestre',
    'Stable these 6 months': 'Estable estos 6 meses',
    'Stable this year': 'Estable este año',
    'The line includes today, still in progress; the figures below use completed days only.': 'La línea incluye hoy, aún en curso; las cifras de abajo usan solo días completos.',
    # FER-256 — Detalle de Temperatura de la piel (SkinTempDetailScreen)
    "How far last night's skin temperature ran from your own recent baseline, in °C. We learn your normal over recent nights, so 0 is your usual and the number is the shift up or down. A single warm or cool night rarely means much: what's worth noticing is several nights in a row drifting the same way. It's a comfort signal, not a thermometer or a diagnosis.": "Qué tanto se alejó la temperatura de tu piel anoche de tu propia base reciente, en °C. Aprendemos tu normal de las últimas noches, así que 0 es lo de siempre y el número es cuánto subió o bajó. Una sola noche cálida o fría rara vez significa algo, lo que vale la pena notar son varias noches seguidas moviéndose hacia el mismo lado. Es una señal de confort, no un termómetro ni un diagnóstico.",
    'Right around your usual nighttime baseline.': 'Justo alrededor de tu base nocturna de siempre.',
    'A touch warmer than your baseline last night.': 'Una pizca más cálida que tu base anoche.',
    'A touch cooler than your baseline last night.': 'Una pizca más fría que tu base anoche.',
    'Nightly skin-temperature deviation from a personal rolling baseline. A comfort signal, not a thermometer or a diagnosis.': 'Desviación nocturna de la temperatura de piel respecto a una base móvil personal. Una señal de confort, no un termómetro ni un diagnóstico.',
    # FER-254 — Detalle de Métrica «Instrumento» para Steps
    '7-day average · %@ steps': 'Promedio de 7 días · %@ pasos',
    "Your step count for today. Steady activity, even a short walk, supports your heart, your mood and your recovery.": "Tu conteo de pasos de hoy. La actividad constante, aunque sea una caminata corta, apoya tu corazón, tu ánimo y tu recuperación.",
    'Where your steps are headed this month compared with last month.': 'Hacia dónde van tus pasos este mes comparado con el anterior.',
    'Gathering': 'Reuniendo',
    '%lld / 7 days': '%lld / 7 días',
    'Connect Apple Salud and walk a few days to see your daily average and your trend.': 'Conecta Apple Salud y camina unos días para ver tu promedio diario y tu tendencia.',
    'Paluch et al. 2022, Lancet Public Health.': 'Paluch et al. 2022, Lancet Public Health.',
    # FER-257 — Detalle de VO₂max (Cuerpo · MetricDetailScreen)
    "Above what's expected for your age.": 'Por encima de lo esperado para tu edad.',
    "Below what's expected for your age.": 'Por debajo de lo esperado para tu edad.',
    "In line with what's expected for your age.": 'En línea con lo esperado para tu edad.',
    'Expected for your age: ~%lld': 'Esperado a tu edad: ~%lld',
    'Measured today': 'Medido hoy',
    'Measured yesterday': 'Medido ayer',
    'Measured %lld days ago': 'Medido hace %lld días',
    'Measured readings': 'Lecturas medidas',
    'Measured values.': 'Valores medidos.',
    'Change': 'Cambio',
    'Good': 'Bueno',
    '· you': '· tú',
    "A higher VO₂max is associated with a lower risk of all-cause mortality. It's one of the best-evidenced predictors of long-term health.": 'Un VO₂max más alto se asocia con menor riesgo de mortalidad por todas las causas. Es uno de los predictores de salud a largo plazo mejor fundamentados.',
    'Mandsager 2018 (JAMA) · Kodama 2009': 'Mandsager 2018 (JAMA) · Kodama 2009',
    'No VO₂max yet': 'Aún no hay VO₂max',
    'ml/kg/min': 'ml/kg/min',
    "The most oxygen your body can use during hard exercise, per kilo of body weight. It's the single best measure of cardiorespiratory fitness, and one of the best-evidenced predictors of long-term health.": "El máximo de oxígeno que tu cuerpo puede usar en ejercicio intenso, por kilo de peso. Es la mejor medida de tu condición cardiorrespiratoria, y uno de los predictores de salud a largo plazo mejor fundamentados.",
    "Your Apple Watch estimates VO₂max from your heart rate and pace during brisk outdoor walks and runs with a good GPS signal, so it updates every so often rather than daily. We read where it sits among healthy adults of your age and sex (the FRIEND reference median), and translate that into a plain band. A higher VO₂max is associated with a lower risk of all-cause mortality: it's one of the best-evidenced markers of long-term health.": "Tu Apple Watch estima el VO₂max a partir de tu frecuencia cardiaca y tu ritmo en caminatas y carreras al aire libre con buena señal de GPS, así que se actualiza de vez en cuando, no a diario. Leemos dónde cae entre adultos sanos de tu edad y sexo (la mediana de referencia FRIEND) y lo traducimos en una banda sencilla. Un VO₂max más alto se asocia con menor riesgo de mortalidad por todas las causas, es uno de los marcadores de salud a largo plazo mejor fundamentados.",
    "Reference: Kaminsky et al., FRIEND Registry (Mayo Clin Proc 2015). Longevity association: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). A coarse population reference, not a clinical measurement: Cénit is not a medical device.": "Referencia: Kaminsky et al., Registro FRIEND (Mayo Clin Proc 2015). Asociación con longevidad: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). Es una referencia poblacional aproximada, no una medición clínica, Cénit no es un dispositivo médico.",
    # FER-238 — Detalle de Esfuerzo (StrainDetailScreen)
    "All-out day: about as much strain as you carry.": "Día a tope, casi todo el esfuerzo que aguantas.",
    "Day Strain is your cardiovascular load on a 0–21 scale. Each second your heart rate is recorded, it's placed in an intensity zone (1–5); higher zones weigh more, and the total is compressed logarithmically so 21 is a theoretical maximum: a full day at peak intensity. (Edwards 1993; Banister 1991)": 'El Esfuerzo del día es tu carga cardiovascular en una escala de 0 a 21. Cada segundo en que se registra tu frecuencia cardiaca se asigna a una zona de intensidad (1–5); las zonas altas pesan más, y el total se comprime logarítmicamente, así que 21 es un máximo teórico: un día entero a intensidad máxima. (Edwards 1993; Banister 1991)',
    'Each second of heart rate is mapped to one of five intensity zones; time in the higher zones counts for much more. The weighted total is compressed onto a 0–21 scale through a logarithmic curve, so the top of the scale represents a theoretical full day at peak intensity.': 'Cada segundo de frecuencia cardiaca se asigna a una de cinco zonas de intensidad; el tiempo en las zonas altas cuenta mucho más. El total ponderado se comprime a una escala de 0 a 21 con una curva logarítmica, así que el tope representa un día entero teórico a intensidad máxima.',
    "Hard effort today: solid work.": "Esfuerzo fuerte hoy, buen trabajo.",
    'Heart-rate-zone load (TRIMP), compressed logarithmically. (Edwards 1993; Banister 1991)': 'Carga por zonas de frecuencia cardiaca (TRIMP), comprimida logarítmicamente. (Edwards 1993; Banister 1991)',
    "Light load today: plenty left in the tank.": "Carga ligera hoy, te queda mucho en el tanque.",
    'Moderate effort today.': 'Esfuerzo moderado hoy.',
    "No strain from today yet: your recent history is below.": "Aún no hay esfuerzo de hoy, abajo está tu historial reciente.",
    'Zones': 'Zonas',
    # FER-235 — calendario táctil
    'no reading': 'sin lectura',
    'Tap a day to see its recovery.': 'Toca un día para ver su recuperación.',
    '%@ · no reading': '%@ · sin lectura',
    # FER-225 — Detalle de Recuperación
    "No reading from last night yet: your recent history is below.": "Aún no hay lectura de anoche, abajo está tu historial reciente.",
    "Recovery blends several signals from your nervous system, your HRV above all, plus resting heart rate, sleep and breathing, and compares them with your own baseline from recent weeks. It's an estimate of how ready your body is today, not a diagnosis. (Buchheit 2014)": "La recuperación combina varias señales de tu sistema nervioso, tu HRV sobre todo, más la frecuencia cardiaca en reposo, el sueño y la respiración, y las compara con tu propia base de las últimas semanas. Es una estimación de qué tan listo está tu cuerpo hoy, no un diagnóstico. (Buchheit 2014)",
    "Above your baseline: your body is ready for a strong day.": "Por encima de tu base, tu cuerpo está listo para un día fuerte.",
    "Recovering: train, but keep it controlled.": "Recuperándote, entrena, pero con cabeza.",
    "Low: prioritize rest today.": "Baja, hoy prioriza el descanso.",
    'above your base': 'por encima de tu base',
    'suppressed': 'suprimida',
    'running high': 'algo elevada',
    'elevated': 'elevada',
    'solid': 'sólido',
    'running warm': 'algo tibia',
    'slightly raised': 'ligeramente elevada',
    '%lld–%lld · %lld days': '%lld–%lld · %lld días',
    '+%lld% vs last month': '+%lld% vs el mes pasado',
    '−%lld% vs last month': '−%lld% vs el mes pasado',
    'Not enough days in this range to draw a trend.': 'No hay suficientes días en este rango para dibujar una tendencia.',
    '±%lld% week to week · %@': '±%lld% de una semana a otra · %@',
    'Calendar · 90 days': 'Calendario · 90 días',
    'Recent load': 'Carga reciente',
    '%lld / %lld nights': '%lld / %lld noches',
    # Detalle de Sueño — pasada de UI: etapas + métricas con tarjeta + copy (FER-227).
    "Weekly debt": "Deuda de la semana",
    "What you missed versus what your body needs. One good night won't clear it.": "Lo que te faltó dormir frente a lo que tu cuerpo necesita. No se salda con una sola noche buena.",
    # Detalle de Sueño — tendencia unificada con Hoy + gráfica de deuda (FER-249 v2).
    "behind this week": "de retraso esta semana",
    "your need": "tu necesidad",
    "%lld of the last %lld nights in this range": "%1$lld de las últimas %2$lld noches en este rango",
    "Hours above or below your sleep need, each of the last 7 nights": "Horas por encima o por debajo de tu necesidad de sueño, cada una de las últimas 7 noches",
    "slept %@": "dormiste %@",
    "What the stages mean": "Qué significan las etapas",
    "Shows what this means": "Muestra qué significa esto",
    "Sleep stages": "Etapas del sueño",
    "Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate: it gets about 2 of 3 right.": "Tu noche pasa por cuatro fases. El reloj las estima con tu movimiento y tu ritmo cardiaco, así que son aproximadas: acierta cerca de 2 de cada 3.",
    "Dreams and memory. It consolidates what you learned and processes emotion.": "Sueños y memoria. Consolida lo que aprendiste y procesa las emociones.",
    "Physical repair. Your body restores itself and releases growth hormone.": "Reparación física. El cuerpo se restaura y libera hormona de crecimiento.",
    "Most of the night. A transition in which your body winds down.": "La mayor parte de la noche. Una transición en la que tu cuerpo baja revoluciones.",
    "Brief awakenings. They're normal and don't mean a bad night.": "Microdespertares breves. Son normales y no significan una mala noche.",
    "Proportions, not minutes. A clinical measurement needs a sleep study.": "Proporciones, no minutos. Una medición clínica necesita un estudio de sueño.",
    "How much you slept versus what your body needs. At 100% you fully covered last night's need.": "Cuánto dormiste frente a lo que tu cuerpo necesita. Al 100% cubriste por completo lo que necesitabas anoche.",
    "Your need is your own rolling average of recent nights, never under 7.5 h.": "Tu necesidad es tu propio promedio de las últimas noches, nunca menos de 7.5 h.",
    "Of the time you spent in bed, how much you actually spent asleep. Above about 85% is considered healthy.": "Del tiempo que pasaste en cama, cuánto dormiste de verdad. Por encima del 85% se considera saludable.",
    "The share of your sleep spent in deep and REM: the stages that physically and mentally restore you. Around 40–50% is typical for a healthy adult.": "La parte de tu sueño en profundo y REM, las etapas que te restauran física y mentalmente. Cerca del 40–50% es lo típico en un adulto sano.",
    "How many times you briefly woke during the night. A few are completely normal: everyone surfaces between sleep cycles.": "Cuántas veces te despertaste brevemente durante la noche. Unas pocas son del todo normales: todos salimos a flote entre ciclos de sueño.",
    "Brief awakenings are normal and often not remembered. What matters is the trend, not a single night.": "Los microdespertares son normales y a menudo no se recuerdan. Lo que importa es la tendencia, no una sola noche.",
    "How long it took you to fall asleep after lights out. Ten to twenty minutes is a healthy range.": "Cuánto tardaste en quedarte dormido tras apagar la luz. De diez a veinte minutos es un rango saludable.",

    # SettingsView — band-log empty placeholder (FER-199).
    # Cuerpo landing — the «historia / entre-días» tab (FER-186).
    "Rest & load": "Descanso y carga",
    "Vitals": "Vitales",
    "Longevity": "Longevidad",
    "Ready to train": "Listo para entrenar",
    "Recovering": "Recuperándote",
    "Prioritize rest": "Prioriza el descanso",
    "Calibrating your baseline": "Calibrando tu base",
    "Physical age": "Edad física",
    "Vitality": "Vitalidad",
    "See all metrics": "Ver todas las métricas",
    "Connect Apple Health to fill steps and more.": "Conecta Apple Salud para llenar pasos y más.",

    # Fitness Age — «Edad física» row in Cuerpo + its detail sheet (FER-141).
    "Estimate": "Estimado",
    "years": "años",
    "%lld years younger than your %lld": "%lld años más joven que tus %lld",
    "%lld years above your %lld": "%lld años por encima de tus %lld",
    "Right at your %lld": "Justo en tus %lld",
    "%lld years younger than your age of %lld.": "%lld años más joven que tu edad de %lld.",
    "Right at your age of %lld.": "Justo en tu edad de %lld.",
    "An estimate with a ±%lld-year margin.": "Una estimación con un margen de ±%lld años.",
    "It's a comparison of your fitness, not your biological age or a medical diagnosis.": "Es una comparación de tu condición física, no tu edad biológica ni un diagnóstico médico.",
    "What moves it": "Qué la mueve",
    "The lower it is, the younger.": "Cuanto más baja, más joven.",
    "Recent activity": "Actividad reciente",
    "More active days also bring it down.": "Más días activos también la bajan.",
    "/ 7 days": "/ 7 días",
    "What we're using": "Qué estamos usando",
    "Age and sex": "Edad y sexo",
    "%lld, man": "%lld, hombre",
    "%lld, woman": "%lld, mujer",
    "%lld, non-binary": "%lld, no binario",
    "Based on the Nes/HUNT model (2011): it estimates your aerobic capacity from your resting heart rate and activity, and compares it with the average for your age.": "Basado en el modelo Nes/HUNT (2011): estima tu capacidad aeróbica a partir de tu FC en reposo y tu actividad, y la compara con el promedio de tu edad.",
    "What we need": "Qué necesitamos",
    # VO₂max de Apple Salud en el detalle de Edad física (FER-215).
    "Measured by your Apple Watch during exercise.": "Medido por tu Apple Watch durante el ejercicio.",
    "The average for your age is around %lld.": "El promedio para tu edad ronda %lld.",
    "Connect Apple Health to see your VO₂max.": "Conecta Apple Salud para ver tu VO₂max.",

    # WhyVerdictSheet — color name for the red/rundown level (FER-167).
    "red": "rojo",

    # MetricInfoSheet — light-theme redesign + full es-MX copy (FER-162).
    # Headlines.
    "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum: a full day at peak intensity.": "La carga sobre tu corazón a lo largo del día, en una escala de 0 a 21. Cada segundo que se registra tu frecuencia cardíaca cae en una zona (1 a 5); las zonas más altas pesan más. El total se comprime de forma logarítmica, así que 21 es un máximo teórico: un día entero a intensidad máxima.",
    "Your heart rate across the day, averaged in 5-minute buckets.": "Tu frecuencia cardíaca a lo largo del día, promediada en intervalos de 5 minutos.",
    # Notes.
    # Zone labels.
    "Moderate": "Moderado",
    "Hard": "Intenso",
    "Extreme": "Extremo",
    "Short": "Corto",
    "Adequate": "Suficiente",
    "Optimal": "Óptimo",
    "Extended": "Extenso",
    "Athlete": "Atleta",
    "Excellent": "Excelente",
    "Normal": "Normal",
    "Elevated": "Elevada",
    "Sedentary": "Sedentario",
    "Active": "Activo",
    "Very active": "Muy activo",
    # Section titles / wells / connect hint.
    "Last 14 days": "Últimos 14 días",
    "No data for the last 14 days.": "Sin datos de los últimos 14 días.",
    "This reading can come from Apple Health. Connect it from Today to see it here.": "Esta lectura puede venir de Apple Salud. Conéctala desde Hoy para verla aquí.",
    "%lld of %lld nights": "%lld de %lld noches",

    # HRV "how it's calculated" explainer sheet (FER-109).
    "HRV is personal. There are no universal good/bad thresholds: only your trend over time.": "La HRV es personal. No hay umbrales universales de bueno o malo, solo tu tendencia en el tiempo.",

    # Recovery "how it's calculated" explainer sheet (FER-108).
    "Your recovery sums up how ready your body is today, from 0 to 100. It blends several signals from your night, your HRV above all, and compares them with your own average from recent weeks, not anyone else's.": "Tu recuperación resume qué tan listo está tu cuerpo hoy, del 0 al 100. Combina varias señales de tu noche, sobre todo tu HRV, y las compara con tu propio promedio de las últimas semanas, no con el de nadie más.",
    "If a signal is missing on a given night, its weight is shared among the others.": "Si falta alguna señal esa noche, su peso se reparte entre las demás.",
    "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996).": "Un compuesto de z-scores con una curva logística. HRV vía RMSSD (Task Force, 1996).",
    "See the method": "Ver el método",
    "It's an estimate, not a diagnosis.": "Es una estimación, no un diagnóstico.",
    "Calibrating baseline": "Calibrando línea base",
    "Skin temp": "Temp. de piel",

    # Symbols / pure placeholders — identical in Spanish.
    "—": ", ",
    "·": "·",
    "· %@": "· %@",
    "/ %lld": "/ %lld",
    "%@": "%@",
    "%@ – %@": "%@ – %@",
    "%@ · %@": "%@ · %@",
    "%@ / %@": "%@ / %@",
    "%@ %@": "%@ %@",
    "%@ ↔ %@": "%@ ↔ %@",
    "%@, %@%@": "%@, %@%@",
    "%@%@": "%@%@",
    "%lld": "%lld",
    "%lld / %lld": "%lld / %lld",
    "•": "•",
    "✓": "✓",
    "r = %@": "r = %@",
    "v%@": "v%@",
    "Cénit": "Cénit",
    "Cénit %@": "Cénit %@",
    "p < 0.05": "p < 0.05",
    "n.s.": "n.s.",

    # FER-113 — reconciliación recuperación↔veredicto (bridge, sublabel, hoja "¿Por qué?").
    "Several signals are down at once. Treat today as recovery.": "Varias señales están abajo. Hoy toca recuperar.",
    "One of your signals is flagging. You can train, but keep it controlled.": "Una de tus señales está prendida. Puedes entrenar, pero con control.",
    "You woke up well recovered. What needs care today is your training load, not your body.": "Amaneciste muy recuperado. Lo que pide cuidado: hoy es tu carga, no tu cuerpo.",
    "Your recovery is high, but %@ is flagging — keep an eye on that today.": "Tu recuperación va alta, pero %@ trae una señal abajo, ojo con eso hoy.",
    "your training load": "tu carga",
    "your HRV": "tu HRV",
    "your resting heart rate": "tu frecuencia en reposo",
    "your skin temperature": "tu temperatura de piel",
    "your breathing": "tu respiración",
    "one of your signals": "una de tus señales",
    "several signals": "varias señales",
    "Verdict": "Veredicto",
    "from %@": "por %@",
    "Why %@?": "¿Por qué %@?",
    "Today your day is %@ — %@": "Hoy tu día es %@, %@",
    "Your signals today": "Tus señales hoy",
    "What each color means": "Qué significa cada color",
    "mint": "menta",
    "green": "verde",
    "amber": "ámbar",
    "rose": "rosa",
    "gray": "gris",
    "signals aligned, load supported": "señales alineadas y carga que aguanta",
    "nothing flagging": "nada está flaggeando",
    "one signal needs care": "una señal pide cuidado",
    "several signals down": "varias señales abajo",
    "TODAY": "HOY",

    # Units / short tokens.
    "bpm": "lpm",
    "BPM": "BPM",
    "REM": "REM",
    "OK": "OK",
    "HRV": "HRV",
    "Apple": "Apple",
    "Apple Health": "Apple Health",
    "App": "App",

    # Format strings.
    "%@ versus %@, r equals %@, %lld days": "%@ contra %@, r igual a %@, %lld días",
    "%@ wrist alerts": "%@ avisos en la muñeca",
    "%@, correlation %@, %lld days": "%@, correlación %@, %lld días",
    "%@, range %@ to %@": "%@, rango de %@ a %@",
    "%@: %@ last night%@": "%@: %@ anoche%@",
    "%lld app%@ on": "%lld app%@ en uso",
    # "%lld breaths": plural-managed in the String Catalog (one/other, FER-912) — no re-add (clobbers plural).
    "%lld days · %lld sleeps stored": "%lld días · %lld noches guardadas",
    # Plural-safe: Spanish can't inflect "capturado/s" off the bare "s" argument,
    # so the count leads and the (ignored) plural-suffix argument is dropped.
    "%lld frame%@ captured this session.": "Frames capturados en esta sesión: %lld.",
    # "vínculo" (m) so the shared strength/direction words ("moderado negativo") agree.
    "%lld overlapping days · %@ %@ correlation": "%lld días en común · vínculo %@ %@",
    "%lld–%lld%@ · step %lld": "%lld–%lld%@ · paso %lld",
    "Age, %lld years": "Edad, %lld años",
    "Battery %lld%%": "Batería %lld%%",
    "Copy %@ address": "Copiar dirección de %@",
    "Email %@": "Escribir a %@",
    "Error: %@": "Error: %@",
    "Estimated max heart rate · %lld bpm": "Frecuencia cardiaca máxima estimada · %lld lpm",
    # FER-435 — unidad de FC en español = «lpm» (consolida las cadenas que vivían solo en el catálogo)
    "Average today · min %@ · max %@ bpm · resting %lld": "Promedio de hoy · mín %@ · máx %@ lpm · reposo %lld",
    "Average today · min %@ · max %@ bpm": "Promedio de hoy · mín %@ · máx %@ lpm",
    "Peak %lld bpm · %@": "Pico %lld lpm · %@",
    "Zones as a percentage of your max heart rate (%lld bpm, Tanaka). The rest of the day you were resting or very light.": "Zonas como porcentaje de tu frecuencia cardiaca máxima (%lld lpm, Tanaka). El resto del día estuviste en reposo o muy ligero.",
    "Heart rate %lld beats per minute": "Frecuencia cardiaca de %lld latidos por minuto",
    "Mean %@": "Media %@",
    "No data for these metrics in %@. Widen the range or pick metrics you've logged.": "No hay datos para estas métricas en %@. Amplía el rango o elige métricas que hayas registrado.",
    "Not enough overlapping days between these metrics in %@. Widen the range.": "No hay suficientes días en común entre estas métricas en %@. Amplía el rango.",
    "Nothing in the catalog moves clearly with %@ over this window. Widen the range to surface relationships.": "Nada del catálogo se mueve claramente con %@ en esta ventana. Amplía el rango para revelar relaciones.",
    "Paste your %@ API key": "Pega tu clave de API de %@",
    "Pearson r · %@": "r de Pearson · %@",
    "Reading your %@…": "Leyendo tu %@…",
    "Remove %@": "Quitar %@",
    "Test %@ buzz": "Probar vibración de %@",
    "Version %@ is available": "La versión %@ está disponible",
    "What moves your %@": "Qué mueve tu %@",
    "load %@": "carga %@",

    # Onboarding / brand voice.
    "Every signal, one tap deep.": "Cada señal, a un toque de distancia.",
    "Slow threads": "Hilos lentos",
    "Overlay signals, draw conclusions.": "Superpón señales, saca conclusiones.",
    "WHAT TO EXPECT": "QUÉ ESPERAR",
    "Got it": "Entendido",
    "Back": "Atrás",
    "You're connected.": "Estás conectado.",

    # Sidebar / screen titles.
    "Today": "Hoy",
    "Control Center": "Centro de control",
    "Readiness": "Preparación",
    "Live": "En vivo",
    "Breathe": "Respira",
    "Intervals": "Intervalos",
    "Interval Timer": "Temporizador de intervalos",
    "Explore": "Explorar",
    "Compare": "Comparar",
    "Insights": "Hallazgos",
    "Intelligence": "Inteligencia",
    "Sleep": "Sueño",
    "Trends": "Tendencias",
    "Workouts": "Entrenamientos",
    "Health": "Salud",
    "Stress": "Estrés",
    "Data Sources": "Fuentes de datos",
    "Notifications": "Notificaciones",
    "Automations": "Automatizaciones",
    "Coach": "Coach",
    "Settings": "Configuración",
    "Support": "Soporte",
    "About": "Acerca de",
    # FER-398 · «Acerca de»: créditos + los tres enlaces que pide la tienda.
    "Credits & licenses": "Créditos y licencias",
    "Links": "Enlaces",
    "Privacy policy": "Política de privacidad",
    "Terms of use": "Términos de uso",
    # FER-398 · la letra chica de la puerta de términos ahora es un enlace a la web.
    # Sin em-dash en español (regla FER-879): «·».
    "terms.fine": "Los términos completos están en blandisc.github.io/cenit/terminos.html · esto no es asesoría legal.",
    "Profile": "Perfil",
    "Data": "Datos",
    "More": "Más",

    # Today / dashboard.
    "Recovery": "Recuperación",
    "Day Strain": "Esfuerzo del día",
    "Day strain": "Esfuerzo del día",
    "Resting HR": "FC en reposo",
    "Resting heart rate": "Frecuencia cardiaca en reposo",
    "Heart Rate": "Frecuencia cardíaca",
    "Heart rate variability": "Variabilidad de la frecuencia cardiaca",
    "Blood Oxygen": "Oxígeno en sangre",
    "Blood oxygen": "Oxígeno en sangre",
    "Respiratory": "Respiratoria",
    "Respiratory rate": "Frecuencia respiratoria",
    "Steps": "Pasos",
    "Calories": "Calorías",
    "Weight": "Peso",
    "Height": "Estatura",
    "Last Workouts": "Últimos entrenamientos",
    "Key Metrics": "Métricas clave",

    # Readiness.
    "Should you push today?": "¿Deberías exigirte hoy?",

    # Live / BLE.
    "Scan": "Escanear",
    "Scan & Connect": "Escanear y conectar",
    "Re-scan": "Volver a escanear",
    "Searching": "Buscando",
    "Connecting…": "Conectando…",
    "Connected": "Conectado",
    "Disconnect": "Desconectar",
    "Imported": "Importado",
    "Session": "Sesión",
    "Session live": "Sesión en vivo",
    "Markers": "Marcadores",
    "Recent moments": "Momentos recientes",
    "Moment marked.": "Momento marcado.",
    "Mark a Moment": "Marcar un momento",
    "Record a timestamped moment in Cénit.": "Registra un momento con marca de tiempo en Cénit.",
    "Log": "Registro",
    "Beats per minute": "Latidos por minuto",

    # Breathe.
    "Haptic-paced breathing · watch your HRV respond": "Respiración guiada por vibración · mira cómo responde tu HRV",
    "Buzz cues on": "Señales de vibración activadas",
    "Haptics on": "Háptica activada",
    "Visual only": "Solo visual",
    "Coherence estimate": "Estimación de coherencia",
    "Start session": "Empezar sesión",
    "Stop session": "Detener sesión",
    "SESSION DONE": "SESIÓN TERMINADA",

    # Intervals.
    "ROUND": "RONDA",
    "SECONDS": "SEGUNDOS",
    "Rest": "Descanso",
    "Running": "En curso",
    "Paused": "En pausa",
    "Pause": "Pausar",
    "Start": "Iniciar",
    "Restart": "Reiniciar",
    "Ready": "Listo",
    "Complete": "Completado",

    # Explore / Compare / Insights.
    "Metric": "Métrica",
    "Metrics": "Métricas",
    "Add metric": "Agregar métrica",
    "Max 4": "Máx 4",
    "Overlay": "Superposición",
    "Normalized": "Normalizado",
    "Nothing selected yet.": "Aún no hay nada seleccionado.",
    "Effect size": "Tamaño del efecto",
    "Outcome metric": "Métrica de resultado",
    "With": "Con",
    "Without": "Sin",
    "How They Move Together": "Cómo se mueven juntas",
    "What correlates": "Qué se correlaciona",
    "Pearson r": "r de Pearson",
    "Pearson r over the visible window · |r| ≥ 0.30, n ≥ 10": "r de Pearson en la ventana visible · |r| ≥ 0.30, n ≥ 10",
    "high": "alta",
    "mid": "media",
    "low": "baja",
    "Points": "Puntos",
    "Window": "Ventana",
    "Time range": "Rango de tiempo",
    "Days": "Días",
    "Date": "Fecha",
    "From": "Desde",
    "to": "a",
    "Average": "Promedio",
    "Avg": "Prom",
    "Min": "Mín",
    "Max": "Máx",
    "Latest": "Más reciente",
    "Latest reading": "Última lectura",
    "Trend": "Tendencia",

    # Sleep.
    "Last night": "Anoche",
    "Nights": "Noches",
    "Hours asleep": "Horas de sueño",
    "Hours vs Needed": "Horas vs. necesarias",
    "Asleep": "Dormido",
    "Asleep avg": "Promedio dormido",
    "Awake": "Despierto",
    "Deep": "Profundo",
    "Light": "Ligero",
    "Efficiency": "Eficiencia",
    "Consistency": "Consistencia",
    "Sleep Debt": "Deuda de sueño",
    "Sleep Performance": "Rendimiento de sueño",
    "Restorative": "Restaurador",
    "Loading your sleep history…": "Cargando tu historial de sueño…",
    "Provenance": "Procedencia",
    "Source Apple Health": "Fuente: Apple Health",

    # Workouts.
    "Activity": "Actividad",
    "Activity & Energy": "Actividad y energía",
    "By sport": "Por deporte",
    "Total Distance": "Distancia total",
    "Zone": "Zona",

    # Health.
    "Health Monitor": "Monitor de salud",
    "Heart & Vitals": "Corazón y vitales",
    "Cardiac": "Cardiaco",
    "Body": "Cuerpo",
    "Body Composition": "Composición corporal",
    "Body Fat": "Grasa corporal",
    "Body fat": "Grasa corporal",
    "Lean Mass": "Masa magra",
    "Lean body mass": "Masa corporal magra",
    "BMI": "IMC",
    "VO₂ Max": "VO₂ máx",
    "Active energy": "Energía activa",
    "Movement": "Movimiento",
    "No readings recorded.": "No hay lecturas registradas.",
    "No data": "Sin datos",
    "Peak": "Pico",
    "Depleted": "Agotado",
    "Low": "Bajo",

    # Stress.
    "Today's value is your recorded daily stress score (0–3).": "El valor de hoy es tu puntuación diaria de estrés registrada (0–3).",
    "Calm time": "Tiempo en calma",

    # Apple Health screen / imports.
    "Reading your Apple Health history…": "Leyendo tu historial de Apple Health…",
    "Reading your history…": "Leyendo tu historial…",
    "Choose export.zip…": "Elegir el .zip de exportación…",
    "Import…": "Importar…",
    "Importing…": "Importando…",
    "Export…": "Exportar…",
    "History": "Historial",
    "Category": "Categoría",
    "Backup & restore": "Respaldo y restauración",
    "Save…": "Guardar…",
    "Download": "Descargar",

    # Coach.
    "Provider": "Proveedor",
    "Model": "Modelo",
    "API key": "Clave de API",
    "Question": "Pregunta",
    "Send": "Enviar",
    "Working…": "Trabajando…",
    "Use": "Usar",

    # Automations.
    "When I double-tap": "Cuando doy doble toque",
    "Test buzz": "Vibración de prueba",
    "Test action": "Probar acción",
    "Wake at": "Despertar a las",
    "Off": "Apagado",
    "Configure": "Configurar",
    "Calendar": "Calendario",
    "State": "Estado",

    # Settings / profile.
    "Age": "Edad",
    "Sex": "Sexo",
    "Female": "Femenino",
    "Male": "Masculino",
    "Non-binary": "No binario",
    "Max HR": "FC máx",
    "Max heart rate": "Frecuencia cardiaca máxima",
    "Auto": "Auto",
    "What's new": "Novedades",
    "Check for updates": "Buscar actualizaciones",
    "Try again": "Intentar de nuevo",
    "Recompute": "Recalcular",
    "Reset": "Restablecer",
    "Clear": "Limpiar",
    "Close": "Cerrar",

    # Support / attribution.
    "Copy": "Copiar",
    "Email": "Correo",
    "This stands on community reverse-engineering. Huge thanks:": "Esto se apoya en la ingeniería inversa de la comunidad. Mil gracias:",
    "Built on": "Construido sobre",

    # Control Center (TodayView) — greeting, synthesis hero, tile captions, sources.
    "No Data": "Sin datos",
    "Steady": "Estable",
    "Primed": "A punto",
    "14-day trend": "Tendencia de 14 días",
    "of 21": "de 21",
    "%.0f%% eff": "%.0f%% efic.",
    "today": "hoy",
    "latest": "más reciente",
    "active": "activas",
    "%lld total": "%lld en total",
    "%lld days · %lld sleeps": "%lld días · %lld noches",
    "%lld days · %lld workouts": "%lld días · %lld entrenamientos",
    "Not connected": "No conectado",
    "5-minute average · since midnight": "Promedio de 5 min · desde medianoche",

    # Recovery ring state word (CenitDesign Palette.recoveryState).
    "DEPLETED": "AGOTADO",
    "LOW": "BAJO",
    "MODERATE": "MODERADO",
    "PRIMED": "A PUNTO",
    "PEAK": "PICO",

    # Readiness card (StrandAnalytics ReadinessEngine).
    "above your baseline — well recovered": "por arriba de tu línea base, bien recuperado",
    "in your normal range": "en tu rango normal",
    "suppressed — a sign of autonomic fatigue": "suprimida, señal de fatiga autonómica",
    "at or below baseline": "en o por debajo de la línea base",
    "running a little high": "un poco elevada",
    "elevated — overtraining or illness can do this": "elevada, el sobreentrenamiento o una enfermedad pueden causarlo",
    "up vs baseline — sometimes an early sign of getting sick": "elevada vs. línea base, a veces una señal temprana de enfermedad",
    "slightly raised vs baseline": "ligeramente elevada vs. línea base",
    "Training variety": "Variedad de entrenamiento",
    "low — similar strain every day raises strain/illness risk": "baja, un esfuerzo similar cada día aumenta el riesgo de sobrecarga o enfermedad",
    "Training load": "Carga de entrenamiento",
    "easing off (%@) — recent load below your usual": "bajando (%@): tu carga reciente va por debajo de tu normal",
    "in balance (%@) — recent load in line with your usual": "en equilibrio (%@): tu carga reciente va a la par de tu normal",
    "ramping up (%@) — recent load above your usual": "subiendo (%@): tu carga reciente va por encima de tu normal",
    "ramping fast (%@) — recent load well above your usual": "subiendo rápido (%@): tu carga reciente va muy por encima de tu normal",
    # Short load-band words for the verdict hero (LoadBand.shortLabel) + its VoiceOver label.
    "A few more nights of data and your readiness read will sharpen.": "Unas cuantas noches más de datos y tu lectura de preparación se afinará.",
    "Run down": "Desgastado",
    "Several signals are down at once. Treat today as recovery — easy movement, real sleep tonight.": "Varias señales están bajas a la vez. Toma hoy como recuperación, movimiento ligero y buen sueño esta noche.",
    "Strained": "Exigido",
    "One of your signals is flagging. You can train, but keep it controlled and bank the recovery.": "Una de tus señales está flaqueando. Puedes entrenar, pero mantenlo controlado y asegura la recuperación.",
    "Your signals are aligned and your load is supported. A harder session is well backed today.": "Tus señales están alineadas y tu carga es sostenible. Hoy una sesión más dura tiene buen respaldo.",
    "Balanced": "Equilibrado",
    "Nothing's flagging. Train to feel — your body's holding steady.": "Nada está flaqueando. Entrena según te sientas, tu cuerpo se mantiene estable.",

    # Illness early-warning banner (AppModel.evaluateIllness).
    "resting HR +%lld bpm": "FC en reposo +%lld lpm",
    "HRV −%lld%%": "HRV −%lld%%",
    "skin temp +%@°C": "temp. de piel +%@°C",
    "respiration up": "respiración elevada",

    # Apple Health import progress.
    # "%lld records": plural-managed in the String Catalog (one/other, FER-912) — no re-add (clobbers plural).

    # App Intents (Atajos / Shortcuts).

    # ── Plain-String conversions (String(localized:) pass) ──────────────────

    # Live — connection pill, stat tiles, pairing hint.
    "Disconnected": "Desconectada",
    "Battery": "Batería",

    # Settings — band status detail.

    # Metric catalog — titles & categories.
    "Average Heart Rate": "Frecuencia cardiaca promedio",
    "Max Heart Rate": "Frecuencia cardiaca máxima",
    "Heart Rate Variability": "Variabilidad de la frecuencia cardiaca",
    "Resting Heart Rate": "Frecuencia cardiaca en reposo",
    "Respiratory Rate": "Frecuencia respiratoria",
    "Skin Temperature": "Temperatura de la piel",
    "Time in Bed": "Tiempo en cama",
    "Asleep Time": "Tiempo dormido",
    "Sleep Consistency": "Consistencia de sueño",
    "Restorative Sleep": "Sueño reparador",
    "Sleep Efficiency": "Eficiencia de sueño",
    "Deep (SWS) Sleep": "Sueño profundo (SWS)",
    "REM Sleep": "Sueño REM",
    "Light Sleep": "Sueño ligero",
    "Sleep Need": "Sueño necesario",
    "HR Zones 1–3": "Zonas de FC 1–3",
    "HR Zones 4–5": "Zonas de FC 4–5",
    "HR Zones (All)": "Zonas de FC (todas)",
    "Strength Activity Time": "Tiempo de entrenamiento de fuerza",
    "Active Energy": "Energía activa",
    "Lean Body Mass": "Masa corporal magra",
    "Day Stress": "Estrés del día",
    "Heart": "Corazón",
    "Strain": "Esfuerzo",

    # Range pickers (Explore / Apple Health / Compare / Trends / Workouts).
    "W": "S",
    "M": "M",
    "3M": "3M",
    "6M": "6M",
    "1Y": "1A",
    "ALL": "TODO",
    "7D": "7D",
    "All": "Todo",
    "7 DAYS": "7 DÍAS",
    "30 DAYS": "30 DÍAS",
    "90 DAYS": "90 DÍAS",
    "180 DAYS": "180 DÍAS",
    "365 DAYS": "365 DÍAS",
    "ALL TIME": "TODO",
    "week": "semana",
    "month": "mes",
    "quarter": "trimestre",
    "6 months": "6 meses",
    "year": "año",
    "all time": "todo el historial",
    "all history": "todo el historial",
    "3 months": "3 meses",
    "30 days": "30 días",
    "1 year": "1 año",
    "the last 7 days": "los últimos 7 días",
    "last 7 days": "últimos 7 días",
    "last 30 days": "últimos 30 días",
    "last 90 days": "últimos 90 días",
    "last year": "último año",
    "All history": "Todo el historial",
    "Trailing %lld days": "Últimos %lld días",
    "reading": "lectura",
    "readings": "lecturas",
    "%lld %@ · %@": "%lld %@ · %@",
    "%lld readings · %@": "%lld lecturas · %@",
    # "%lld days": plural-managed in the String Catalog (one/other, FER-912) — no re-add (clobbers plural).
    "as of %@": "al %@",
    "no prior %@": "sin %@ anterior",

    # Compare / Insights — generated sentences and qualifier words.
    " No clear relationship: they move largely independently.": " Sin relación clara, se mueven de forma independiente.",
    "tends to fall": "tiende a bajar",
    "tends to rise": "tiende a subir",
    "negligible": "insignificante",
    "weak": "débil",
    "moderate": "moderado",
    "strong": "fuerte",
    "very strong": "muy fuerte",
    "positive": "positivo",
    "negative": "negativo",
    "flat": "neutro",
    "no": "nula",
    "a weak": "débil",
    "a moderate": "moderada",
    "a strong": "fuerte",
    "small": "pequeño",
    "large": "grande",
    "RHR": "FC reposo",
    "Sleep performance": "Rendimiento de sueño",

    # Behaviour insights (StrandAnalytics package — keys created manually).
    "higher": "mayor",
    "lower": "menor",
    "unchanged": "sin cambio",
    "no different": "sin diferencia",
    "On days you logged ‘%@’, %@ was %@ (avg %lld vs %lld, n=%lld vs %lld).": "Los días que registraste ‘%1$@’, %2$@ fue %3$@ (prom. %4$lld vs %5$lld, n=%6$lld vs %7$lld).",

    # Intelligence engine notes.
    "No on-device store yet.": "Aún no hay base de datos en el dispositivo.",

    # Breathe.
    "Relax 4-6": "Relajación 4-6",
    "Coherence 5.5": "Coherencia 5.5",
    "Box 4-4": "Cuadrada 4-4",
    "Breathe in…": "Inhala…",
    "Breathe out…": "Exhala…",
    "Building": "Construyendo",
    "Settling": "Asentándose",
    "Coherent": "Coherente",
    "Deep calm": "Calma profunda",

    # Intervals.
    "WORK": "TRABAJO",
    "REST": "DESCANSO",
    "DONE": "LISTO",

    # Band actions (Automations picker).
    "Nothing": "Nada",
    "Buzz back (confirm)": "Vibrar de vuelta (confirmar)",
    "Mark a moment": "Marcar un momento",
    "Run a Shortcut…": "Ejecutar un Atajo…",

    # Coach suggestion chips.

    # Stress bands + guidance.
    "LOW": "BAJO",
    "MEDIUM": "MEDIO",
    "HIGH": "ALTO",
    "Resting HR is elevated and HRV is below your baseline: both classic signs of high activation. Prioritise rest, hydration and an easy day.": "La FC en reposo está elevada y la HRV está por debajo de tu línea base, dos señales clásicas de alta activación. Prioriza el descanso, la hidratación y un día tranquilo.",
    "HRV has dropped well below your baseline, pointing to elevated stress or fatigue. Ease off and give your body time to recover.": "La HRV cayó muy por debajo de tu línea base, lo que apunta a estrés o fatiga elevados. Baja el ritmo y dale a tu cuerpo tiempo de recuperarse.",
    "Resting heart rate is running high versus your norm: your body is under load today. Keep effort light.": "La frecuencia cardiaca en reposo anda alta respecto a tu norma, tu cuerpo está bajo carga hoy. Mantén el esfuerzo ligero.",
    "Your autonomic markers are skewed toward stress today. Treat it as a recovery-focused day.": "Tus marcadores autonómicos se inclinan hacia el estrés hoy. Tómalo como un día enfocado en recuperarte.",
    "resting HR is a touch high": "la FC en reposo está un poco alta",
    "HRV is a little low": "la HRV está un poco baja",
    "You're sitting around your typical autonomic baseline: moderate stress, a normal, balanced day.": "Estás alrededor de tu línea base autonómica típica, estrés moderado, un día normal y equilibrado.",
    "Resting heart rate is low and HRV is up: your nervous system looks well-recovered and calm. A great day to push if you want to.": "La frecuencia cardiaca en reposo está baja y la HRV alta, tu sistema nervioso se ve recuperado y en calma. Un gran día para exigirte si quieres.",
    "HRV is above baseline, a sign of a relaxed, well-recovered nervous system. Stress is low.": "La HRV está por encima de tu línea base, señal de un sistema nervioso relajado y bien recuperado. El estrés es bajo.",
    "Resting heart rate and HRV are sitting at or below baseline: low physiological stress. You're in a calm, recovered state.": "La frecuencia cardiaca en reposo y la HRV están en tu línea base o por debajo, estrés fisiológico bajo. Estás en un estado tranquilo y recuperado.",

    # Health.
    "Idle": "Inactivo",
    "Zone %lld · %lld%%": "Zona %lld · %lld%%",
    "In range": "En rango",
    "Out of range": "Fuera de rango",

    # Widget keys deduped into the main catalog by the seed (the widget bundle
    # has its own copy in CenitWidgets/Localizable.xcstrings).
    "%": "%",
    "–": "–",
    "%@ bpm": "%@ lpm",
    "%@ bpm · %@": "%@ lpm · %@",
    "%lld%%": "%lld%%",
    "Recovery %@%%": "Recuperación %@%%",

    # --- upstream/iOS v1.66→v1.80 feature strings (units toggle, manual workouts,
    #     journal, terms gate, VitalBands, calibration, sync status, HR zones) ---
    "Calibrating": "Calibrando",
    "%lld of %lld nights": "%lld de %lld noches",

    # ── Night-zero calibration card + live beat-to-beat monitor (FER-61 revival + live capture) ──
    "No reading for today yet": "Aún no hay lectura de hoy",
    "See it beat by beat": "Míralo latido a latido",
    "No reading": "Sin lectura",
    "Waiting for beats…": "Esperando latidos…",
    "Capturing live": "Capturando en vivo",
    "Heart rate": "Frecuencia cardiaca",
    "Variability (R-R)": "Variabilidad (R-R)",
    "Completes on sync": "Se completa al sincronizar",
    "Blood oxygen (SpO₂)": "Oxígeno en sangre (SpO₂)",
    "Skin temperature": "Temperatura de piel",
    "Respiration": "Respiración",
    "synced %@": "sincronizado %@",
    "not yet": "aún no",
    "last reading %@": "última lectura %@",
    "Verify my data": "Verificar mis datos",
    "Last synced %@": "Última sincronización %@",
    "live": "en vivo",
    "Done": "Listo",
    "History synced %@": "Historial sincronizado %@",
    "Not synced yet": "Aún no sincronizado",
    "Battery %lld%% · Charging": "Batería %lld%% · Cargando",
    "Reconnect help: %@": "Ayuda de reconexión: %@",
    # VitalBands (personal baselines)
    # HR zones
    "HR Zones": "Zonas de FC",
    # Manual workout tracking
    "Start workout": "Iniciar entrenamiento",
    "Save workout": "Guardar entrenamiento",
    "Add a workout": "Agrega un entrenamiento",
    "Add workout": "Agregar entrenamiento",
    "Add Workout": "Agregar entrenamiento",
    "Log a session you tracked elsewhere.": "Registra una sesión que mediste en otro lado.",
    "Adjust this session's details.": "Ajusta los detalles de esta sesión.",
    "Edit Workout": "Editar entrenamiento",
    "Edit details…": "Editar detalles…",
    "Edit…": "Editar…",
    "Re-label as": "Reetiquetar como",
    "Duplicate as manual…": "Duplicar como manual…",
    "Dismiss (not a workout)": "Descartar (no es un entrenamiento)",
    "Export CSV…": "Exportar CSV…",
    "Sport": "Deporte",
    "e.g. Running": "p. ej. Correr",
    "Start date and time": "Fecha y hora de inicio",
    "Duration in minutes": "Duración en minutos",
    "Average heart rate in beats per minute, optional": "Frecuencia cardiaca promedio en latidos por minuto, opcional",
    "Calories in kilocalories, optional": "Calorías en kilocalorías, opcional",
    # Journal logging (Insights)
    "Journal": "Diario",
    # Units toggle (Imperial / Metric)
    "Units": "Unidades",
    "Measurement system": "Sistema de medición",
    "Imperial": "Imperial",
    "Temperature": "Temperatura",
    "Temperature unit": "Unidad de temperatura",
    "Weight in pounds": "Peso en libras",
    "Weight, %lld pounds": "Peso, %lld libras",
    "Height in inches": "Estatura en pulgadas",
    "Height, %lld feet %lld inches": "Estatura, %lld pies %lld pulgadas",
    "%lld′ %lld″": "%lld′ %lld″",
    "lb": "lb",
    "°C": "°C",
    "°F": "°F",
    # First-run terms gate
    "Before you use Cénit": "Antes de usar Cénit",
    "Please read and accept the points below.": "Por favor lee y acepta los puntos de abajo.",
    "I have read and accept these terms, and I'm using Cénit with my own device and my own data, at my own risk.": "He leído y acepto estos términos, y uso Cénit con mi propio dispositivo y mis propios datos, bajo mi propio riesgo.",
    "Accept & Continue": "Aceptar y continuar",
    # Firmware wake-up alarm note
    # Updates / CSV import notice
    # Short common actions / answers
    "Add": "Agregar",
    "Save": "Guardar",
    "Cancel": "Cancelar",
    "Delete": "Eliminar",
    "Match": "Coincidir",
    "Yes": "Sí",
    "No": "No",
    "Yesterday": "Ayer",

    # Today redesign — verdict-first iOS hero, honesty line, dense metrics, empty/first-launch state.
    "No reading yet": "Aún no hay lectura",
    "Low conf": "Conf. baja",
    "Since midnight": "Desde medianoche",
    "No readings yet": "Aún no hay lecturas",
    "Synced %@": "Sincronizado %@",
    "14-day": "14 días",
    "Live heart rate": "Frecuencia cardiaca en vivo",
    "Heart rate": "Frecuencia cardiaca",
    # ReadinessEngine (StrandAnalytics package — key created here, no .stringsdata extraction).
    "Based on a short night — confidence low.": "Basado en una noche corta, confianza baja.",

    # FER-74 — automatic iCloud Drive backup + one-tap restore (iOS, #if-gated branch).
    "Automatic iCloud backup": "Respaldo automático en iCloud",
    "Backing up to %@": "Respaldando en %@",
    "Back up now": "Respaldar ahora",
    "Restore…": "Restaurar…",
    "Turn off automatic backup": "Desactivar respaldo automático",
    "Choose iCloud Drive folder…": "Elegir carpeta de iCloud Drive…",
    "No backup yet.": "Aún no hay respaldo.",
    "Last backup %@": "Último respaldo %@",
    "Couldn't remember that folder. Try a folder in iCloud Drive.": "No se pudo recordar esa carpeta. Prueba con una carpeta en iCloud Drive.",
    "Lost access to the backup folder — choose it again.": "Se perdió el acceso a la carpeta de respaldo: elígela de nuevo.",
    "Couldn't snapshot the database just now — will retry.": "No se pudo copiar la base en este momento: se reintentará.",
    "Couldn't locate the Cénit database.": "No se pudo encontrar la base de datos de Cénit.",
    "No database to back up yet.": "Aún no hay base de datos que respaldar.",
    "Backup couldn't be saved: %@": "No se pudo guardar el respaldo: %@",
    "Restore from backup…": "Restaurar desde un respaldo…",
    "Not now": "Ahora no",
    "Restore": "Restaurar",
    "Your data has been restored. Reopen Cénit for it to take effect.": "Tus datos se restauraron. Vuelve a abrir Cénit para que surta efecto.",
    # FER-83 — Data Sources band-sync diagnostic (band range + per-sensor receipt + verdict).
    "Sync diagnostic": "Diagnóstico de sincronización",
    # "%lld pieces": plural-managed in the String Catalog (one/other, FER-912) — no re-add (clobbers plural).
    "Received this sync": "Recibido en esta sincronización",
    "R-R": "R-R",
    "Data arrives but doesn’t decode: please report.": "Llegan datos pero no se decodifican, repórtalo.",
    "Receiving and storing everything.": "Recibiendo y guardando todo.",

    # FER-180 — «Métricas de hoy»: rejilla de tiles intradía + variante stress de MetricInfoSheet.
    "vs yesterday": "vs ayer",
    "Medium": "Medio",
    "High": "Alto",
    "Your autonomic load today, from 0 to 3. We estimate it by comparing today's resting heart rate and HRV with your own 30-day baseline: a higher-than-usual resting HR and a lower-than-usual HRV both push the number up: classic signs your body is activated.": "Tu carga autonómica de hoy, del 0 al 3. La estimamos comparando tu frecuencia cardíaca en reposo y tu HRV con tu propia línea base de 30 días: una FC en reposo más alta de lo normal y una HRV más baja empujan el número hacia arriba, señales clásicas de que tu cuerpo está activado.",
    "Derived from your overnight resting heart rate and HRV: a transparent proxy for autonomic load, not a clinical stress measure.": "Se deriva de tu frecuencia cardíaca en reposo y tu HRV nocturnas, un proxy transparente de la carga autonómica, no una medida clínica de estrés.",
    "We take today's resting heart rate and HRV and express each as how far it sits from your 30-day average (a z-score). A resting HR above your norm and an HRV below it both add to the load; the two are summed and squashed onto a 0–3 scale where 0 is calm, 1.5 is your baseline, and 3 is highly activated.": "Tomamos tu frecuencia cardíaca en reposo y tu HRV de hoy y expresamos cada una como qué tan lejos está de tu promedio de 30 días (un z-score). Una FC en reposo por arriba de tu norma y una HRV por debajo suman a la carga; las dos se combinan y se ajustan a una escala de 0 a 3, donde 0 es calma, 1.5 es tu línea base y 3 es muy activado.",
    "Combined resting-HR / HRV z-score through a logistic curve; HRV via RMSSD (Task Force, 1996).": "Z-score combinado de FC en reposo y HRV a través de una curva logística; HRV vía RMSSD (Task Force, 1996).",

    # FER-145 — Longevidad: «Edad corporal» (Vitality + Body Age) y su detalle.
    "Body age": "Edad corporal",
    "years": "años",
    "yrs": "años",
    "you": "tú",
    "The same measure, 0–100:": "La misma medida, 0–100:",
    "· 50 = typical": "· 50 = típico",
    "← rejuvenates you": "← te rejuvenece",
    "ages you →": "te envejece →",
    "This isn't your Physical age": "No es tu Edad física",
    "Physical age measures only the cardiorespiratory side. This one also weighs sleep, regularity, HRV and steps: so the two can differ.": "La Edad física mide solo el lado cardiorrespiratorio. Esta también pesa sueño, regularidad, HRV y pasos, por eso pueden no coincidir.",
    "A wellness comparison, not a biological age or a clinical diagnosis. HRV is estimated from nighttime PPG; the reference norm is conservative.": "Una comparación de bienestar, no una edad biológica ni un diagnóstico clínico. La HRV se estima desde PPG nocturno; la norma de referencia es conservadora.",
    "What it's built from": "De qué se arma",
    "Nighttime resting HR": "FC en reposo nocturna",
    "Sleep regularity": "Regularidad de sueño",
    "Regularity": "Regularidad",
    "VO₂max": "VO₂max",
    "ready": "listo",
    "rejuvenates you by %@ years": "te rejuvenece %@ años",
    "ages you by %@ years": "te envejece %@ años",
    "neutral": "neutro",
    "Body age %lld, %lld years younger than your age %lld; estimated range %lld to %lld": "Edad corporal %lld, %lld años más joven que tu edad %lld; rango estimado %lld a %lld",
    "Body age %lld, %lld years older than your age %lld; estimated range %lld to %lld": "Edad corporal %lld, %lld años mayor que tu edad %lld; rango estimado %lld a %lld",
    "Body age %lld, at your age %lld; estimated range %lld to %lld": "Edad corporal %lld, en tu edad %lld; rango estimado %lld a %lld",

    # Detalle de Sueño — pantalla «Instrumento» que reemplaza el SleepView oscuro (FER-212).
    "Weekend shift": "Desfase de fin de semana",
    "+%@ later": "+%@ más tarde",
    "very regular": "muy regular",
    "regular": "regular",
    "variable": "variable",
    "Last night vs your typical": "Anoche vs lo típico",
    "Duration trend": "Tendencia de duración",
    "Not enough nights yet to draw a trend.": "Aún no hay suficientes noches para una tendencia.",
    "Tonight's metrics": "Métricas de la noche",
    "Performance": "Rendimiento",
    "vs your need": "vs lo necesario",
    "−%@ vs your need": "−%@ vs lo necesario",
    "vs time in bed": "vs tiempo en cama",
    "Restorative": "Restaurador",
    "Deep + REM": "Profundo + REM",
    "Latency": "Latencia",
    "10–20 healthy": "10–20 sano",
    "rpm": "rpm",
    "Awakenings": "Despertares",
    "times": "veces",
    # FER-310 — aviso de siesta excluida de la regularidad del horario
    "Windred et al., Sleep 2024 (regularity); Miller et al., J Sports Sci 2020 (wrist staging vs PSG); Hirshkowitz et al., 2015 (sleep need).": "Windred et al., Sleep 2024 (regularidad); Miller et al., J Sports Sci 2020 (etapas en muñeca vs PSG); Hirshkowitz et al., 2015 (necesidad de sueño).",
    "Source · Apple Health": "Fuente · Apple Salud",
    "Loading your sleep history…": "Cargando tu historial de sueño…",
    "%@ – %@ · %lld%% efficiency": "%@ – %@ · %lld%% de eficiencia",
    "%@, %lld%% last night": "%@, %lld%% anoche",
    ", typical %lld%%": ", típico %lld%%",
    "+%lld pts": "+%lld pts",
    "−%lld pts": "−%lld pts",
    "−%@": "−%@",
    "Sleep stages: deep %lld percent, light %lld percent, REM %lld percent, awake %lld percent": "Etapas de sueño: profundo %lld por ciento, ligero %lld por ciento, REM %lld por ciento, despierto %lld por ciento",
    # FER-241 — Detalle de Estrés (Cuerpo)
    "/ 3": "/ 3",
    "Normal range": "Rango normal",
    "· today": "· hoy",
    "▲ +%lld": "▲ +%lld",
    "▼ −%lld": "▼ −%lld",
    "at base": "en base",
    "below your base": "por debajo de tu base",
    "at your base": "en tu base",
    "Today's value is your recorded daily stress score (0–3). The trend, bands and markers are derived the same way.": "El valor de hoy es tu puntaje de estrés diario registrado (0–3). La tendencia, las bandas y los marcadores se derivan de la misma forma.",
    "Combined resting-HR / HRV z-score through a logistic curve. HRV via RMSSD (Task Force, 1996). An estimate, not a diagnosis.": "Z-score combinado de frecuencia en reposo / HRV a través de una curva logística. HRV vía RMSSD (Task Force, 1996). Una estimación, no un diagnóstico.",
    # FER-252 — Detalle de Oxígeno en sangre (SpO₂, Cuerpo)
    "Nightly values · the shaded band is the healthy range.": "Valores por noche · la banda sombreada es el rango sano.",
    "Nightly readings": "Lecturas por noche",
    "Nights below %@%@": "Noches por debajo de %@%@",
    "of the last %lld nights": "de las últimas %lld noches",
    "Wrist optical sensors are less accurate than medical pulse oximeters: read this as a trend, not a clinical measurement. Cénit is not a medical device.": "Los sensores ópticos de muñeca son menos precisos que un oxímetro médico, léelo como tendencia, no como una medición clínica. Cénit no es un dispositivo médico.",
    # FER-496 — Importar un programa de entrenamiento generado por un LLM (pantalla
    # WorkoutImportView + fila «Import plan» del hub). Cadenas compartidas con Dieta
    # (Copy prompt, Copied, Upload .json file, Continue, Paste your plan, «Bring back
    # the file…», Done, Change, los errores notJSON/idioma) ya están traducidas y se omiten.
    "Import plan": "Importar plan",
    "Bring your plan from your AI": "Trae tu plan desde tu IA",
    "Copy the prompt and paste it into your trusted AI, along with your plan (text, photo or PDF).": "Copia el prompt y pégalo en tu IA de confianza, junto con tu plan (texto, foto o PDF).",
    "Your routines are created on your iPhone. Cénit never connects: you run the AI step yourself.": "Tus rutinas se crean en tu iPhone. Cénit nunca se conecta, el paso de la IA lo haces tú.",
    "%lld exercises to set up": "%lld ejercicios por ubicar",
    "These aren't in your library. Match each one to an exercise you have, or create it.": "Estos no están en tu biblioteca. Empareja cada uno con un ejercicio que tengas, o créalo.",
    "Matched automatically · %@": "Emparejado automático · %@",
    "Matched · %@": "Emparejado · %@",
    "Create new": "Crear nuevo",
    "Resolve %lld more to continue": "Resuelve %lld más para continuar",
    "Your program": "Tu programa",
    "%lld routines · %lld exercises": "%lld rutinas · %lld ejercicios",
    "Create %lld routines": "Crear %lld rutinas",
    "Created %lld routines": "Creaste %lld rutinas",
    "They're in «My routines», ready to train.": "Están en «Mis rutinas», listas para entrenar.",
    "bodyweight": "peso corporal",
    "That file isn't a Cénit workout plan. Make sure you used the prompt above.": "Ese archivo no es un plan de entrenamiento de Cénit. Asegúrate de haber usado el prompt de arriba.",
    "The plan's unit isn't supported: it must be kg or lb.": "La unidad del plan no es compatible, debe ser kg o lb.",
    "One of the exercises has an unsupported type. Check the file and try again.": "Uno de los ejercicios tiene un tipo no compatible. Revisa el archivo e intenta de nuevo.",
    "That plan has no routines. Check the file and try again.": "Ese plan no tiene rutinas. Revisa el archivo e intenta de nuevo.",
    "One of the routines has no exercises. Check the file and try again.": "Una de las rutinas no tiene ejercicios. Revisa el archivo e intenta de nuevo.",
    "One of the exercises has no name. Check the file and try again.": "Uno de los ejercicios no tiene nombre. Revisa el archivo e intenta de nuevo.",
    # FER-643 — Body Age: chip «estimación parcial» + caveat cuando faltan HRV/FC en reposo (solo-Apple).
    "Partial estimate": "Estimación parcial",
    "Partial estimate. ": "Estimación parcial. ",
    "Worked out without HRV or resting heart rate: the two heaviest signals. The number still holds, with less precision.": "Calculada sin HRV ni FC en reposo, las dos señales de mayor peso. El número sigue valiendo, con menos precisión.",
    "Worked out without HRV: one of the heaviest signals. The number still holds, with less precision.": "Calculada sin HRV, una de las señales de mayor peso. El número sigue valiendo, con menos precisión.",
    "Worked out without resting heart rate: one of the heaviest signals. The number still holds, with less precision.": "Calculada sin FC en reposo, una de las señales de mayor peso. El número sigue valiendo, con menos precisión.",
    # FER-702 — «Tu HRV por frecuencia»: desglose espectral (LF/HF/total) en el Detalle de HRV.
    "Your HRV by frequency": "Tu HRV por frecuencia",
    "Respiratory": "Respiratoria",
    "your calm signal, tied to your breathing": "tu señal de calma, ligada a la respiración",
    "Slow": "Lenta",
    "slow waves; a mix of signals": "ondas lentas; mezcla de varias señales",
    "Total variation": "Variación total",
    "everything together, the “volume” of your HRV": "todo junto, el «volumen» de tu HRV",
    "Last night's reading was short, so it only covers the respiratory part: not the slow waves.": "Anoche la lectura fue corta, así que solo alcanza para la parte respiratoria, no para las ondas lentas.",
    "Still learning your normal range. Once there are enough nights, I'll tell you whether a value is high or low for you.": "Todavía estoy aprendiendo tu rango normal. Cuando haya suficientes noches, te diré si un valor está alto o bajo para ti.",
    "Computed from last night's heartbeats (Lomb-Scargle). These are descriptive band powers to compare against yourself: not a diagnosis or a “stress balance.”": "Calculado de los latidos de anoche (Lomb-Scargle). Son potencias descriptivas para compararte contigo mismo, no un diagnóstico ni un «balance de estrés».",
    "higher than your normal": "más alta de lo normal",
    "within your normal": "dentro de tu normal",
    "lower than your normal": "más baja de lo normal",
    # Fase 1 — migración Detalle de vitales al esqueleto Final (Temp. de piel).
    "Nightly thermal stability": "Estabilidad térmica nocturna",
    "Tends to rise with alcohol, fever, and ambient heat.": "Suele subir con alcohol, fiebre y calor ambiental.",
    # Fase 2 — migración Actividad/Longevidad al esqueleto Final.
    "Nes/HUNT model (2011)": "Modelo Nes/HUNT (2011)",
    "This period": "Este periodo",
    "Where you fall": "Dónde caes",
    "Your Apple Watch's estimate of your aerobic fitness: how well your body uses oxygen. Higher usually means better cardio shape; it's an estimate, not a lab test.": "La estimación que hace tu Apple Watch de tu condición aeróbica: qué tan bien usa tu cuerpo el oxígeno. Más alto suele significar mejor forma cardiovascular; es una estimación, no una prueba de laboratorio.",
    # Fase 4 — landing de Tendencias (decisiones del dueño).
    "Today's values · last month's trends": "Valores de hoy · tendencias del último mes",
    "intraday, no daily series": "intradía, sin serie diaria",
    "band": "banda",
    "Apple Health": "Apple Salud",
    "computed": "calculado",
    "%lld this week": "%lld esta semana",
    "%d this week": "%d esta semana",
    "Kcal": "Kcal",
    "Your sports": "Tus deportes",
    "points": "puntos",
    "building": "calibrando",
    "return to base": "regreso a tu base",
    "%d sessions": "%d sesiones",
    "Back to your base in ~1 day · %d sessions": "Vuelve a tu base en ~1 día · %d sesiones",
    "Back to your base in ~%d days · %d sessions": "Vuelve a tu base en ~%d días · %d sesiones",
    # FER-666 «Ritmo» — pantalla experimental de regularidad latido-a-latido (no clínica).
    "Looked steady.": "Se vio estable.",
    "A few extra or skipped beats showed up.": "Se vieron algunos latidos extra o salteados.",
    "Varied more than usual.": "Varió más de lo usual.",
    "Couldn't read it clearly.": "No se pudo leer con claridad.",
    "Experimental · Not an ECG or a diagnosis · Doesn't detect disease.": "Experimental · No es un ECG ni un diagnóstico · No detecta enfermedades.",
    "EXPERIMENTAL": "EXPERIMENTAL",
    "A glimpse of your rhythm": "Un vistazo a tu ritmo",
    "While you sleep, Cénit looks at how evenly your heart beats, beat to beat, and draws it for you.": "Mientras duermes, Cénit mira qué tan parejo late tu corazón, latido a latido, y te lo dibuja.",
    "It's not an ECG.": "No es un ECG.",
    "It's not a diagnosis.": "No es un diagnóstico.",
    "It doesn't detect disease.": "No detecta enfermedades.",
    "RHYTHM · LAST NIGHT": "RITMO · ANOCHE",
    "tap the cloud for the details": "toca la nube para ver los detalles",
    "%lld beats · solid read": "%lld latidos · lectura sólida",
    "%lld beats · forming read": "%lld latidos · lectura en formación",
    "%lld beats · calibrating": "%lld latidos · calibrando",
    "%lld of %lld readable windows looked steady.": "%lld de %lld ventanas legibles se vieron estables.",
    "%lld of %lld readable windows showed extra or skipped beats.": "%lld de %lld ventanas legibles mostraron latidos extra o salteados.",
    "%lld of %lld readable windows varied more than usual.": "%lld de %lld ventanas legibles variaron más de lo usual.",
    "No window last night could be read clearly.": "Ninguna ventana de anoche se pudo leer con claridad.",
    "Still calibrating.": "Aún calibrando.",
    "I'm still learning your rhythm. A few more nights and the read sharpens.": "Aún estoy aprendiendo tu ritmo. Unas cuantas noches más y la lectura se afina.",
    "Couldn't read it clearly last night.": "No se pudo leer con claridad anoche.",
    "There was too much movement or too little signal at rest. It's normal, try again tomorrow.": "Hubo mucho movimiento o poca señal en reposo. Es normal, vuelve a intentar mañana.",
    "No reading from last night.": "Sin lectura de anoche.",
    "Cloud shape (SD1:SD2)": "Forma de la nube (SD1:SD2)",
    "how round vs. elongated": "qué tan redonda vs. alargada",
    "Short width (SD1)": "Ancho corto (SD1)",
    "variation from one beat to the next": "variación de un latido al siguiente",
    "Length (SD2)": "Largo (SD2)",
    "variation across the night": "variación a lo largo de la noche",
    "Relative variation": "Variación relativa",
    "against your average beat": "respecto a tu latido promedio",
    "Direction changes": "Cambios de dirección",
    "how jagged the rhythm was": "qué tan «picudo» fue el ritmo",
    "Extra or skipped beats": "Latidos extra o salteados",
    "fraction of the total": "fracción del total",
    "Your rhythm, beat to beat": "Tu ritmo, latido a latido",
    # FER-719 — mapa muscular con decaimiento (1n) + «Volumen por músculo» (3d)
    "Today calls for rest.\nRecover first.": "Hoy toca descanso.\nRecupera primero.",
    "All fresh.\nTrain what you like.": "Todo fresco.\nEntrena lo que quieras.",
    "Everything still carries load.\nGive it a day or go light.": "Todo aún carga.\nDale un día o entrena ligero.",
    "Fresh: ": "Fresco: ",
    "The rest can wait.": "Lo demás puede esperar.",
    " still carries load.": " aún carga.",
    "Most loaded · 7 days": "Más cargados · 7 días",
    "%@ sets": "%@ series",
    "Each set loads the muscles it works and fades by half every 2 days · ": "Cada serie carga los músculos que trabaja y decae a la mitad cada 2 días · ",
    "See the method ›": "Ver el método ›",
    "Volume per muscle": "Volumen por músculo",
    "30 d": "30 d",
    "90 d": "90 d",
    "6 m": "6 m",
    "1 y": "1 a",
    "below the band": "bajo la banda",
    "within the band": "dentro de la banda",
    "above the band": "sobre la banda",
    "Every muscle you train is inside or above the band.": "Todos los músculos que entrenas están dentro o encima de la banda.",
    " below the band · they could take 2–3 more sets a week.": " bajo la banda · podrían absorber 2–3 series más por semana.",
    "No sets in this range": "Sin series en este rango",
    "Log your workouts and you'll see each muscle's weekly volume against the band.": "Registra tus entrenamientos y verás el volumen semanal de cada músculo contra la banda.",
    "%@ sets per week": "%@ series por semana",
    # FER-744 — deuda i18n del rediseño de «Hoy» (F1): re-key de TodayView.swift
    "We're downloading your night. As soon as the sync finishes, we compute your day's verdict and it shows here.": 'Estamos descargando tu noche. En cuanto termine la sincronización, calculamos tu veredicto del día y aparece aquí.',
    'Sync': 'Sincronizar',
    'Opens the beat-by-beat monitor': 'Abre el monitor latido a latido',
    "Today's recovery: %lld": 'Recuperación de hoy: %lld',
    'Not enough context for a verdict': 'Sin contexto para un veredicto',
    '+%lld vs your average': '+%lld vs tu promedio',
    '−%lld vs your average': '−%lld vs tu promedio',
    'Downloading': 'Descargando',
    'your night is on its way': 'tu noche viene en camino',
    'arrives with the morning sync': 'llega con la sincronización de la mañana',
    'Your verdict arrives with the first morning sync, once you sync the night.': 'Tu veredicto llega con la primera sincronización de la mañana, cuando sincronices la noche.',
    'See your metrics for today': 'Ver tus métricas de hoy',
    "Opens today's metrics page": 'Abre la página de métricas de hoy',
    'Opens why the verdict reads this way': 'Abre por qué el veredicto se lee así',
    'See pattern': 'Ver patrón',
    'Opens this pattern in Patrones': 'Abre este patrón en Patrones',
    'Log check-in': 'Registra check-in',
    'See experiment': 'Ver experimento',
    "Opens your experiment in Patrones to log today's check-in": 'Abre tu experimento en Patrones para registrar el check-in de hoy',
    'Opens your experiment in Patrones': 'Abre tu experimento en Patrones',
    "Today's connection": 'La conexión de hoy',
    'Today in your plan': 'Hoy en tu plan',
    'Your workout': 'Tu entrenamiento',
    "Opens Train and starts today's session": 'Abre Entrenar y arranca la sesión de hoy',
    'your split has no routine today': 'tu split no asigna rutina hoy',
    'day': 'día',
    'days': 'días',
    'streak %lld %@': 'racha %lld %@',
    'Streak of %lld %@ in your plan': 'Racha de %lld %@ en tu plan',
    'Now': 'Ahora',
    'Waiting': 'En espera',
    "Opens today's signals detail": 'Abre el detalle de tus señales de hoy',
    'HRV estimated from Apple Health': 'HRV estimada de Apple Salud',
    'Why %lld': 'Por qué %lld',
    'Length is weight': 'El largo es el peso',
    'Why %lld: the sum of your five signals': 'Por qué %lld: la suma de tus cinco señales',
    'Recovery\nestimated': 'Recuperación\nestimada',
    'Recovery\ntoday': 'Recuperación\nde hoy',
    'Your baseline\nis settling': 'Tu base\nse afina',
    "Today's reading is missing": 'Falta la lectura de hoy',
    "Not enough context yet for a day's verdict.": 'Aún sin contexto suficiente para un veredicto del día.',
    '%lld of %lld nights calibrated': '%lld de %lld noches calibradas',
    'Got history in Apple Health? Connect it and your baseline starts ahead.': '¿Tienes historial en Apple Salud? Conéctalo y tu base arranca con ventaja.',
    'Opens Data Sources to get your baseline ahead': 'Abre Fuentes de datos para adelantar tu base',
    '· Apple Health baseline': '· base Apple Salud',
    'Tonight': 'Esta noche',
    'Opens the detail': 'Abre el detalle',

    # FER-744 follow-up — accessibility label de SEÑALES (FiveRules), antes verbatim en español.
    '%1$@: %2$lld of %3$lld points': '%1$@: %2$lld de %3$lld puntos',

    # FER-832 — sección «Forma de la noche» en Detalle de Sueño.
    'Night shape': 'Forma de la noche',
    'your heart eased off': 'bajó tu corazón',
    'lowest point': 'punto más bajo',
    'below your resting': 'bajo tu reposo',
    'of the night': 'de la noche',
    "There isn't enough signal tonight to read how your heart eased off.":
        'No hay suficiente señal esta noche para leer cómo bajó tu corazón.',
    "A marked, early drop: a sign you settled into rest. It's a pattern, not a diagnosis.":
        "Un descenso marcado y temprano: señal de que descansaste. Es un patrón, no un diagnóstico.",
    "A moderate drop overnight. It's a pattern, not a diagnosis.":
        'Un descenso moderado durante la noche. Es un patrón, no un diagnóstico.',
    "A gentler drop than a deep-rest night usually shows. It's a pattern, not a diagnosis.":
        'Un descenso más suave del que suele mostrar una noche de descanso profundo. Es un patrón, no un diagnóstico.',

    # FER-833 — bloque «VO₂max · tendencia» en Detalle de Edad de Fitness.
    'Rising': 'Subiendo',
    'Falling': 'Bajando',
    'Steady': 'Estable',

    # FER-842 — peinado i18n
    # A — préstamos (keys that had drifted out of the dict)
    "Import Apple Health export": "Importar exportación de Apple Salud",
    # C1 — comenzar → empezar
    "Get started": "Empezar",
    # C2 — meta → objetivo (whole word)
    "Enough, close to your target.": "Suficiente, cerca de tu objetivo.",
    "Right in your target range.": "Justo en tu rango objetivo.",
    "Short of your target last night.": "Corto para tu objetivo anoche.",
    "Your ceiling is a reference from your recent load and how recovered you woke up. It is context, not a goal, and you can go past it.":
        "Tu techo es un punto de referencia según tu carga reciente y qué tan recuperado amaneciste. Es contexto, no un objetivo, y puedes pasarlo.",
    # C3 — entreno → entrenamiento (whole word noun)
    "Finish workout": "Terminar el entrenamiento",
    "Finish workout?": "¿Terminar el entrenamiento?",
    "The map resets to fresh. Your workout history isn't deleted: logging a new workout loads that muscle again.":
        "El mapa vuelve a fresco. No se borra tu historial de entrenamientos: al registrar un nuevo entrenamiento, ese músculo se vuelve a cargar.",
    "Workout": "Entrenamiento",
    "You logged %lld sets. Finish to save this workout.":
        "Registraste %lld series. Toca Terminar para guardar el entrenamiento.",
    "your training": "tu entrenamiento",
    "Save keeps this workout. Discard deletes everything you logged.":
        "Guardar conserva este entrenamiento. Descartar borra todo lo que registraste.",
    # C4 — borrar → eliminar (whole word; conjugations left alone)
    "Delete this workout?": "¿Eliminar este entrenamiento?",
    "Delete what I logged": "Eliminar lo que anoté",
    "Delete workout": "Eliminar entrenamiento",
    "Borrar la media": "Eliminar la media",
    # FER-852 — HRR-60s (recuperación cardiaca post-esfuerzo, experimental)
    "Cardiac recovery · 60 s": "Recuperación cardiaca · 60 s",
    "bpm in 60 s": "bpm en 60 s",
    "No clean recovery reading for this session.":
        "No hay una lectura limpia de recuperación para esta sesión.",
    "vs your normal · ~%lld bpm · %lld sessions":
        "vs tu normal · ~%lld bpm · %lld sesiones",
    "Personal trend, not a clinical threshold. Experimental reading.":
        "Tendencia personal, no un umbral clínico. Lectura experimental.",
    "Still learning your usual recovery: keep logging sessions.":
        "Aún estoy aprendiendo tu recuperación habitual: sigue registrando sesiones.",
    "Your heart came down slower than usual after this one: a sign to watch recovery.":
        "Tu corazón bajó más lento que de costumbre tras esta: una señal para cuidar la recuperación.",
    "Your heart came down faster than usual: strong recovery after this session.":
        "Tu corazón bajó más rápido que de costumbre: buena recuperación tras esta sesión.",
    "Your recovery after this session looks like your normal.":
        "Tu recuperación tras esta sesión se ve como tu normal.",
    # FER-879 — barrido de em-dashes app-wide: claves migradas desde el catálogo (es ya limpio en FER-706).
    "Wear it snug: the sensor needs skin contact.": "Póntela ajustada, el sensor necesita contacto con la piel.",
    "It's charged and worn: the sensor wakes with skin contact.": "Está cargada y puesta, el sensor despierta con la piel.",
    "Silence the nudges during a window you choose: a meeting block, an evening wind-down.": "Silencia los avisos en una franja que elijas, un bloque de juntas, la calma de la noche.",
    "Candidate: no experiment yet": "Candidato, aún sin experimento",
    "This erases everything you contributed: your day journal and all your experiments (with their verdicts). The patterns detected from your body stay, and your imported history is untouched. This can't be undone.": "Esto borra todo lo que aportaste, tu diario y todos tus experimentos (con sus veredictos). Los patrones detectados de tu cuerpo se quedan, y tu historial importado no se toca. No se puede deshacer.",
    "You don't have to wait: an experiment speeds up what I learn about you.": "No tienes que esperar, un experimento acelera lo que aprendo de ti.",
    "Nothing proven yet: your experiments will land here.": "Nada confirmado aún, tus experimentos caerán aquí.",
    "No Apple Health data imported yet: tap Sync now to pull your recent history.": "Aún no has importado datos de Apple Salud: toca Sincronizar ahora para traer tu historial reciente.",
    "iCloud backup failed: tap to retry": "Falló el respaldo en iCloud, toca para reintentar",
    "Your heart rate across the day, in 5-minute averages. Your resting heart rate, the low while you sleep, is its own metric.": "Tu frecuencia cardiaca a lo largo del día, en promedios de 5 minutos. Tu frecuencia en reposo, la más baja mientras duermes, es una métrica aparte.",
    "Only one reading in this range: not enough to draw a line yet.": "Solo una lectura en este rango, aún no alcanza para trazar una línea.",
    "Blood oxygen comes from Apple Health. Wrist-based sensors have lower accuracy than medical pulse oximeters: treat values as a trend, not a clinical reading.": "El oxígeno en sangre viene de Apple Salud. Los sensores de muñeca son menos precisos que un oxímetro médico: tómalo como tendencia, no como una lectura clínica.",
    "Steps come from Apple Health. The detail reads each day's total and smooths it into a 7-day trend, so weekday/weekend swings don't drown out the direction you're heading. Research links roughly 7,000–9,000 steps a day with lower mortality, with the benefit leveling off beyond that: there is nothing magic about exactly 10,000.": "Los pasos vienen de Apple Salud. El detalle toma el total de cada día y lo suaviza en una tendencia de 7 días, para que los altibajos entre semana y fin de semana no tapen hacia dónde vas. La investigación asocia entre 7,000 y 9,000 pasos al día con menor mortalidad, y el beneficio se aplana más allá de eso: no hay nada mágico en los 10,000 exactos.",
    "We average your heart rate in 5-minute buckets across the day, from midnight. Your resting heart rate, the low while you sleep, is its own metric. The zones split the day by how hard your heart worked, as a percentage of your estimated maximum heart rate (zone 1 is 50–60%, zone 5 is 90–100%).": "Promediamos tu frecuencia cardiaca en tramos de 5 minutos a lo largo del día, desde medianoche. Tu frecuencia en reposo, la más baja mientras duermes, es una métrica aparte. Las zonas dividen el día según qué tan fuerte trabajó tu corazón, como porcentaje de tu frecuencia cardiaca máxima estimada (la zona 1 es 50–60%, la zona 5 es 90–100%).",
    "Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're averaged with fixed weights, HRV 60%, resting heart rate 20%, sleep 15%, skin temperature 10%, respiration 5%, and mapped onto a 0–100 scale, calibrated so a typical day lands near 58. If a signal is missing on a given night, its weight is shared among the others.": "Cada señal se convierte en un puntaje de qué tan por arriba o por abajo de tu promedio personal quedó (un z-score, en σ). Se promedian con pesos fijos, HRV 60%, FC en reposo 20%, sueño 15%, temperatura de la piel 10%, respiración 5%, y se mapean a una escala de 0 a 100, calibrada para que un día típico caiga cerca de 58. Si una señal falta una noche, su peso se reparte entre las demás.",
    "Your levels come from your own baseline: a few more nights and they'll appear.": "Tus niveles salen de tu propia base, con unas noches más aparecen.",
    "Below the recommended band: room for more volume this week.": "Por debajo de la banda recomendada: hay espacio para más volumen esta semana.",
    "Above the recommended band: a lot of volume this week.": "Por encima de la banda recomendada: mucho volumen esta semana.",
    "Still loaded: give it a day or two before training it again.": "Aún cargado: dale uno o dos días antes de volver a entrenarlo.",
    "Fresh and ready: a good muscle to train today.": "Fresco y listo: un buen músculo para entrenar hoy.",
    "Confianza baja: noche corta": "Confianza baja, noche corta",
    "Anoche dormiste menos de 6 h. Una noche corta deprime tu HRV e infla tu frecuencia en reposo aunque tu recuperación real sea mejor: así que hoy el número se lee con menos certeza. No es que estés peor: una noche corta se mide con menos confianza.": "Anoche dormiste menos de 6 h. Una noche corta deprime tu HRV e infla tu frecuencia en reposo aunque tu recuperación real sea mejor, así que hoy el número se lee con menos certeza. No es que estés peor: una noche corta se mide con menos confianza.",
    "Scale 0–21: it grows logarithmically, not a physical unit.": "Escala 0–21: crece de forma logarítmica, no es una unidad física.",
    "%@ · sparse: widened to %@": "%@ · pocas, se amplió a %@",
    # FER-137 — «Crear plan»: la puerta única de «Tres caminos» (CrearPlanScreen).
    "Create your plan": "Crear tu plan",
    "Three paths": "Tres caminos",
    "Ready-made templates, your own routine, or the plan you already have in your AI":
        "plantillas listas, tu propia rutina, o el plan que ya tienes en tu IA",
    "catalog routines": "rutinas del catálogo",
    "%lld routines": "%lld rutinas",
    "Choose exercises from the library (%lld in the catalog)": "elige ejercicios de la biblioteca (%lld en el catálogo)",
    "Import from your AI": "Importar de tu IA",
    "Choosing a template creates its routines and your week is set; you can always edit it later, day by day.":
        "Al elegir plantilla se crean sus rutinas y la semana queda armada; todo se puede editar después, día por día.",
    "Template applied · your week is set, edit it whenever": "Plantilla aplicada · semana armada, edítala cuando quieras",

    # FER-169 — F4 «Intervención»: cuando el humano decide a media sesión (La Hoja viva, B5-B13/B16b).
    # ⚠️ NO corras `python3 Tools/translate-es.py` para aplicar estas 24 — ese comando regenera el
    # catálogo ENTERO vía `json.dumps` y revierte traducciones buenas de OTRAS pantallas (drift
    # conocido de esta herramienta contra el catálogo actual, ~4000 claves con solo ~1500 en el
    # dict de abajo — ver CLAUDE.md/memoria «translate-es-dict-catalog-drift»). Estas 24 ya viven en
    # `Cenit/Resources/Localizable.xcstrings` — se insertaron A MANO, por unión, como texto crudo
    # (nunca `json.dump` del archivo completo). Este bloque queda solo como referencia legible de
    # cuáles son y qué dicen; NO es el mecanismo que las aplicó.
    # B6b «Volver a X» sobre una subida ya aplicada.
    "Back to %@ %@": "Volver a %@ %@",
    "Keep %@ %@": "Seguir en %@ %@",
    # B7 la bajada propuesta (deload en vivo).
    "Drop to %@": "Bajar a %@",
    "%lld sessions unmoved · proposes %@ %@": "%lld sesiones igual · propone %@ %@",
    "%lld sessions unmoved · goal not met": "%lld sesiones igual · sin llegar a la meta",
    # B8 «el plan cede»: saltar / sustituir / agregar / mover, desde el ··· en sesión.
    "Skip exercise · goes to the end": "Saltar ejercicio · vuelve al final",
    "Substitute · same muscle first": "Sustituir · misma zona primero",
    # B9 corregir una hecha — la explicación vive en un comentario de código, sin copy nuevo propio.
    # B10 el guard de captura absurda — «¿825 KG? es 8× tu récord» / ERA X / SÍ, N.
    "%@ %@?": "¿%@ %@?",
    "is 8× your record": "es 8× tu récord",
    "It was %@": "Era %@",
    "Yes, %@": "Sí, %@",
    # B11 récord en vivo, estricto — «RÉCORD peso máx · antes 100.0».
    "max reps": "reps máx",
    "max volume": "volumen máx",
    "before %@": "antes %@",
    "%@ × %lld": "%@ × %lld",
    # B12 tiempo/distancia con zona de FC — cronómetro compacto de La Hoja.
    "ZONE %lld · %lld": "ZONA %lld · %lld",
    "goal %@": "meta %@",
    # B5 pausada — la banda de descanso congelada dice lo mismo que la cabecera («Paused»).
    "REST · PAUSED": "DESCANSO · PAUSADO",
    "waits with you": "espera contigo",
    # B16b «¿La rutina se queda así?» al terminar con cambios hechos sobre la marcha.
    "Keep the routine this way?": "¿La rutina se queda así?",
    "Save to the routine": "Guardar en la rutina",
    "Just for today": "Solo por hoy",
    "%@ for %@": "%@ por %@",
    "%@ %lld → %lld sets": "%@ %lld → %lld series",
}


# Positional forms (%1$@) normalize to their bare specifier so reordered
# translations don't trip the parity check.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(@|lld|%)")


def main() -> int:
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]

    missing: list[str] = []
    for key, entry in strings.items():
        if not key:
            continue
        es = ES.get(key)
        if es is None:
            missing.append(key)
            continue
        locs = entry.setdefault("localizations", {})
        locs["es"] = {"stringUnit": {"state": "translated", "value": es}}

    # Keys authored here but absent from the catalog — package strings
    # (String(localized:bundle:.main) in Packages/ emits no .stringsdata) and
    # platform-gated branches the current target never compiles. Create them so
    # the runtime lookup finds them.
    #
    # ...but only when a source file still references the string (FER-994 E1).
    # This dictionary outlives the screens it was written for, so without the
    # gate every re-run would resurrect the keys Tools/find-dead-strings.py just
    # purged, silently undoing the purge.
    finder = load_finder()
    exact, normalized, raw, _files = finder.build_corpus(FINDER.parent.parent)
    created = 0
    orphans: list[str] = []
    for key, es in ES.items():
        if key in strings:
            continue
        if finder.is_alive(key, exact, normalized, raw) is None:
            orphans.append(key)
            continue
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": key}},
                "es": {"stringUnit": {"state": "translated", "value": es}},
            },
        }
        created += 1

    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")

    translated = sum(
        1 for k, v in strings.items()
        if k and "es" in v.get("localizations", {})
    )
    print(f"Spanish units written: {translated} (created {created} manual keys)")
    if orphans:
        print(
            f"skipped {len(orphans)} dictionary entries whose string no source file "
            "references (dead copy from retired screens; not resurrected)"
        )

    # Placeholder parity between source and translation (the frame%@ key
    # intentionally drops its plural-suffix argument).
    intentional = {"%lld frame%@ captured this session."}
    for k, v in ES.items():
        if k in intentional:
            continue
        if sorted(PLACEHOLDER.findall(k)) != sorted(PLACEHOLDER.findall(v)):
            print(f"PLACEHOLDER MISMATCH: {k!r} -> {v!r}")

    if missing:
        print(f"MISSING ({len(missing)}):")
        for k in missing:
            print("  " + repr(k))
    return 1 if missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
