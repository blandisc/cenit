# FER-523 · Spike Series 12 (DESECHABLE)

Investigación desechable. Responde una sola pregunta:

> ¿Un Apple Watch Series 12 entrega a HealthKit frecuencia cardiaca cada ~5 s y `heartRateVariabilityRMSSD` denso durante la noche?

Si sí, se puede activar la capa densa que el motor ya sabe usar (decisión 2026-09-14 / 2026-07-24) **sin tocar el motor**.

## Hallazgo de SDK (antes del device)

En el SDK de **iOS 27.0** (Xcode 27) el tipo **sí existe**:

- ObjC: `HKQuantityTypeIdentifierHeartRateVariabilityRMSSD` (`API_AVAILABLE(ios(27.0), …)`)
- Swift: `HKQuantityTypeIdentifier.heartRateVariabilityRMSSD`

La sonda pide ese tipo en iOS 27+. Si el runtime no lo resuelve, cae a `heartRateVariabilitySDNN` y lo anota en el reporte.

## Cómo activar el flag

Todo el spike vive bajo `#if DEBUG && CENIT_SPIKE_SERIES12`. Release nunca lo ve.

1. En `project.yml`, target `Cenit` → `settings.configs.Debug`, descomenta:

   ```yaml
   SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) DEBUG CENIT_SPIKE_SERIES12
   ```

   (o añade `CENIT_SPIKE_SERIES12` a las condiciones activas de Debug en Xcode).

2. Regenera el proyecto: `xcodegen generate`

3. Compila **Debug** en un iPhone con HealthKit (lo corre el director / el dueño). Simulador sin reloj no sirve para el verdicto final.

4. Abre **Ajustes → Fuentes de datos**. Bajo Apple Salud aparece la fila **Spike Series 12 (densidad)**.

## Qué medir (una noche con el Series 12 puesto)

1. Duerme **una noche completa** con el Series 12 puesto y con registro de sueño en Salud.
2. A la mañana, abre la pantalla del spike y toca **Medir última noche**.
3. La sonda:
   - pide/confirma lectura de FC + HRV (RMSSD si existe; si no, SDNN);
   - toma la ventana de sueño de la última noche, o las últimas 8 h si no hay sueño;
   - cuenta muestras de FC, intervalo mediano entre muestras y cobertura horaria;
   - cuenta muestras de HRV y su cadencia;
   - compara contra el baseline de un Watch «normal» (FC esparcida + HRV ~1/noche).

## Criterio GO / NO-GO

| Señal | Baseline (Watch normal) | GO (capa densa) |
| --- | --- | --- |
| FC | Esparcida (minutos entre muestras) | Intervalo mediano **~5 s** (umbral spike: ≤ 8 s) y cobertura en la mayor parte de la noche |
| HRV | ~1 muestra / noche (SDNN) | **RMSSD** (o el tipo que entregue) con **varias muestras** en la noche (umbral spike: ≥ 10) y cadencia claramente sub-horaria |

Veredicto en pantalla:

- **Densidad alta detectada** → GO para activar la capa densa (issue de seguimiento vía /pm; este spike no toca el motor).
- **Densidad normal** → NO-GO; se descarta la activación hasta nueva evidencia.

Los números crudos (conteos, medianas, tipo HRV usado) viajan en el reporte de la pantalla.

## Borrar el spike

1. Borra la carpeta `Cenit/Screens/_SpikeFER523/`.
2. Quita el flag `CENIT_SPIKE_SERIES12` y la fila de entrada en `DataSourcesView` (bloque `#if DEBUG && CENIT_SPIKE_SERIES12`).
3. `xcodegen generate`.

Cero red, cero escritura a HealthKit, solo lectura on-device. No toca `Packages/**`.
