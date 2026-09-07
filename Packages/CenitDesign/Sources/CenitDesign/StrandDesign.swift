/// Firma del sistema visual de Cénit.
///
/// Las fichas no viven aquí: están repartidas por rol — `StrandPalette` pinta el color de un dato,
/// `StrandFont` da la voz tipográfica, `StrandMotion` marca el ritmo, y las piezas de gráfica y de
/// componente se apoyan en las tres. Este enum solo pone nombre y número al conjunto.
public enum CenitDesign {
    /// Súbela cuando la superficie de fichas cambie de forma perceptible.
    public static let version = "0.1.0"
}
