/// Firma del sistema visual de Cénit: El Eje.
///
/// Las fichas viven por rol (`LiquidColor`, `LiquidType`, `liquidGlass`). Este enum solo
/// pone nombre y número al conjunto.
public enum CenitDesign {
    /// 1.0.0 desde 2026-09-22: el sistema se llama El Eje y el catálogo dice la verdad.
    /// Sube el número chico cuando entra o sale una pieza del catálogo. Sube el número
    /// grande cuando cambia el nombre del sistema o una regla que la persona ve.
    /// Ver `docs/design-system/RETIRADAS.md`.
    public static let version = "1.0.0"
}
