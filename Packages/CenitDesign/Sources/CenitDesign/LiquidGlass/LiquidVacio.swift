import SwiftUI

// MARK: - Liquid Glass · Vacío que enseña (FER-430 · épico FER-428 «Sistema de aprendizaje»)
//
// EL estado vacío de la app — principio «cada vacío enseña». Tres partes, siempre en este
// orden: **qué va aquí** (`queEs`), **cómo se llena** (`comoSeLlena`, con la `cuenta`
// «faltan 3 noches» si aplica) y **dónde vive o la acción** (`salida`). Sustituye a los
// vacíos bespoke de Historial / Marcas / Cuerpo / Comparar conforme L6 los migra.
//
// Hereda la voz de esos vecinos, no la reinventa: plano sobre el lienzo (sin tarjeta), alineado
// a la izquierda justo donde irán los datos, glifo `infoGlifoTitular` en tinta/500, título
// `titulo`, cuerpo que ESCALA con Dynamic Type (`cuerpoLecturaBase` vía `@ScaledMetric`, el
// patrón de `LiquidSheetHeader`) y el aire `LiquidSpace.estadoVacioAire` acuñado para este rol.
// La cuenta lleva la leyenda de `LiquidCalibracionCard` (captionLectura + dígitos
// monoespaciados). La acción es `LiquidGlassButton(.solida)` — papel opaco, no verde: un
// vacío enseña, no vende; el verde de marca se queda para el CTA de pantalla.
//
// Recibe `Text` YA resuelto por la app (desde el registro `CenitEnsenanza`): este paquete no
// conoce claves ni el catálogo de cadenas, y no importa el registro. Sin genéricos. Sin
// animación propia: un vacío es un estado quieto.
//
// Cuándo SÍ: cualquier lista/sección/pantalla que todavía no tiene datos que mostrar.
// Cuándo NO: error de lectura o aviso (`LiquidAviso`); «calibrando» con barra de progreso
// (`LiquidCalibracionCard`); una hoja entera de onboarding.

public struct LiquidVacio: View {
    /// La tercera parte del vacío: o le dices dónde vive lo que falta, o le das UNA acción.
    public enum Salida {
        /// Ruta en pie de página («Vive en Tendencias › Sueño») — cuando la pantalla no tiene
        /// una acción real que ofrecer.
        case dondeVive(Text)
        /// Un solo botón (`LiquidGlassButton(.solida)`), con SF Symbol opcional delante.
        case accion(etiqueta: Text, simbolo: String? = nil, handler: @MainActor () -> Void)
    }

    private let simbolo: String?
    private let queEs: Text
    private let comoSeLlena: Text
    private let cuenta: Text?
    private let salida: Salida?

    /// El cuerpo escala con Dynamic Type (misma técnica que `LiquidSheetHeader.explicacionSize`).
    @ScaledMetric(relativeTo: .footnote) private var cuerpoPt: CGFloat = LiquidType.cuerpoLecturaBase

    /// - Parameters:
    ///   - simbolo: SF Symbol opcional arriba del título (p. ej. `"clock.arrow.circlepath"`).
    ///   - queEs: qué va aquí — el título («Aún no hay entrenamientos»).
    ///   - comoSeLlena: cómo se llena — la frase que enseña.
    ///   - cuenta: «faltan 3 noches» — el plural lo arma la app; `nil` si no hay cuenta.
    ///   - salida: dónde vive o la acción; `nil` = solo texto.
    public init(simbolo: String? = nil,
                queEs: Text,
                comoSeLlena: Text,
                cuenta: Text? = nil,
                salida: Salida? = nil) {
        self.simbolo = simbolo
        self.queEs = queEs
        self.comoSeLlena = comoSeLlena
        self.cuenta = cuenta
        self.salida = salida
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.estadoVacioAire) {
            if let simbolo {
                Image(systemName: simbolo)
                    .font(LiquidType.infoGlifoTitular)
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            // Las tres frases se leen como UN elemento de VoiceOver, en orden.
            VStack(alignment: .leading, spacing: LiquidSpace.estadoVacioAire) {
                queEs
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    comoSeLlena
                        .font(.system(size: cuerpoPt))
                        .foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cuenta {
                        cuenta
                            .font(LiquidType.captionLectura)
                            .monospacedDigit()
                            .foregroundStyle(LiquidColor.tinta700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if case let .dondeVive(ruta) = salida {
                    ruta
                        .font(LiquidType.pie)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)

            if case let .accion(etiqueta, simboloAccion, handler) = salida {
                LiquidGlassButton(etiqueta, variant: .solida, systemImage: simboloAccion) {
                    handler()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LiquidSpace.s400)
    }
}

#if DEBUG
#Preview("Liquid · Vacío que enseña") {
    ScrollView {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            Text("solo texto").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            LiquidVacio(
                simbolo: "trophy",
                queEs: Text(verbatim: "Aún no tienes marcas"),
                comoSeLlena: Text(verbatim: "Cuando registres una serie de fuerza con peso o repeticiones, tu mejor marca aparece aquí."),
                salida: .dondeVive(Text(verbatim: "Vive en Entrenar › Progreso")))

            Text("con cuenta").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            LiquidVacio(
                simbolo: "moon",
                queEs: Text(verbatim: "Tu sueño todavía no tiene base"),
                comoSeLlena: Text(verbatim: "Cénit necesita varias noches con el reloj puesto para comparar cada noche contra tu normal."),
                cuenta: Text(verbatim: "Faltan 3 noches"),
                salida: .dondeVive(Text(verbatim: "Vive en Tendencias › Sueño")))

            Text("con acción").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            LiquidVacio(
                simbolo: "clock.arrow.circlepath",
                queEs: Text(verbatim: "Aún no hay entrenamientos"),
                comoSeLlena: Text(verbatim: "Cuando termines una sesión de fuerza, aparece aquí con su desglose, volumen y esfuerzo."),
                salida: .accion(etiqueta: Text(verbatim: "Importar de Strong o Hevy"),
                                simbolo: "square.and.arrow.down",
                                handler: {}))
        }
        .padding(.horizontal, LiquidSpace.s550)
        .padding(.vertical, LiquidSpace.s600)
    }
    .pantallaFondo()
}
#endif
