# Histórico del sistema de diseño

Fotos de un momento: auditorías, inventarios y borradores. Sirven para entender **por qué** el
sistema es como es. **No sirven para decidir el estado actual:** sus conteos y sus rutas describen
el árbol del día en que se escribieron.

Lo vigente vive un nivel arriba: [`DESIGN.md`](../DESIGN.md) (manifiesto), [`LIQUID-GLASS.md`](../LIQUID-GLASS.md)
(El Eje), [`CATALOGO.md`](../CATALOGO.md) (piezas), [`CONTRATO.md`](../CONTRATO.md) (reglas y gates),
[`ACCESIBILIDAD.md`](../ACCESIBILIDAD.md), [`LENGUAJE.md`](../LENGUAJE.md), [`I18N.md`](../I18N.md),
[`ICONOGRAFIA.md`](../ICONOGRAFIA.md).

| Archivo | Qué fue |
|---|---|
| `AUDITORIA-SISTEMA.md` | Auditoría C del paquete por dentro (2026-09-01, FER-279) |
| `AUDITORIA-USO-1.md` · `AUDITORIA-USO-2.md` | Auditorías de uso de tokens en pantallas |
| `AUDITORIA-CONSTRUCCIONES.md` | Construcciones a mano que pedían pieza |
| `INVENTARIO-UN-SOLO-VIDRIO.md` | Inventario de la unificación en un solo vidrio (épico FER-229) |
| `ICONOS-BORRADOR.md` | Borrador de la iconografía antes de `ICONOGRAFIA.md` |

`CENSO.md` / `CENSO.json` se quedan arriba: se regeneran con `Tools/DesignCensus` y `CONTRATO.md`
los usa para arbitrar.
