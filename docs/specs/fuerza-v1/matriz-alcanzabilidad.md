# Ola 0 · E — matriz de alcanzabilidad (barrido 1, CEN-45)

Raíz: `FuerzaRootView` (CEN-43). Criterio: un archivo se borra si ninguna navegación desde la raíz, el reloj, los widgets, la Live Activity o el onboarding llega a él. Se verificó compilando app + pruebas tras cada lote (el compilador lista lo que aún lo usaba).

## Borrado en este barrido (44 archivos, ~20 800 líneas)

| Archivo | Por qué |
| --- | --- |
| `Cenit/App/AppMap.swift` | fixture/mapa de una familia retirada (Hoy, Tendencias) |
| `Cenit/App/MapaFixtures/HoyFixtures.swift` | fixture/mapa de una familia retirada (Hoy, Tendencias) |
| `Cenit/App/MapaFixtures/TendenciasFixtures.swift` | fixture/mapa de una familia retirada (Hoy, Tendencias) |
| `Cenit/Screens/ActivityRecoverySheet.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/AjustesAvisoMatutino.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/AjustesHistorialFA.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/BandSummaryCopy.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/BodyAgeSheet.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/BreathingView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/CompareView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Cuerpo/CuerpoTabView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/CuerpoView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/CyclePhaseView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/FitnessAgeDetailView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/FusionAgreementRow.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/HealthAlertBanner.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Hoy/HojaContexto.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Hoy/HojaDecideTuDia.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Hoy/HoyModosHost.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Hoy/LiquidMetricSheetView+Demo.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/Hoy/LiquidMetricSheetView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/MetricDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/MetricDetailSupport.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/MetricExplorerView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/PreparacionDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/SkinTempDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/SleepDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/StrainDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/StressDayMapView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/StressDetailScreen.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/StressModel.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/TodayView.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/TodayViewSupport.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `Cenit/Screens/WhitespaceMetricsExperiment.swift` | pantalla de recuperación/salud sin puerta desde CEN-43 |
| `CenitApp/App/RootTabView.swift` | el dock; la raíz es la sesión (su píldora pasó a `ActiveSessionPill.swift`) |
| `CenitUnitTests/AterrizajeColorEscaleraUnicaTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/CompareExploreEscaleraUnicaTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/HistorialFAPuertaTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/MetricInfoEscaleraUnicaTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/PreparacionDetalleModeloTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/SleepCalendarUnitTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/SleepDetailModelTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/StrainEscaleraUnicaTests.swift` | prueba de una pantalla borrada |
| `CenitUnitTests/TrendCurrentDayTests.swift` | prueba de una pantalla borrada |

## Podado en archivos vivos

| Archivo | Cambio |
| --- | --- |
| `Cenit/Screens/AjustesView.swift` | Fuera: Monitoreo (vigilar señales de carga), aviso matutino, historial de FA, recalibrar recuperación y la sección Experimental (métricas nuevas, fase del ciclo). |
| `Cenit/Screens/Ayuda/AyudaScreen.swift` | La sección Cuerpo sale del índice; sus dos hojas («Qué decide tu día», «Tu contexto») se desconectan. |
| `Cenit/Screens/WorkoutDetailScreen.swift` | Las métricas experimentales quedan apagadas (su interruptor se fue con Ajustes › Experimental). |
| `Cenit/Data/Repository.swift` | La fase del ciclo deja de leer su opt-in (la pantalla se borró). |
| `CenitApp/App/ScreenshotNav.swift`, `Cenit/App/FuerzaDebugNav.swift`, `Tools/check-nav-keys.py` | Las claves de captura las atiende la raíz de Fuerza; fuera `today`/`body`/`trends`/`sleep`/`explore`/`breathe`. |

## Se queda (a propósito) para el barrido 2, con la ola 1

| Pieza | Por qué se queda hoy |
| --- | --- |
| `Cenit/Screens/Hoy/LiquidHoyBuilder*.swift`, `HoyGramatica`, `MetricLevelsHostModel` | Es el oráculo del veredicto: lo leen el hub, el reloj (`AppModel+WatchStart`) y los widgets (`TrainWidgetPublisher`), y alimenta `deferRaise`. Quitarlo cambia cómo progresa la app; va con el motor «siguiente paso» y la línea de sueño/FC en reposo. |
| `Cenit/Screens/MetricTrendChart.swift` | Sus tipos de ventana los usa la hoja de carga y el oráculo. |
| `Cenit/Screens/TrainingLoadSheet.swift`, `TrainingLoadStrip.swift`, `Cuerpo/HiloVeredictoCompacto.swift` | Los usan el hub de Entrenar (oculto en la raíz) y el mapa muscular. |
| `Packages/CenitAnalytics`, `Packages/CenitImport` | Los usa el oráculo y el import; se podan cuando el oráculo se vaya. |
| Registro de enseñanza de Hoy/Cuerpo (`CenitEnsenanza`, `docs/FEATURES.md`) | Generado; sale del índice de Ayuda ya, y su contenido se retira con el barrido 2. |

Criterio de cierre de FER-380 (`strings` del binario sin «readiness/preparación/recovery»): **pendiente del barrido 2**, porque el oráculo sigue compilado.
