# Qué se retiró

El sistema se llama **El Eje**. El look sigue siendo vidrio teñido sobre lienzo claro (u oscuro, en modo oscuro), en mosaico o sobrio.

| Se retiró como nombre o como opción oficial | Qué queda en su lugar |
|---|---|
| El nombre «Liquid Glass» | **El Eje**. En código las recetas siguen llamándose `liquidGlass` |
| `StatTile` y los vacíos de papel | `LiquidCajita`, `LiquidMetricTile`, `LiquidVacio` |
| `Hypnogram` | `LiquidHipnograma` |
| `YearHeatStrip` | `LiquidCalendario90` |

`Hypnogram` y `YearHeatStrip` siguen en el paquete hasta que su última prueba las suelte. No se ofrecen para pantallas nuevas. El catálogo las tiene en Archivo.

El mismo catálogo marca como no aptas para una pantalla nueva las piezas que comparten trabajo con una vigente: `SegmentedPillControl`, `TrendChart`, `.patternBlock` e `InstrumentoFlowTitle`. Siguen donde ya están. Una pantalla nueva no las adopta.

## Versión

`CenitDesign.version` es **1.0.0** desde el 2026-09-22, el día en que el sistema pasó a llamarse El Eje y el catálogo dijo la verdad.

- Sube el número chico cuando entra o sale una pieza del catálogo.
- Sube el número grande cuando cambia el nombre del sistema o una regla que la persona ve.
