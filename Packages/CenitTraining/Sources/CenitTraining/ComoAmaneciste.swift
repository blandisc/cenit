import Foundation

// ComoAmaneciste.swift — la única señal de salud que queda en Cénit Fuerza (Camino C+, 2026-10-15).
//
// Una regla corta y transparente que SOLO puede retener una subida de peso ganada; nunca baja el plan,
// nunca bloquea entrenar y nunca produce un puntaje. Lee dos números que Apple ya calcula y guarda en
// Salud: los minutos dormidos anoche y el pulso en reposo de hoy, contra tu propia mediana.
//
//   • Sueño corto: menos de 6 h. La restricción de sueño reduce la fuerza máxima en ejercicios
//     compuestos (Knowles et al., «Inadequate sleep and muscle strength: Implications for resistance
//     training», J Sci Med Sport 21(9):959–968, 2018) y el rendimiento en general (Craven et al.,
//     «Effects of Acute Sleep Loss on Physical Performance», Sports Med 52:2669–2690, 2022).
//   • Pulso en reposo alto: 7 lpm o más por encima de tu mediana de los últimos días. Un pulso
//     matutino elevado frente a la línea base personal es un marcador clásico de fatiga acumulada
//     (Achten & Jeukendrup, «Heart rate monitoring: applications and limitations», Sports Med
//     33(7):517–538, 2003; Buchheit, «Monitoring training status with HR measures», Front Physiol
//     5:73, 2014).
//
// Los dos cortes (360 min, +7 lpm) y el mínimo de días de base son PERILLAS de producto, rotuladas
// como tales: la literatura respalda la dirección, no el número exacto. Sin dato no se opina.
// Puro y sin base de datos: lo alimenta `Repository` y lo prueba `swift test`.

public enum ComoAmaneciste {

    /// Perilla: debajo de esto, anoche fue «sueño corto».
    public static let sueñoCortoMin: Double = 360
    /// Perilla: lpm por encima de tu mediana a partir de los cuales el pulso en reposo «amaneció alto».
    public static let pulsoAltoSobreBase: Double = 7
    /// Perilla: días con pulso en reposo que hacen falta para tener una mediana tuya.
    public static let minimoDiasBase = 7

    /// Lo que la regla leyó esta mañana.
    public enum Lectura: Equatable, Sendable {
        /// Ni sueño de anoche ni pulso con base suficiente: no se opina, el plan corre como está.
        case sinDato
        /// Hay dato y nada está fuera: la subida ganada pasa.
        case enRango
        /// Dormiste menos de `sueñoCortoMin` minutos.
        case sueñoCorto(minutos: Double)
        /// Tu pulso en reposo de hoy está `pulsoAltoSobreBase` lpm o más arriba de tu mediana.
        case pulsoAlto(hoy: Double, base: Double)

        /// ¿Puede pasar hoy una subida de peso ganada? Solo el sueño corto y el pulso alto la retienen.
        public var permiteSubida: Bool {
            switch self {
            case .sinDato, .enRango: return true
            case .sueñoCorto, .pulsoAlto: return false
            }
        }
    }

    /// Lee la mañana. El sueño corto manda sobre el pulso: es el más fácil de entender y de verificar.
    ///
    /// - Parameters:
    ///   - sueñoMin: minutos dormidos la noche que terminó hoy (`nil` = sin dato).
    ///   - pulsoHoy: pulso en reposo de hoy (`nil` = sin dato).
    ///   - pulsoBase: pulsos en reposo de días ANTERIORES (sin hoy), en cualquier orden.
    public static func leer(sueñoMin: Double?, pulsoHoy: Double?, pulsoBase: [Double]) -> Lectura {
        let sueño = sueñoMin.flatMap { $0 > 0 ? $0 : nil }
        if let sueño, sueño < sueñoCortoMin {
            return .sueñoCorto(minutos: sueño)
        }
        let base = pulsoBase.filter { $0 > 0 }
        var pulsoLegible = false
        if let hoy = pulsoHoy, hoy > 0, base.count >= minimoDiasBase {
            pulsoLegible = true
            let mediana = Self.mediana(base)
            if hoy - mediana >= pulsoAltoSobreBase {
                return .pulsoAlto(hoy: hoy, base: mediana)
            }
        }
        return (sueño != nil || pulsoLegible) ? .enRango : .sinDato
    }

    /// Mediana (robusta a una noche rara, a diferencia del promedio).
    static func mediana(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
